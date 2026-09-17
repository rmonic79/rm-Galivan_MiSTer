// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) Umberto Parisi (rmonic79). GPL v3 or later.
//
// pause_text.sv — Renderer testo BRAM-based per overlay pause.
//
// Genera un layer di char (font 8x8) su un'area rettangolare dello schermo
// (W_CHARS x H_CHARS char) leggendo da una BRAM init-da-file (.mem).
//
// Modalità:
//   SCROLL_EN=0: testo statico, BRAM contiene esattamente W_CHARS×H_CHARS byte ASCII.
//   SCROLL_EN=1: testo scrolla verticalmente bottom→top, BRAM contiene
//                W_CHARS × MSG_ROWS char ASCII (MSG_ROWS può essere > H_CHARS).
//                Velocità: 1 pixel ogni SCROLL_PERIOD frame.
//
// Output: pixel_on = 1 quando il pixel del char a (render_x, render_y) è acceso.
//         Caller mixa con palette esterna.
//
// Costo BRAM:
//   font_rom: 1024 byte = 1 M10K (condiviso tra istanze tramite parameter FONT_FILE)
//   msg_rom:  W_CHARS × MSG_ROWS byte (1 M10K se < ~4 KB)

module pause_text #(
	parameter        CHAR_W       = 8,            // larghezza della cella in px (6 o 8)
	parameter        W_CHARS      = 41,           // larghezza area in char
	parameter        H_CHARS      = 18,           // altezza area visibile in char
	parameter        MSG_ROWS     = 18,           // righe totali nel buffer (>= H_CHARS)
	parameter [9:0]  ORIGIN_X     = 10'd16,       // pixel X dell'angolo top-left
	parameter [8:0]  ORIGIN_Y     = 9'd40,        // pixel Y dell'angolo top-left
	parameter        SCROLL_EN    = 0,            // 0=statico, 1=scroll verticale
	parameter        SCROLL_PERIOD = 3,           // 1 pixel ogni N frame (se SCROLL_EN=1)
	parameter        FONT_FILE    = "logo/font_darius.hex",
	parameter        MSG_FILE     = "logo/links.mem"
) (
	input  wire        clk,
	input  wire        active,        // overlay attivo (pause & ~clean)
	input  wire        vblank_pulse,  // 1 ciclo per frame, per tick scroll

	input  wire [9:0]  render_x,
	input  wire [8:0]  render_y,

	output reg         pixel_on,      // 1 = pixel acceso del char
	output reg  [1:0]  pixel_tier     // tier color (0..3) per il pixel corrente
);

// Larghezza dell'area in pixel: CHAR_W, non 8 cablato.
// Con 8 fisso e celle da 6 px l'area risultava larga 288 invece di 216, il
// modulo disegnava oltre la fine della riga, char_col superava W_CHARS-1 e
// msg_addr sconfinava nella riga SUCCESSIVA del buffer: il testo ricominciava
// a scriversi di fianco. L'altezza resta 8, il glifo e' alto 8 in tutti i casi.
localparam W_PX = W_CHARS * CHAR_W;
localparam H_PX = H_CHARS * 8;

// =====================================================================
// Scroll counter: pixel offset verticale (0..MSG_ROWS*8-1, wrap continuo)
// =====================================================================
localparam MSG_PX = MSG_ROWS * 8;
localparam SCRPOSW = $clog2(MSG_PX + 1);

reg [SCRPOSW-1:0] scrpos;
reg [3:0]         scr_div;

always @(posedge clk) begin
	if (!active) begin
		scrpos  <= '0;
		scr_div <= 4'd0;
	end else if (SCROLL_EN && vblank_pulse) begin
		if (scr_div == SCROLL_PERIOD - 1) begin
			scr_div <= 4'd0;
			if (scrpos == MSG_PX - 1)
				scrpos <= '0;
			else
				scrpos <= scrpos + 1'b1;
		end else begin
			scr_div <= scr_div + 4'd1;
		end
	end
end

// =====================================================================
// Read-ahead 1 pixel su render_x per allineare pipeline BRAM
// =====================================================================
wire [9:0] x_ahead = render_x + 10'd1;

// In-bounds check (su pixel ahead)
wire in_area_ahead = active &&
	(x_ahead   >= ORIGIN_X) && (x_ahead   < ORIGIN_X + W_PX) &&
	(render_y  >= ORIGIN_Y) && (render_y  < ORIGIN_Y + H_PX);

// Pixel relativi all'area (0..W_PX-1, 0..H_PX-1)
wire [9:0] dx = x_ahead - ORIGIN_X;
wire [9:0] dy_rel = {1'b0, render_y} - {1'b0, ORIGIN_Y};

// Y effettiva (con scroll wrap)
// SCROLL_EN=1: dy_eff = (dy_rel + scrpos) mod MSG_PX
// SCROLL_EN=0: dy_eff = dy_rel (sempre nel buffer di H_CHARS×8)
wire [SCRPOSW-1:0] dy_sum   = dy_rel[SCRPOSW-1:0] + scrpos;
wire [SCRPOSW-1:0] dy_wrap  = (dy_sum >= MSG_PX) ? (dy_sum - MSG_PX) : dy_sum;
wire [SCRPOSW-1:0] dy_eff   = SCROLL_EN ? dy_wrap : dy_rel[SCRPOSW-1:0];

// Char column / pixel column (within char)
//
// La cella non e' piu' per forza 8 px, quindi la divisione non e' piu' uno
// scorrimento. Si usa il reciproco: char_col = (dx * RECIP) >> 16 con
// RECIP = 0xFFFF/CHAR_W + 1. L'arrotondamento per eccesso e' quello che rende
// esatta la divisione intera; verificato ESAUSTIVAMENTE per CHAR_W 6 e 8 su
// tutto il campo utile (0..40 celle), divisione e resto.
localparam [15:0] RECIP  = 16'hFFFF / CHAR_W + 16'd1;
localparam        DXW    = $clog2(W_CHARS*CHAR_W + 1);

wire [DXW+15:0] dx_mul   = dx[DXW-1:0] * RECIP;
wire [$clog2(W_CHARS+1)-1:0] char_col_c = dx_mul[DXW+15:16];

// Il resto va calcolato a larghezza PIENA: char_col arriva a 36 e
// char_col*CHAR_W a 216, quindi troncare gli operandi a quattro bit darebbe
// una colonna sbagliata a meta' riga.
wire [DXW-1:0] pix_col_full = dx[DXW-1:0] - char_col_c * CHAR_W;

// TIMING — colonna e resto REGISTRATI.
//
// Senza questo registro il percorso e': contatore -> dx -> moltiplicazione per
// il reciproco -> char_col -> SECONDA moltiplicazione dentro msg_addr ->
// indirizzo della BRAM, tutto in un colpo di clock. Due moltiplicatori in
// serie su un indirizzo di memoria: il timing crolla (misurato, -1.6 ns).
//
// Costa zero perche' la colonna viene dall'asse LENTO: nel modo in cui
// l'overlay e' montato, render_x avanza una volta per RIGA, non per pixel, e
// la zona disegnata comincia decine di cicli dopo che e' cambiato. Un ciclo di
// ritardo sparisce dentro quel margine. L'asse veloce (riga dentro il
// carattere) resta combinatorio come prima, quindi l'allineamento col dato del
// font non cambia.
reg [$clog2(W_CHARS+1)-1:0] char_col;
reg [3:0]                   pix_col;
always @(posedge clk) begin
	char_col <= char_col_c;
	pix_col  <= pix_col_full[3:0];
end

// Char row / pixel row (within char)
wire [$clog2(MSG_ROWS+1)-1:0] char_row = dy_eff[SCRPOSW-1:3];
wire [2:0]                    pix_row = dy_eff[2:0];

// =====================================================================
// MSG ROM: W_CHARS × MSG_ROWS word, 9-bit per char (2 bit tier + 7 bit ASCII)
// =====================================================================
localparam MSG_DEPTH = W_CHARS * MSG_ROWS;
localparam MSG_AW    = $clog2(MSG_DEPTH);

(* ramstyle = "M10K" *) reg [8:0] msg_rom [0:MSG_DEPTH-1];
initial $readmemh(MSG_FILE, msg_rom);

wire [MSG_AW-1:0] msg_addr = char_row * W_CHARS + char_col;
reg  [8:0] msg_q;
always @(posedge clk) msg_q <= msg_rom[msg_addr];

wire [1:0] msg_tier  = msg_q[8:7];
wire [6:0] msg_ascii = msg_q[6:0];

// =====================================================================
// FONT ROM: 1024 byte = 128 char × 8 row
// Stessa BRAM per tutte le istanze grazie a init file shared.
// =====================================================================
(* ramstyle = "M10K" *) reg [7:0] font_rom [0:1023];
initial $readmemh(FONT_FILE, font_rom);

// pix_row deve essere ritardato 1 ciclo per allinearsi con msg_q
reg [2:0] pix_row_d;
reg [3:0] pix_col_d;
reg       in_area_d;
always @(posedge clk) begin
	pix_row_d <= pix_row;
	pix_col_d <= pix_col;
	in_area_d <= in_area_ahead;
end

wire [9:0] font_addr = {msg_ascii, pix_row_d};
reg  [7:0] font_row;
reg  [1:0] tier_d;
always @(posedge clk) begin
	font_row <= font_rom[font_addr];
	tier_d   <= msg_tier;
end

// pix_col va ritardato di 2 cicli totali (msg_q→font_addr→font_row)
reg [3:0] pix_col_dd;
reg       in_area_dd;
reg [1:0] tier_dd;
always @(posedge clk) begin
	pix_col_dd <= pix_col_d;
	in_area_dd <= in_area_d;
	tier_dd    <= tier_d;
end

// Output: bit pix_col_dd del font_row corrente, gated da in_area
always @(posedge clk) begin
	pixel_on   <= in_area_dd && font_row[7 - pix_col_dd];
	pixel_tier <= tier_dd;
end

endmodule
