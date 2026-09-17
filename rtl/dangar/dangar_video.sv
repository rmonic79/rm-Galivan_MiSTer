// SPDX-License-Identifier: GPL-3.0-or-later
/*  This file is part of rmGalivan_MiSTer.
    Author: Umberto Parisi (rmonic79)

    dangar_video.sv — renderer di Ufo Robo Dangar (hardware Galivan GV-1412).

    ---------------------------------------------------------------------------
    FORMATI GRAFICI — presi dai gfx_layout del driver, NON dedotti
    ---------------------------------------------------------------------------
    gfx_8x8x4_packed_lsb (char, galivan.cpp:1101) e gfx_16x16x4_packed_lsb
    (tile, :1102) hanno xoffs = { 1*4, 0*4, 3*4, 2*4, ... }, col commento di MAME
    "x order : low nibble first, hi nibble second" (reference/mame_generic_gfx.cpp:114
    e :129). Quindi  byte = x>>1,  nibble BASSO se x PARI, ALTO se x DISPARI.
    Attenzione: NON e' STEP(0,4) — quello e' il `_packed_msb`, che ha i nibble al
    contrario. Il nome del layout va letto, non indovinato.

    spritelayout (galivan.cpp:1087-1098) ha in piu' l'interlacciamento delle meta':
        xoffs = { 1*4, 0*4, F+1*4, F+0*4, 3*4, 2*4, F+3*4, F+2*4,
                  5*4, 4*4, F+5*4, F+4*4, 7*4, 6*4, F+7*4, F+6*4 }   F = RGN_FRAC(1,2)
      da cui, pixel per pixel:  meta' regione = x[1],  byte = x>>2,
      e il NIBBLE segue la stessa regola di char e tile (pari = basso), perche' la
      sequenza e' la solita coppia scambiata `1*4, 0*4` dei layout `*_packed_lsb`.
      Sbagliare il nibble scambia i pixel a coppie dentro ogni sprite: il gioco parte
      lo stesso e non lo segnala niente, si vedono solo i bordi "seghettati".
      Il numero di elementi e' RGN_FRAC(1,2)/64 = 32768/64 = 512, cioe' codice a
      9 bit: la formula del driver e' code = byte1 + ((attr & 0x06) << 7) (:643) ma
      il bit 9 cade fuori dai 512 elementi e MAME lo fa rientrare con il modulo,
      quindi conta solo attr[1]. Il banco palette invece indicizza con il codice a
      10 bit >> 2 = 8 bit; la PROM 82s129.7f e' specchiata (i 128 byte alti sono
      identici ai bassi), percio' bastano i 7 bit bassi.

    ---------------------------------------------------------------------------
    LIVELLI
    ---------------------------------------------------------------------------
    TESTO  galivan.cpp:467-476 — char RAM 2 KB: 0x000-0x3FF codici, 0x400-0x7FF attr
           code = ram[i] | ((attr & 0x01) << 8)   color = (attr & 0x78) >> 3
           tilemap 32x32 di 8x8, TILEMAP_SCAN_COLS (:514): indice = x_tile*32 + y_tile
           pen trasparente 15 (:516). Non scrolla. Le due draw() per categoria
           (:663-664) disegnano l'intera tilemap in due passate consecutive senza
           niente in mezzo: l'effetto e' identico a una passata sola.

    BG     galivan.cpp:457-465 — mappa in ROM: 0x0000-0x3FFF codici, 0x4000-0x7FFF attr
           code = rom[i] | ((attr & 0x03) << 8)   color = (attr & 0x78) >> 3
           tilemap 128x128 di 16x16 SCAN_ROWS (:513), scroll 11 bit (:655-656). Opaco.

    SPRITE galivan.cpp:617-650 — 64 sprite da 4 byte, spriteram bufferizzata a inizio
           VBlank (:1178,1182). byte0 Y, byte1 code_lo, byte2 attr, byte3 X.
           attr: b0 X bit8, b1 code bit8, b2-5 color, b6 flipx, b7 flipy
           sx = (X-0x80) + 256*(attr&1)    sy = 240 - Y
           il loop di MAME va da 0 a 63 (:624): lo sprite 63 sta SOPRA, quindi nel
           line buffer si scrive nello stesso ordine e l'ultimo vince.

    PRIORITA galivan.cpp:658-680, bit 5-7 della porta 0x42:
           bit6 (layers[1]) = 1  -> bg spento, schermo riempito con pen 0
           bit7 (layers[2]) = 1  -> testo spento
           bit5 (layers[0]) = 1  -> testo PRIMA, sprite SOPRA
                              0  -> sprite prima, testo SOPRA

    COLORE galivan.cpp:355-402, verificato termine per termine:
             testo  idx = pen | (pen[3] ? (color & 0x0c) << 2 : (color & 0x03) << 4)
             bg     idem | 0xC0
             sprite idx = 0x80 | (pen[3] ? (bank & 0x0c) << 2 : (bank & 0x03) << 4)
                              | (lookup[color*16 + pen] & 0x0f)
           PROM: R 0x000, G 0x100, B 0x200, lookup sprite 0x300 (galivan.cpp:1423-1426).

    ---------------------------------------------------------------------------
    ARCHITETTURA — DUE LINE BUFFER, NIENTE MEMORIA LENTA DENTRO IL PIXEL
    ---------------------------------------------------------------------------
    Il background sta in SDRAM, che ha latenza VARIABILE: non si puo' leggere
    dentro il pixel. Invece di rincorrere il confine del tile con un prefetch (che
    va a sbattere sul primo tile di ogni riga e sullo scroll non allineato a 16),
    il background si costruisce a RIGA INTERA, come gli sprite: mentre si disegna
    la riga L si riempie il buffer della riga L+1, un tile per volta, 17 colonne
    (16 piene + i due mezzi bordi dello scroll). Costa ~2400 cicli su 6144
    disponibili per riga, e nel pixel si legge solo un buffer.
    Gli sprite hanno gia' il loro line buffer doppio con la stessa cadenza.
    Nel percorso pixel restano quindi solo BRAM a latenza fissa: char RAM,
    ROM char, ROM sprite, PROM, e i due line buffer.
*/

`timescale 1ns / 1ps

module dangar_video
(
	input             clk,
	input             reset,
	input             ce_pix,

	input      [9:0]  hcnt,
	input      [9:0]  vcnt,

	input      [12:0] scroll_x,
	input      [12:0] scroll_y,
	input      [2:0]  layers,
	input             flip_screen,

	output     [10:0] cram_addr,
	input      [7:0]  cram_data,
	output     [8:0]  spr_addr,
	input      [7:0]  spr_data,

	output     [14:0] bgmap_addr,
	input      [7:0]  bgmap_data,

	output reg [16:0] tile_addr,      // SDRAM
	output reg        tile_req,
	input      [7:0]  tile_data,
	input             tile_ok,
	input             tile_busy,

	output     [14:0] char_addr,
	input      [7:0]  char_data,
	output     [16:0] sprrom_addr,
	input      [7:0]  sprrom_data,

	input             board_ninjemak,
	input             board_youmab,
	input             board_ninjemat,
	output     [9:0]  prom_addr,
	input      [7:0]  prom_data,
	output     [7:0]  sprbank_addr,
	input      [7:0]  sprbank_data,

	input             en_bg,
	input             en_txt,
	input             en_spr,

	output     [23:0] rgb
);

// La licenza Tecfri (`ninjemat`) ha l'I/O di Galivan ma il VIDEO di Ninja
// Emaki, ricavato dalle sue ROM: 1024 caratteri con due bit di codice
// nell'attributo (la tile dello spazio e' la 0x320, l'unica uniforme, e
// l'init pulisce lo schermo con attributo $7B), colore del testo a tre bit,
// colore dello sfondo col bit 2 dell'attributo (che Galivan ignora e che
// nella sua mappa e' usato nel 61,5% delle celle), 128 sprite da 128 KB.
// Fanno eccezione DUE cose, che restano di Galivan e per questo NON passano
// di qui: la mappa di sfondo, che e' 128x128 SCAN_ROWS (correlazione a passo
// 128: 79,7% contro il 20,9% del passo 32), e il clamp delle 18 celle, che
// esiste solo per il blitter — e il blitter, su questa scheda, non c'e'.
wire nj_video = board_ninjemak | board_ninjemat;

// =====================================================================
// Fase dentro il pixel: 16 cicli di clk per ce_pix.
//
// Nella finestra in cui hcnt vale H si calcola IL PIXEL H e lo si presenta al
// ce_pix che chiude la finestra. E' l'unico allineamento coerente: a quel fronte
// il consumatore (gamma_fast) campiona insieme il colore e DE/HBlank, e DE lo
// calcola da hcnt PRIMA del fronte, cioe' proprio da H. Calcolare H+1, come
// faceva la versione precedente, sposta il colore di un pixel rispetto al blank
// e — peggio — nella finestra hcnt=383 calcola il pixel 0 della riga DOPO
// mentre i line buffer non sono ancora stati scambiati: prima colonna dello
// schermo presa dalla riga sbagliata.
//
// Rosso, verde e blu devono essere tutti fermi PRIMA di quel fronte: la catena
// PROM finisce a ph 14, non a ph 15.
// =====================================================================
reg [3:0] ph;
always @(posedge clk) if (reset) ph <= 4'd0; else ph <= ce_pix ? 4'd0 : (ph + 4'd1);

// I registri di controllo vivono in dangar_main: usarli qui in combinatoria
// significa attraversare il chip da un'istanza all'altra e poi entrare
// nell'indirizzo delle BRAM. Il percorso peggiore del core era esattamente
// questo (flip_r -> lb_q, slack +0.012 ns). Sono segnali quasi statici — il
// flip cambia una volta all'avvio, scroll e layer una volta per fotogramma —
// quindi un ciclo di ritardo su 96 MHz non si vede, e il routing lungo esce
// dal percorso critico.
reg  [12:0] scroll_x_q, scroll_y_q;
reg  [2:0]  layers_q;
reg         flip_q;
always @(posedge clk) begin
	scroll_x_q <= scroll_x;
	scroll_y_q <= scroll_y;
	layers_q   <= layers;
	flip_q     <= flip_screen;
end

wire [8:0] lx = flip_q ? (9'd255 - hcnt[8:0]) : hcnt[8:0];
wire [8:0] ly = flip_q ? (9'd255 - vcnt[8:0]) : vcnt[8:0];

// riga logica che i due line buffer stanno preparando (quella dopo di questa)
wire [8:0] ly_next = flip_q ? (ly - 9'd1) : (ly + 9'd1);

// Inizio riga: a questo fronte hcnt torna a 0 e vcnt avanza, quindi lo scambio
// dei buffer avviene ESATTAMENTE prima che si calcoli il pixel 0 della riga nuova.
wire line_start = ce_pix & (hcnt == 10'd383);

// =====================================================================
// TESTO — tutto in BRAM, dentro il pixel.
//   ph0  indirizzo codice     ph2  codice + indirizzo attributo
//   ph4  attributo            ph6  grafica  (pronta per la PROM a ph8)
// =====================================================================
// SCAN_COLS: indice = x*32 + y
wire [9:0] tx_ix_raw = {lx[7:3], ly[7:3]};

// Su Ninja Emaki le prime 18 celle della VRAM testo NON sono caratteri: sono i
// parametri del blitter NB1414M4 (comando, input, DSW, crediti, scroll). MAME
// non le disegna, le sostituisce tutte con la cella 0x12
// (galivan.cpp, ninjemak_state::get_tx_tile_info: `if (index < 0x12) index = 0x12`).
// Senza questo si vedono i byte di parametro disegnati come caratteri: e'
// l'artefatto in alto a sinistra.
// ...ma il bootleg Game Electronics il chip NON CE L'HA: l'hanno tolto dalla
// scheda e sostituito con codice proprio. Quelle 18 celle non sono parametri
// di nessuno, sono caratteri normali, e il codice del bootleg ci scrive la sua
// interfaccia (21 riferimenti a $D800-$D80F nelle sue tre ROM). Nasconderle
// faceva cominciare la GUI 18 celle piu' avanti.
wire [9:0] tx_ix = (board_ninjemak && !board_youmab && tx_ix_raw < 10'd18)
                 ? 10'd18 : tx_ix_raw;
reg [10:0] cram_a;
assign cram_addr = cram_a;
reg [7:0] tx_code_lo, tx_attr;

always @(posedge clk) begin
	case (ph)
	4'd0: cram_a <= {1'b0, tx_ix};
	4'd2: begin tx_code_lo <= cram_data; cram_a <= {1'b1, tx_ix}; end
	4'd4: tx_attr <= cram_data;
	default: ;
	endcase
end

wire [9:0] tx_code  = nj_video ? {tx_attr[1:0], tx_code_lo}
                               : {1'b0, tx_attr[0], tx_code_lo};
wire [3:0] tx_color = nj_video ? {1'b0, tx_attr[4:2]} : tx_attr[6:3];
assign char_addr = {tx_code, ly[2:0], lx[2:1]};    // byte = x>>1
reg [7:0] tx_gfx;
always @(posedge clk) if (ph == 4'd6) tx_gfx <= char_data;
wire [3:0] tx_pen = lx[0] ? tx_gfx[7:4] : tx_gfx[3:0];   // nibble alto se x dispari

// =====================================================================
// BACKGROUND — line buffer doppio, riempito durante la riga precedente.
//
// Si copre l'intera riga logica lx = 0..255 con 17 colonne di tile: la prima
// comincia a lx = -scroll_x[3:0] (puo' essere parzialmente fuori a sinistra) e
// l'ultima sborda a destra. I pixel fuori da [0,255] si scartano.
//   indice mappa = riga_tile*128 + colonna_tile   (TILEMAP_SCAN_ROWS, :513)
//   la colonna si tronca a 7 bit: la tilemap e' 128x128 e si avvolge da sola.
// =====================================================================
reg  [7:0] bgb0 [0:255];
reg  [7:0] bgb1 [0:255];
reg  [7:0] bgb_q;

reg  [12:0] bg_sx;         // scroll X latchato a inizio riga (13 bit: 512 tile)
reg  [6:0]  bg_ty;         // riga di tile
reg  [3:0]  bg_ry;         // riga dentro il tile
reg  [4:0]  bg_c;          // colonna in corso, 0..16
reg  [2:0]  bg_b;          // byte in corso della riga di tile, 0..7
reg  [7:0]  bg_code_lo, bg_attr, bg_gfx;
reg  [14:0] bgmap_a;
assign bgmap_addr = bgmap_a;

wire [9:0]  bg_code  = {bg_attr[1:0], bg_code_lo};
wire [3:0]  bg_col_t = nj_video ? {bg_attr[6:5], bg_attr[3:2]} : bg_attr[6:3];
wire [12:0] bgy_n    = {4'd0, ly_next} + scroll_y_q;

// Colonna di tile in corso, 9 bit: su Ninja Emaki la tilemap e' larga 512 tile
// e si avvolge li'; su Galivan e' 128x128 e si tronca a 7 bit come prima.
wire [8:0]  bg_tx    = bg_sx[12:4] + {4'd0, bg_c};

// SCAN_COLS su Ninja Emaki: indice = colonna*32 + riga (galivan.cpp:521).
// SCAN_ROWS su Galivan:     indice = riga*128 + colonna (galivan.cpp:513).
// Quattordici bit in entrambi i casi, e' solo un ordine diverso dei campi.
wire [13:0] bg_mapix = board_ninjemak ? {bg_tx, bg_ty[4:0]}
                                      : {bg_ty, bg_tx[6:0]};

// posizione in buffer dei due pixel del byte corrente
wire [9:0]  bg_pos0 = {1'd0, bg_c, 4'd0} + {6'd0, bg_b, 1'b0} - {6'd0, bg_sx[3:0]};
wire [9:0]  bg_pos1 = bg_pos0 + 10'd1;
wire        bg_ok0  = (bg_pos0[9:8] == 2'b00);
wire        bg_ok1  = (bg_pos1[9:8] == 2'b00);
// byte = x>>1, nibble alto se x dispari: il pixel PARI e' il nibble basso
wire [3:0]  bg_pen0 = bg_gfx[3:0];
wire [3:0]  bg_pen1 = bg_gfx[7:4];

localparam G_LAT=4'd0, G_M0=4'd1, G_M0W=4'd2, G_M1=4'd3, G_M1W=4'd4,
           G_AT=4'd5,   G_REQ=4'd6, G_WT=4'd7, G_W0=4'd8, G_W1=4'd9, G_NX=4'd10,
           G_IDLE=4'd11;
reg [3:0] gs;

// =====================================================================
// SPRITE — line buffer doppio, stessa cadenza del background.
// Tutte le sorgenti (spriteram, PROM banco, ROM sprite) sono BRAM: fra
// indirizzo e dato ci vuole UN ciclo, quindi ogni lettura ha il suo stato
// di attesa. Senza, si legge il byte della lettura precedente.
// =====================================================================
localparam S_IDLE=4'd0,  S_A0=4'd1,  S_D0=4'd2,  S_A1=4'd3,  S_D1=4'd4,
           S_A2=4'd5,    S_D2=4'd6,  S_A3=4'd7,  S_D3=4'd8,
           S_BNK=4'd9,   S_BNK2=4'd10, S_FE=4'd11, S_FE2=4'd12,
           S_PX0=4'd13,  S_PX1=4'd14, S_NXT=4'd15;

reg [3:0] ss;
reg [6:0] sidx;
reg [7:0] s_y, s_code_lo, s_attr, s_x;
reg [3:0] s_bank;
reg [2:0] s_pair;
reg [7:0] s_gfx;
reg [8:0] s_spra;
reg       wbuf;

assign spr_addr = s_spra;

wire [8:0] sy_raw  = 9'd240 - {1'b0, s_y};
wire [8:0] sy_eff  = flip_q ? (9'd240 - sy_raw) : sy_raw;
wire [8:0] dy      = ly_next - sy_eff;
wire       on_line = (dy < 9'd16);
wire       fy      = s_attr[7] ^ flip_q;
wire       fx      = s_attr[6] ^ flip_q;
wire [3:0] srow    = dy[3:0] ^ {4{fy}};
wire [8:0] sx_raw  = ({1'b0, s_x} - 9'd128) + {s_attr[0], 8'd0};
wire [8:0] sx_eff  = flip_q ? (9'd240 - sx_raw) : sx_raw;
wire [9:0] scode   = nj_video ? {s_attr[2], s_attr[1], s_code_lo}
                              : {1'b0, s_attr[1], s_code_lo};
wire [3:0] scol    = s_attr[5:2];                   // (attr & 0x3c) >> 2

// meta' della regione = x[1] = pair[0], byte = x>>2 = pair[2:1]
// s_pair[0] seleziona la META' DELLA REGIONE sprite, quindi deve stare sul bit
// piu' alto della regione VERA — e le due schede non hanno la stessa:
//   Galivan / Dangar  64 KB  -> meta' = bit 15
//   Ninja Emaki      128 KB  -> meta' = bit 16
//
// REGRESSIONE 2026-09-13, trovata dall'utente: allargando `scode` da 9 a 10 bit
// per Ninja Emaki, s_pair[0] e' passato da bit 15 a bit 16 anche per gli altri
// set. Su una regione da 64 KB significa che META' della grafica veniva letta
// OLTRE la regione, cioe' da zeri: sprite rotti su Dangar e Galivan.
assign sprrom_addr  = nj_video ? {s_pair[0], scode, srow_r, s_pair[2:1]}
                               : {1'b0, s_pair[0], scode[8:0], srow_r, s_pair[2:1]};
// m_sprpalbank[code >> 2] (galivan.cpp:646) con il codice a 10 bit: i 7 bit che
// restano bastano perche' la PROM 82s129.7f e' specchiata sui 128 byte alti.
assign sprbank_addr = scode[9:2];

// TIMING: sx_eff, fx e srow dipendono da flip_q, e sono COSTANTI per tutto lo
// sprite — dipendono solo da s_x, s_attr e dalla riga. Lasciarli combinatori
// significava far arrivare flip_q, attraverso due sottrazioni e una somma, fino
// al decode a 256 vie degli indirizzi dei line buffer: era il percorso critico
// del core. Si campionano UNA volta in S_BNK, dove s_x e s_attr sono gia'
// latchati e mancano due cicli a S_FE. Il valore scritto e' identico.
reg [8:0] sx_eff_r;
reg [3:0] srow_r;
reg       fx_r;

wire [3:0] col_base = {s_pair[2:1], s_pair[0], 1'b0};
wire [3:0] cb0 = fx_r ? (4'd15 - col_base)          : col_base;
wire [3:0] cb1 = fx_r ? (4'd15 - (col_base + 4'd1)) : (col_base + 4'd1);
wire [8:0] wx0 = sx_eff_r + {5'd0, cb0};
wire [8:0] wx1 = sx_eff_r + {5'd0, cb1};
// Nibble: come char e tile, il pixel PARI e' il nibble BASSO.
// Dimostrazione, non deduzione: xoffs dello spritelayout parte con { 1*4, 0*4, ... }
// (galivan.cpp:1093), cioe' il pixel x=0 sta a bitnum 4. readbit di MAME e'
// MSB-first (bitnum 4 = bit 3 del byte 0), e decodechar mette plane0 nel bit piu'
// alto del pixel: pixel(x=0) = byte[3:0]. E' lo stesso schema dei layout generici
// `*_packed_lsb`, che nel sorgente MAME portano il commento
// "x order : low nibble first, hi nibble second" (reference/mame_generic_gfx.cpp:114).
wire [3:0] pen0 = s_gfx[3:0];
wire [3:0] pen1 = s_gfx[7:4];

reg [12:0] lb0 [0:255];
reg [12:0] lb1 [0:255];
reg [12:0] lb_q;

// azzeramento del buffer sprite che torna in scrittura: deve finire PRIMA che
// la macchina degli sprite cominci a scriverci, altrimenti si cancellano pixel
// gia' disegnati. 256 cicli su 6144: si fa in testa alla riga e basta.
reg [7:0] clr_a;
reg       clearing;

// -----------------------------------------------------------------
// UNICO blocco che scrive i due line buffer sprite: azzeramento e macchina
// stanno insieme perche' due always separati sullo stesso array sono due
// driver — Quartus non inferisce piu' la M10K e in simulazione e' una corsa.
// -----------------------------------------------------------------
always @(posedge clk) begin
	if (reset) begin
		ss <= S_IDLE; sidx <= 7'd0; clearing <= 1'b0; clr_a <= 8'd0; wbuf <= 1'b0;
	end else begin
		if (line_start) begin
			wbuf     <= ~wbuf;
			clearing <= 1'b1;
			clr_a    <= 8'd0;
			ss       <= S_IDLE;
		end
		else if (clearing) begin
			if (wbuf) lb1[clr_a] <= 13'd0; else lb0[clr_a] <= 13'd0;
			clr_a <= clr_a + 8'd1;
			if (clr_a == 8'd255) clearing <= 1'b0;
		end
		else begin
			case (ss)
			S_IDLE:  begin sidx <= 7'd0; s_spra <= 9'd0; ss <= S_A0; end
			S_A0:    ss <= S_D0;                               // attesa BRAM
			S_D0:    begin s_y <= spr_data;       s_spra <= {sidx, 2'd1}; ss <= S_A1; end
			S_A1:    ss <= S_D1;
			S_D1:    begin s_code_lo <= spr_data; s_spra <= {sidx, 2'd2}; ss <= S_A2; end
			S_A2:    ss <= S_D2;
			S_D2:    begin s_attr <= spr_data;    s_spra <= {sidx, 2'd3}; ss <= S_A3; end
			S_A3:    ss <= S_D3;
			S_D3:    begin s_x <= spr_data;       ss <= S_BNK; end
			S_BNK:   begin
				// campionamento di cio' che dipende da flip_q: costante per
				// tutto lo sprite, cosi' flip_q non entra piu' nel percorso
				// degli indirizzi (vedi la nota sopra le wire cb0/cb1)
				sx_eff_r <= sx_eff;
				fx_r     <= fx;
				srow_r   <= srow;
				ss       <= S_BNK2;                // sprbank_addr gia' stabile
			end
			S_BNK2:  begin
				s_bank <= sprbank_data[3:0];
				if (on_line) begin s_pair <= 3'd0; ss <= S_FE; end
				else ss <= S_NXT;
			end
			S_FE:    ss <= S_FE2;
			S_FE2:   begin s_gfx <= sprrom_data; ss <= S_PX0; end
			S_PX0: begin
				if (pen0 != 4'hF && wx0 < 9'd256) begin
					if (wbuf) lb1[wx0[7:0]] <= {1'b1, scol, s_bank, pen0};
					else      lb0[wx0[7:0]] <= {1'b1, scol, s_bank, pen0};
				end
				ss <= S_PX1;
			end
			S_PX1: begin
				if (pen1 != 4'hF && wx1 < 9'd256) begin
					if (wbuf) lb1[wx1[7:0]] <= {1'b1, scol, s_bank, pen1};
					else      lb0[wx1[7:0]] <= {1'b1, scol, s_bank, pen1};
				end
				if (s_pair == 3'd7) ss <= S_NXT;
				else begin s_pair <= s_pair + 3'd1; ss <= S_FE; end
			end
			S_NXT: begin
				// finiti i 64: si resta fermi fino al prossimo inizio riga
				// 64 sprite su Galivan, 128 su Ninja Emaki: e' il numero di
				// entry da 4 byte che stanno nella spriteram del set.
				if (sidx == (nj_video ? 7'd127 : 7'd63)) ss <= S_NXT;
				else begin sidx <= sidx + 7'd1; s_spra <= {sidx + 7'd1, 2'd0}; ss <= S_A0; end
			end
			default: ss <= S_NXT;
			endcase
		end
	end
end

always @(posedge clk) lb_q <= wbuf ? lb0[lx[7:0]] : lb1[lx[7:0]];

wire       spr_valid = lb_q[12];
wire [3:0] spr_color = lb_q[11:8];
wire [3:0] spr_bank  = lb_q[7:4];
wire [3:0] spr_pen   = lb_q[3:0];

// -----------------------------------------------------------------
// UNICO blocco che scrive i due line buffer del background.
// Nessun azzeramento: il background e' opaco e le 17 colonne coprono tutta la
// riga, quindi ogni posizione 0..255 viene riscritta ogni riga.
// -----------------------------------------------------------------
always @(posedge clk) begin
	if (reset) begin
		gs <= G_IDLE; tile_req <= 1'b0; bg_c <= 5'd0; bg_b <= 3'd0;
	end else if (line_start) begin
		bg_c     <= 5'd0;
		bg_b     <= 3'd0;
		tile_req <= 1'b0;
		gs       <= G_LAT;
	end else begin
		case (gs)
		G_IDLE: ;                                        // riga finita: si aspetta
		// Scroll e riga di tile si latchano UN ciclo dopo line_start, quando vcnt
		// e' gia' avanzato: a quel punto ly e' la riga che si sta disegnando e
		// ly_next quella da preparare. Latchandoli SUL fronte si prenderebbe il
		// vcnt vecchio e il buffer conterrebbe la riga precedente.
		G_LAT: begin
			bg_sx <= scroll_x_q;
			bg_ty <= bgy_n[10:4];
			bg_ry <= bgy_n[3:0];
			gs    <= G_M0;
		end
		G_M0:  begin bgmap_a <= {1'b0, bg_mapix}; gs <= G_M0W; end
		G_M0W: gs <= G_M1;                               // attesa BRAM
		G_M1:  begin bg_code_lo <= bgmap_data; bgmap_a <= {1'b1, bg_mapix}; gs <= G_M1W; end
		G_M1W: gs <= G_AT;
		// l'attributo si latcha in uno stato SUO: bg_code lo usa (bit 8-9 del
		// codice) e in Verilog una non-blocking non e' visibile nello stesso ciclo.
		G_AT:  begin bg_attr <= bgmap_data; gs <= G_REQ; end
		// La richiesta parte solo a bus SDRAM libero. A inizio riga la macchina
		// riparte da zero e puo' aver lasciato una lettura in volo: senza questa
		// guardia il tile_ok di QUELLA arriverebbe qui e il primo byte della riga
		// sarebbe il byte del tile precedente.
		G_REQ: if (!tile_busy) begin
			// 10 bit di codice, 4 di riga, 3 di byte = 17 -> 128 byte per tile,
			// 8 per riga (gfx_16x16x4_packed_lsb)
			tile_addr <= {bg_code, bg_ry, bg_b};
			tile_req  <= 1'b1;
			gs        <= G_WT;
		end
		G_WT: if (tile_ok) begin
			tile_req <= 1'b0;
			bg_gfx   <= tile_data;
			gs       <= G_W0;
		end
		G_W0: begin
			if (bg_ok0) begin
				if (wbuf) bgb1[bg_pos0[7:0]] <= {bg_col_t, bg_pen0};
				else      bgb0[bg_pos0[7:0]] <= {bg_col_t, bg_pen0};
			end
			gs <= G_W1;
		end
		G_W1: begin
			if (bg_ok1) begin
				if (wbuf) bgb1[bg_pos1[7:0]] <= {bg_col_t, bg_pen1};
				else      bgb0[bg_pos1[7:0]] <= {bg_col_t, bg_pen1};
			end
			gs <= G_NX;
		end
		G_NX: begin
			if (bg_b == 3'd7) begin
				bg_b <= 3'd0;
				if (bg_c == 5'd16) gs <= G_IDLE;         // 17 colonne fatte
				else begin bg_c <= bg_c + 5'd1; gs <= G_M0; end
			end else begin
				bg_b <= bg_b + 3'd1;
				gs   <= G_REQ;                            // stesso tile, byte dopo
			end
		end
		default: gs <= G_IDLE;
		endcase
	end
end

// il bg_code va tenuto fermo mentre si leggono gli 8 byte: bgmap_a non cambia
// piu' dopo G_M1, quindi bg_code_lo/bg_attr restano validi fino al tile dopo.
always @(posedge clk) bgb_q <= wbuf ? bgb0[lx[7:0]] : bgb1[lx[7:0]];

wire [3:0] bg_color = bgb_q[7:4];
wire [3:0] bg_pen   = bgb_q[3:0];

// =====================================================================
// Colore
// =====================================================================
// Il TESTO e' l'unico layer in cui le due schede NON usano la stessa formula.
//
//   Galivan     galivan_state::palette()  — "characters use colors 0-0x3f"
//               ctabentry = (i & 0x0f) | ((i >> ((i & 8) ? 2 : 0)) & 0x30)
//               cioe' i due bit di banco cambiano posto a seconda del pen
//
//   Ninja Emaki ninjemak_state::palette() — "characters use colors 0-0x7f"
//               set_pen_indirect(i, i): indice DIRETTO, color*16 + pen,
//               con color a 3 bit (otto banchi) invece di quattro
//
// Sfondo e sprite invece hanno formule identiche fra i due set, verificate
// termine per termine: li' non serve distinguere.
wire [7:0] tx_idx = nj_video
                  ? {1'b0, tx_color[2:0], tx_pen}
                  : ({4'd0, tx_pen} |
                     (tx_pen[3] ? {2'd0, tx_color[3:2], 4'd0} : {2'd0, tx_color[1:0], 4'd0}));
wire [7:0] bg_idx = 8'hC0 | ({4'd0, bg_pen} |
                    (bg_pen[3] ? {2'd0, bg_color[3:2], 4'd0} : {2'd0, bg_color[1:0], 4'd0}));

reg  [3:0] spr_lk;
wire [7:0] spr_idx = 8'h80 |
                     (spr_pen[3] ? {2'd0, spr_bank[3:2], 4'd0} : {2'd0, spr_bank[1:0], 4'd0}) |
                     {4'd0, spr_lk};

wire bg_off    = layers_q[1];
wire txt_off   = layers_q[2];
wire spr_first = layers_q[0];      // bit5=1: testo disegnato prima, sprite sopra

wire tx_op = en_txt & ~txt_off  & (tx_pen  != 4'hF);
wire sp_op = en_spr & spr_valid & (spr_pen != 4'hF);
wire bg_op = en_bg  & ~bg_off;

wire [7:0] pal_idx = spr_first ? (sp_op ? spr_idx : tx_op ? tx_idx  : bg_op ? bg_idx : 8'd0)
                               : (tx_op ? tx_idx  : sp_op ? spr_idx : bg_op ? bg_idx : 8'd0);

reg [9:0] prom_a;
reg [3:0] c_r, c_g, c_b;
assign prom_addr = prom_a;

// La PROM e' una sola porta: quattro letture in serie dentro il pixel.
// ph5 indirizzo lookup -> ph7 lookup -> ph8 R -> ph10 R e G -> ph12 G e B -> ph14 B.
// L'ultima cade a ph14 apposta: a ph15 c'e' il ce_pix che campiona rgb, e un
// valore scritto SU quel fronte arriverebbe un pixel dopo (blu in ritardo).
always @(posedge clk) begin
	case (ph)
	4'd5:  prom_a <= {2'b11, spr_color, spr_pen};   // 0x300 + color*16 + pen
	4'd7:  spr_lk <= prom_data[3:0];
	4'd8:  prom_a <= {2'b00, pal_idx};
	4'd10: begin c_r <= prom_data[3:0]; prom_a <= {2'b01, pal_idx}; end
	4'd12: begin c_g <= prom_data[3:0]; prom_a <= {2'b10, pal_idx}; end
	4'd14: c_b <= prom_data[3:0];
	default: ;
	endcase
end

// pal4bit: nibble replicato sugli 8 bit
assign rgb = {c_r, c_r, c_g, c_g, c_b, c_b};

endmodule
