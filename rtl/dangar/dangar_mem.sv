// SPDX-License-Identifier: GPL-3.0-or-later
/*  This file is part of rmGalivan_MiSTer.
    Author: Umberto Parisi (rmonic79)

    dangar_mem.sv — memoria delle ROM di Ufo Robo Dangar (hardware Galivan).

    Ripartizione (M10K contati sui BLOCCHI, non sui bit):

      BRAM   178 M10K   main 64 (48 fissa + 2 banchi da 8) + char 16 + mappe bg 32
                        + sprite 64 + PROM 1 + banco palette sprite 1
                        Sono i clienti a latenza fissa: la CPU principale e tutto
                        cio' che si legge dentro il pixel o dentro un FSM a passo
                        fisso. Contratto: indirizzo al ciclo T, dato al ciclo T+1.

      SDRAM  128 KB     grafica dei tile 16x16, banco 0. E' l'unica regione grande
                        che sta fuori: il background la legge una RIGA DI TILE alla
                        volta (8 byte ogni 16 pixel = 256 cicli di margine), quindi
                        la latenza variabile della SDRAM non tocca il percorso pixel.

      DDR3    48 KB     ROM del Z80 audio, via ddram_4port. Il sound gira a 4 MHz
                        (24 cicli di clk per ciclo macchina) e ddram_4port serve
                        linee da 8 byte con cache per porta: il fetch sequenziale
                        del codice costa una lettura DDR ogni 8 byte.

    ---------------------------------------------------------------------------
    PERCHE' LE BRAM SONO A 16 BIT E NON A BYTE
    ---------------------------------------------------------------------------
    ioctl gira con WIDE=1: ioctl_dout e' una parola da 16 bit = 2 byte e ioctl_addr
    avanza di 2. Scrivere i due byte in un array a byte (rom[off] e rom[off+1])
    significa DUE porte di scrittura; con la porta di lettura fanno TRE accessi
    sullo stesso array. Un M10K ne ha DUE: Quartus rinuncia a inferire la RAM e
    costruisce banchi di registri — 176 KB di ROM = oltre un milione di flip-flop,
    cioe' un fit impossibile su 5CSEBA6.
    Quindi le ROM sono memorizzate a PAROLA (una scrittura, una lettura) e il byte
    lo sceglie il bit 0 dell'indirizzo, registrato insieme al dato. La latenza vista
    dal cliente resta identica: indirizzo al ciclo T, byte valido al ciclo T+1.
    Il costo in M10K e' lo stesso (x16 usa 512 parole per blocco, x8 ne usa 1024).
    Tutte le basi di regione sono pari, quindi off[0] e' sempre 0 e l'indice di
    parola e' off[N:1] senza disallineamenti.
*/

`timescale 1ns / 1ps

module dangar_mem
(
	input               clk,
	input               reset,

	// ---- download ----
	input               ioctl_download,
	input               ioctl_wr,
	input        [26:0] ioctl_addr,
	input        [15:0] ioctl_dout,
	input        [15:0] ioctl_index,
	input               board_ninjemak,  // 0 = Galivan/Dangar/dangarj, 1 = Ninja Emaki
	input               board_youmab,    // bootleg Game Electronics: IMPLICA board_ninjemak
	input               board_ninjemat,  // licenza Tecfri: NON implica board_ninjemak
	input               sdram_ready,     // alto quando jtframe_sdram64 ha finito l'init
	output              rom_loaded,
	output              ioctl_wait,

	// ---- clienti in BRAM: indirizzo al ciclo T, dato al ciclo T+1 ----
	input        [16:0] main_addr,
	output        [7:0] main_data,
	input        [14:0] char_addr,
	output        [7:0] char_data,
	input        [14:0] bgmap_addr,
	output        [7:0] bgmap_data,
	input        [16:0] sprrom_addr,
	output        [7:0] sprrom_data,
	input         [9:0] prom_addr,
	output        [7:0] prom_data,
	input         [7:0] sprbank_addr,
	output        [7:0] sprbank_data,
	// ROM da 8 KB della scheda figlia DG-3 (chip NB1412M2, solo set `dangarj`).
	// Sugli altri set la MRA non emette la regione: resta a zero e nessuno la legge.
	input        [12:0] prot_addr,
	output        [7:0] prot_data,
	// ROM dati da 16 KB del blitter NB1414M4 (solo Ninja Emaki).
	input        [13:0] blit_addr,
	output        [7:0] blit_data,

	// ---- cliente in SDRAM: tile, con handshake ----
	input        [16:0] tile_addr,
	input               tile_req,
	output reg    [7:0] tile_data,
	output reg          tile_ok,
	output              tile_busy,      // transazione SDRAM ancora in volo

	// ---- cliente in DDR3: ROM audio, con handshake ----
	input        [15:0] snd_addr,
	input               snd_req,
	output        [7:0] snd_data,
	output              snd_ok,

	// ---- verso jtframe_sdram64 (solo banco 0) ----
	output       [21:0] ba0_addr,
	output        [3:0] ba_rd,
	input         [3:0] ba_rdy,
	input         [3:0] ba_ack,
	input        [15:0] sdram_dout,
	output              prog_en,
	output       [21:0] prog_addr,
	output        [1:0] prog_ba,
	output              prog_rd,
	output              prog_wr,
	output       [15:0] prog_din,
	output        [1:0] prog_dsn,
	input               prog_ack,
	input               prog_rdy,

	// ---- verso ddram_4port (ROM audio) ----
	output       [27:0] ddr_rdaddr,
	input         [7:0] ddr_dout,
	output              ddr_rd_req,
	input               ddr_rd_ack,
	output       [27:0] ddr_wraddr,
	output       [15:0] ddr_din,
	output              ddr_we_req,
	input               ddr_we_ack
);

`include "dangar_rom_regions.vh"
`include "ninjemak_rom_regions.vh"
`include "youmab_rom_regions.vh"
`include "ninjemat_rom_regions.vh"

// =====================================================================
// Decodifica della regione durante il download.
// MAIN_BASE e' 0: per la prima regione basta il limite alto. MAIN e MAINBNK sono
// contigue (0x00000-0x0FFFF) e stanno nella stessa BRAM: ROM fissa a 0x0000-0xBFFF,
// i due banchi da 8 KB a 0xC000 e 0xE000.
// =====================================================================
wire load = ioctl_download & ioctl_wr & (ioctl_index == 16'd0);

// Due tabelle, scelte dal byte di variante. Il byte arriva con ioctl_index=1,
// PRIMA delle ROM, quindi qui e' gia' valido per tutto il download.
// I limiti si scelgono una volta sola in questi wire: nel resto del modulo non
// c'e' nessun altro confronto sulla variante.
// Sul bootleg il blocco contiguo che finisce in rom_main e' piu' lungo: alla
// ROM fissa e ai banchi si aggiunge XBANK, la ROM extra da 32 KB che il codice
// dei bootlegger banca a 0x8000-0xBFFF. Essendo contigua a MAINBNK e con
// off_main = ioctl_addr, sta semplicemente in coda allo stesso array: nessuna
// BRAM nuova, nessun wire di regione in piu' — basta spostare il limite.
wire [26:0] b_mainbnk_end = board_youmab   ? YB_XBANK_END
                          : board_ninjemak ? NJ_MAINBNK_END
                          : board_ninjemat ? NT_MAINBNK_END : MAINBNK_END;
wire [26:0] b_audio_base  = board_youmab ? YB_AUDIO_BASE  : board_ninjemak ? NJ_AUDIO_BASE  : board_ninjemat ? NT_AUDIO_BASE  : AUDIO_BASE;
wire [26:0] b_audio_end   = board_youmab ? YB_AUDIO_END   : board_ninjemak ? NJ_AUDIO_END   : board_ninjemat ? NT_AUDIO_END   : AUDIO_END;
wire [26:0] b_chars_base  = board_youmab ? YB_CHARS_BASE  : board_ninjemak ? NJ_CHARS_BASE  : board_ninjemat ? NT_CHARS_BASE  : CHARS_BASE;
wire [26:0] b_chars_end   = board_youmab ? YB_CHARS_END   : board_ninjemak ? NJ_CHARS_END   : board_ninjemat ? NT_CHARS_END   : CHARS_END;
wire [26:0] b_bgmap_base  = board_youmab ? YB_BGMAP_BASE  : board_ninjemak ? NJ_BGMAP_BASE  : board_ninjemat ? NT_BGMAP_BASE  : BGMAP_BASE;
wire [26:0] b_bgmap_end   = board_youmab ? YB_BGMAP_END   : board_ninjemak ? NJ_BGMAP_END   : board_ninjemat ? NT_BGMAP_END   : BGMAP_END;
wire [26:0] b_tiles_base  = board_youmab ? YB_TILES_BASE  : board_ninjemak ? NJ_TILES_BASE  : board_ninjemat ? NT_TILES_BASE  : TILES_BASE;
wire [26:0] b_tiles_end   = board_youmab ? YB_TILES_END   : board_ninjemak ? NJ_TILES_END   : board_ninjemat ? NT_TILES_END   : TILES_END;
wire [26:0] b_spr_base    = board_youmab ? YB_SPRITES_BASE: board_ninjemak ? NJ_SPRITES_BASE: board_ninjemat ? NT_SPRITES_BASE: SPRITES_BASE;
wire [26:0] b_spr_end     = board_youmab ? YB_SPRITES_END : board_ninjemak ? NJ_SPRITES_END : board_ninjemat ? NT_SPRITES_END : SPRITES_END;
wire [26:0] b_proms_base  = board_youmab ? YB_PROMS_BASE  : board_ninjemak ? NJ_PROMS_BASE  : board_ninjemat ? NT_PROMS_BASE  : PROMS_BASE;
wire [26:0] b_proms_end   = board_youmab ? YB_PROMS_END   : board_ninjemak ? NJ_PROMS_END   : board_ninjemat ? NT_PROMS_END   : PROMS_END;
wire [26:0] b_sprb_base   = board_youmab ? YB_SPRBANK_BASE: board_ninjemak ? NJ_SPRBANK_BASE: board_ninjemat ? NT_SPRBANK_BASE: SPRBANK_BASE;
wire [26:0] b_sprb_end    = board_youmab ? YB_SPRBANK_END : board_ninjemak ? NJ_SPRBANK_END : board_ninjemat ? NT_SPRBANK_END : SPRBANK_END;

wire in_main    = (ioctl_addr < b_mainbnk_end);
wire in_audio   = (ioctl_addr >= b_audio_base) && (ioctl_addr < b_audio_end);
wire in_chars   = (ioctl_addr >= b_chars_base) && (ioctl_addr < b_chars_end);
wire in_bgmap   = (ioctl_addr >= b_bgmap_base) && (ioctl_addr < b_bgmap_end);
wire in_tiles   = (ioctl_addr >= b_tiles_base) && (ioctl_addr < b_tiles_end);
wire in_sprites = (ioctl_addr >= b_spr_base)   && (ioctl_addr < b_spr_end);
wire in_proms   = (ioctl_addr >= b_proms_base) && (ioctl_addr < b_proms_end);
wire in_sprbank = (ioctl_addr >= b_sprb_base)  && (ioctl_addr < b_sprb_end);
// PROT esiste solo su dangarj, BLIT solo su Ninja Emaki: mai attivi insieme.
// La Tecfri va esclusa da PROT esplicitamente: non e' una Ninja Emaki, quindi
// il solo ~board_ninjemak non la filtra, e la finestra PROT (0x058500-0x05A500)
// cade DENTRO la sua regione sprite (0x04C000-0x06C000). Senza questo gate
// otto kilobyte di sprite finirebbero nella BRAM sbagliata.
wire in_prot    = ~board_ninjemak & ~board_ninjemat
                                  & (ioctl_addr >= PROT_BASE)    && (ioctl_addr < PROT_END);
wire in_blit    =  board_ninjemak & ~board_youmab
                                  & (ioctl_addr >= NJ_BLIT_BASE) && (ioctl_addr < NJ_BLIT_END);

wire [26:0] off_main    = ioctl_addr;
wire [26:0] off_audio   = ioctl_addr - b_audio_base;
wire [26:0] off_chars   = ioctl_addr - b_chars_base;
wire [26:0] off_bgmap   = ioctl_addr - b_bgmap_base;
wire [26:0] off_tiles   = ioctl_addr - b_tiles_base;
wire [26:0] off_sprites = ioctl_addr - b_spr_base;
wire [26:0] off_proms   = ioctl_addr - b_proms_base;
wire [26:0] off_sprbank = ioctl_addr - b_sprb_base;
wire [26:0] off_prot    = ioctl_addr - PROT_BASE;
wire [26:0] off_blit    = ioctl_addr - NJ_BLIT_BASE;

// =====================================================================
// BRAM a parola: UNA porta di scrittura + UNA di lettura per ogni array.
// Indirizzo di lettura registrato puro: mai un mux combinatorio nell'indice,
// o Quartus fa decadere la RAM a registri+mux (doc 04 MiSTer_Discovery_Docs).
// =====================================================================
reg [15:0] rom_main [0:49151];   // 96 KB. Ninja Emaki: 48 fissa + 4 banchi da 8 = 80.
                                 // youmab: 32 fissa + 4 banchi da 8 + 32 di banco extra = 96.
reg [15:0] rom_char [0:16383];   // 32 KB (Ninja Emaki)
reg [15:0] rom_bgm  [0:16383];   // 32 KB
reg [15:0] rom_spr  [0:65535];   // 128 KB (Ninja Emaki)
reg [15:0] rom_prom [0:511];     //  1 KB
reg [15:0] rom_sprb [0:127];     // 256 B
reg [15:0] rom_prot [0:4095];    //  8 KB (DG-3, NB1412M2)
reg [15:0] rom_blit [0:8191];    // 16 KB (dati del blitter NB1414M4)

reg [15:0] q_main, q_char, q_bgm, q_spr, q_prom, q_sprb, q_prot, q_blit;
reg        s_main, s_char, s_bgm, s_spr, s_prom, s_sprb, s_prot, s_blit;

always @(posedge clk) begin
	if (load & in_main)    rom_main[off_main   [16:1]] <= ioctl_dout;
	q_main <= rom_main[main_addr[16:1]];
	s_main <= main_addr[0];
end

always @(posedge clk) begin
	if (load & in_chars)   rom_char[off_chars  [14:1]] <= ioctl_dout;
	q_char <= rom_char[char_addr[14:1]];
	s_char <= char_addr[0];
end

always @(posedge clk) begin
	if (load & in_bgmap)   rom_bgm [off_bgmap  [14:1]] <= ioctl_dout;
	q_bgm <= rom_bgm[bgmap_addr[14:1]];
	s_bgm <= bgmap_addr[0];
end

always @(posedge clk) begin
	if (load & in_sprites) rom_spr [off_sprites[16:1]] <= ioctl_dout;
	q_spr <= rom_spr[sprrom_addr[16:1]];
	s_spr <= sprrom_addr[0];
end

always @(posedge clk) begin
	if (load & in_proms)   rom_prom[off_proms  [9:1]]  <= ioctl_dout;
	q_prom <= rom_prom[prom_addr[9:1]];
	s_prom <= prom_addr[0];
end

always @(posedge clk) begin
	if (load & in_sprbank) rom_sprb[off_sprbank[7:1]]  <= ioctl_dout;
	q_sprb <= rom_sprb[sprbank_addr[7:1]];
	s_sprb <= sprbank_addr[0];
end

always @(posedge clk) begin
	if (load & in_prot)    rom_prot[off_prot   [12:1]] <= ioctl_dout;
	q_prot <= rom_prot[prot_addr[12:1]];
	s_prot <= prot_addr[0];
end

always @(posedge clk) begin
	if (load & in_blit)    rom_blit[off_blit   [13:1]] <= ioctl_dout;
	q_blit <= rom_blit[blit_addr[13:1]];
	s_blit <= blit_addr[0];
end

assign main_data    = s_main ? q_main[15:8] : q_main[7:0];
assign char_data    = s_char ? q_char[15:8] : q_char[7:0];
assign bgmap_data   = s_bgm  ? q_bgm [15:8] : q_bgm [7:0];
assign sprrom_data  = s_spr  ? q_spr [15:8] : q_spr [7:0];
assign prom_data    = s_prom ? q_prom[15:8] : q_prom[7:0];
assign sprbank_data = s_sprb ? q_sprb[15:8] : q_sprb[7:0];
assign prot_data    = s_prot ? q_prot[15:8] : q_prot[7:0];
assign blit_data    = s_blit ? q_blit[15:8] : q_blit[7:0];

// =====================================================================
// DOWNLOAD verso SDRAM (tile -> banco 0) e verso DDR3 (ROM audio).
// prog_addr della SDRAM e' un indirizzo di PAROLA: offset/2 dentro il banco.
// La DDR3 la si scrive con la porta di write di ddram_4port, a parole da 16 bit.
//
// jtframe_sdram64 tiene il canale prog in reset per tutta l'inizializzazione
// (jtframe_sdram64.v:194  prog_rst <= ~prog_en | init | rst): finche' init e'
// alto una scrittura non riceve mai prog_ack/prog_rdy. Percio' ioctl_wait resta
// alto per tutto il download finche' sdram_ready non sale — e' esattamente cio'
// che fa il bridge di Raiden (sdram_bridge.sv:245).
// =====================================================================
reg        sd_we   = 1'b0;
reg [21:0] sd_a    = 22'd0;
reg [15:0] sd_d    = 16'd0;
reg        sd_pend = 1'b0;

reg        dr_we   = 1'b0;
reg [27:0] dr_a    = 28'd0;
reg [15:0] dr_d    = 16'd0;

// ATTENZIONE: il reset del gioco (Template.sv:371) contiene ioctl_download, cioe'
// e' ALTO per tutto il caricamento. Se questa macchina lo usasse come reset non
// emetterebbe MAI una scrittura: i tile non arriverebbero in SDRAM e la ROM del
// Z80 audio non arriverebbe in DDR3 — schermo nero e sound muto, con le sole BRAM
// caricate (quelle si scrivono in blocchi senza reset). Percio' qui il reset vale
// solo FUORI dal download; i registri partono a zero dalla dichiarazione.
wire dl_rst = reset & ~ioctl_download;

always @(posedge clk) begin
	if (dl_rst) begin
		sd_we <= 1'b0; sd_pend <= 1'b0; dr_we <= 1'b0;
	end else begin
		// --- SDRAM: solo i tile ---
		if (load && in_tiles) begin
			sd_a    <= off_tiles[22:1];
			sd_d    <= ioctl_dout;
			sd_we   <= 1'b1;
			sd_pend <= 1'b1;
		end else if (prog_ack) begin
			sd_we <= 1'b0;
		end
		if (prog_rdy) sd_pend <= 1'b0;

		// --- DDR3: la ROM audio. we_req/we_ack sono a livello alternato:
		//     si inverte we_req e si aspetta che we_ack lo raggiunga. ---
		if (load && in_audio) begin
			dr_a  <= {12'd0, off_audio[15:0]};
			dr_d  <= ioctl_dout;
			dr_we <= ~dr_we;
		end
	end
end

assign prog_en   = ioctl_download;
assign prog_addr = sd_a;
assign prog_ba   = 2'd0;              // un solo banco in uso: il 0
assign prog_rd   = 1'b0;
assign prog_wr   = sd_we;
assign prog_din  = sd_d;
assign prog_dsn  = 2'b00;

assign ddr_wraddr = dr_a;
assign ddr_din    = dr_d;
assign ddr_we_req = dr_we;

// Coda di ioctl_wait: dopo che l'ultima scrittura e' passata si tiene comunque
// fermo l'HPS per qualche decina di cicli. ioctl_wait viaggia sul bus HPS
// (hps_io.sv:191 HPS_BUS[37]), quindi non e' una contropressione al ciclo:
// lo stiramento e' la stessa precauzione del bridge di Raiden.
reg [7:0] wait_stretch;
reg       busy_d;
wire      busy = sd_pend | (dr_we != ddr_we_ack);
always @(posedge clk) begin
	busy_d <= busy;
	if (dl_rst) wait_stretch <= 8'd0;
	else if (busy_d & ~busy) wait_stretch <= 8'd64;
	else if (wait_stretch != 8'd0) wait_stretch <= wait_stretch - 8'd1;
end

assign ioctl_wait = busy | (wait_stretch != 8'd0) | (ioctl_download & ~sdram_ready);

// =====================================================================
// LETTURA SDRAM (tile). Un solo cliente sul banco 0: nessun arbitraggio.
// Indirizzo di parola, il byte lo sceglie il bit 0.
// L'indirizzo va LATCHATO alla richiesta: tile_addr appartiene alla FSM del
// background, che lo cambia appena la richiesta e' partita; lasciarlo passare
// in combinatoria significherebbe cambiare riga/colonna a transazione aperta.
// =====================================================================
reg tl_rd = 1'b0, tl_busy = 1'b0, tl_lsb = 1'b0;
reg [21:0] tl_a = 22'd0;

assign ba0_addr  = tl_a;
assign ba_rd     = {3'b000, tl_rd};
// Il cliente deve poter sapere se una lettura e' ancora aperta: se ne apre una
// nuova mentre la vecchia e' in volo, il tile_ok della VECCHIA gli arriva come
// se fosse la risposta alla nuova e si prende il byte sbagliato. Succede a ogni
// inizio riga, quando il renderer riparte da capo lasciando una lettura appesa.
assign tile_busy = tl_busy;

always @(posedge clk) begin
	if (reset) begin
		tl_rd <= 1'b0; tl_busy <= 1'b0; tile_ok <= 1'b0;
	end else begin
		tile_ok <= 1'b0;
		if (!tl_busy) begin
			// niente richieste mentre il canale prog ha il controllo della SDRAM
			if (tile_req & ~ioctl_download & sdram_ready) begin
				tl_a    <= {6'd0, tile_addr[16:1]};
				tl_lsb  <= tile_addr[0];
				tl_rd   <= 1'b1;
				tl_busy <= 1'b1;
			end
		end else begin
			if (ba_ack[0]) tl_rd <= 1'b0;
			if (ba_rdy[0]) begin
				tile_data <= tl_lsb ? sdram_dout[15:8] : sdram_dout[7:0];
				tile_ok   <= 1'b1;
				tl_busy   <= 1'b0;
			end
		end
	end
end

// =====================================================================
// LETTURA DDR3 (ROM audio) tramite ddram_4port, che ha gia' la cache a linea
// da 8 byte per porta: il fetch sequenziale del codice costa una lettura ogni
// 8 byte. Protocollo del 4port: rd_req a livello alternato, rd_ack lo insegue,
// dout resta valido fino alla richiesta successiva (ddram_4port.sv:223-229).
//
// snd_ok e' un LIVELLO, non un impulso: dangar_sound campiona solo quando il suo
// ce_snd (4 MHz = un colpo ogni 24 clk) coincide con rom_ok, e un impulso di un
// solo clk non lo incrocerebbe quasi mai — la CPU sound resterebbe appesa per
// sempre. Il livello vale finche' l'indirizzo richiesto e' quello servito.
// Anche ddr_rdaddr va registrato: snd_addr e' il bus della CPU e cambia.
// =====================================================================
reg        dr_rd   = 1'b0;
reg        dr_busy = 1'b0;
reg        snd_val = 1'b0;
reg [15:0] snd_a   = 16'd0;
reg  [7:0] snd_d   = 8'd0;
reg [27:0] dr_ra   = 28'd0;

assign ddr_rdaddr = dr_ra;
assign ddr_rd_req = dr_rd;
assign snd_data   = snd_d;
assign snd_ok     = snd_val & (snd_a == snd_addr);

always @(posedge clk) begin
	if (reset) begin
		dr_rd <= 1'b0; dr_busy <= 1'b0; snd_val <= 1'b0;
	end else if (dr_rd == ddr_rd_ack) begin
		if (dr_busy) begin
			// la richiesta in volo e' stata servita
			snd_d   <= ddr_dout;
			snd_val <= 1'b1;
			dr_busy <= 1'b0;
		end
		else if (snd_req & ~snd_ok & ~ioctl_download) begin
			snd_a   <= snd_addr;
			dr_ra   <= {12'd0, snd_addr};
			snd_val <= 1'b0;
			dr_rd   <= ~dr_rd;
			dr_busy <= 1'b1;
		end
	end
end

// =====================================================================
reg loaded = 1'b0;
reg dl_d   = 1'b0;
always @(posedge clk) begin
	dl_d <= ioctl_download;
	if (dl_d && !ioctl_download) loaded <= 1'b1;
end
assign rom_loaded = loaded;

endmodule
