// SPDX-License-Identifier: GPL-3.0-or-later
/*  This file is part of rmGalivan_MiSTer.
    Author: Umberto Parisi (rmonic79)

    dangar_top.sv — livello di gioco di Ufo Robo Dangar (hardware Galivan GV-1412).

    Mette insieme CPU principale, audio, renderer e memoria, genera i clock enable
    dal clock unico a 96 MHz e porta fuori video, audio e i chunk savestate.

    Clock enable (dalle XTAL della PCB, galivan.cpp:1169 e :1172):
      ce_main  96/16 = 6.000 MHz   Z80B main   (XTAL 12 MHz / 2)
      ce_snd   96/24 = 4.000 MHz   Z80A sound  (XTAL  8 MHz / 2)
      ce_ym    96/24 = 4.000 MHz   YM3526      (XTAL  8 MHz / 2)
    Divisori interi: nessun frac_cen, nessun clock derivato, un solo clock nel core.

    Memoria (ripartizione decisa a budget M10K, vedi dangar_mem.sv):
      BRAM  main, char, mappe bg, sprite, PROM      178 M10K
      SDRAM tile 16x16, banco 0                     128 KB
      DDR3  ROM del Z80 audio, via ddram_4port       48 KB

    Buffering sprite: la spriteram e' bufferizzata e la copia avviene sul FRONTE DI
    SALITA del VBlank (galivan.cpp:1178 vblank_copy_rising, :1182). L'impulso si
    genera qui e va alla CPU, che possiede la RAM.
*/

`timescale 1ns / 1ps

module dangar_top #(
	// [SS-HOOK] indici ssbus dei chunk posseduti dal gioco
	parameter SS_IDX_WRAM = -1,
	parameter SS_IDX_CRAM = -1,
	parameter SS_IDX_SPRB = -1,
	parameter SS_IDX_REGS = -1,
	parameter SS_IDX_SRAM  = -1,
	parameter SS_IDX_YMSH  = -1,
	parameter SS_IDX_SGLUE = -1,
	parameter SS_IDX_SPRL  = -1
)
(
	input             clk,            // 96 MHz
	input             reset,
	input             pause,
	input             ss_cpu_reload,   // [SS-HOOK] riposo delle FSM dopo un load

	// Variante di scheda, dalla regione MRA index=1 (vedi Template.sv).
	// 0 = Galivan / Dangar / dangarj      1 = Ninja Emaki
	// Latchata PRIMA del download delle ROM, quindi e' valida anche durante.
	input             board_ninjemak,
	input             board_youmab,
	input             board_ninjemat,

	// ---- input di gioco, attivi bassi come la PCB ----
	input      [7:0]  p1,
	input      [7:0]  p2,
	input      [7:0]  sys,
	input      [7:0]  service,      // solo Ninja Emaki: porta 0x83
	input      [7:0]  dsw1,
	input      [7:0]  dsw2,

	// ---- raster dal top MiSTer ----
	input      [9:0]  hcnt,
	input      [9:0]  vcnt,
	input             hblank,
	input             vblank,
	input             ce_pix,

	// ---- enable di debug dall'OSD ----
	input             en_bg,
	input             en_txt,
	input             en_spr,

	// ---- download ----
	input             ioctl_download,
	input             ioctl_wr,
	input      [26:0] ioctl_addr,
	input      [15:0] ioctl_dout,
	input      [15:0] ioctl_index,
	input             sdram_ready,    // init di jtframe_sdram64 finito
	output            ioctl_wait,

	// ---- SDRAM (jtframe_sdram64 nel top): solo banco 0, i tile ----
	output     [21:0] ba0_addr,
	output      [3:0] ba_rd,
	input       [3:0] ba_rdy,
	input       [3:0] ba_ack,
	input      [15:0] sdram_dout,
	output            prog_en,
	output     [21:0] prog_addr,
	output      [1:0] prog_ba,
	output            prog_rd,
	output            prog_wr,
	output     [15:0] prog_din,
	output      [1:0] prog_dsn,
	input             prog_ack,
	input             prog_rdy,

	// ---- DDR3: ROM audio. I pin li pilota il ddr_mux nel top MiSTer ----
	input             DDRAM_CLK,
	input             DDRAM_BUSY,
	output      [7:0] DDRAM_BURSTCNT,
	output     [28:0] DDRAM_ADDR,
	input      [63:0] DDRAM_DOUT,
	input             DDRAM_DOUT_READY,
	output            DDRAM_RD,
	output     [63:0] DDRAM_DIN,
	output      [7:0] DDRAM_BE,
	output            DDRAM_WE,
	output            ss_idle,
	output            ss_want,
	input             ss_hold,

	// ---- uscite ----
	output     [23:0] rgb,
	output signed [15:0] audio_l,
	output signed [15:0] audio_r,

	// ---- savestate ----
	// registri delle due CPU (tv80s auto_ss, blocco da 358 bit)
	input      [357:0] ss_main_in,
	input              ss_main_wr,
	output     [357:0] ss_main_out,
	input      [357:0] ss_snd_in,
	input              ss_snd_wr,
	output     [357:0] ss_snd_out,
	// chunk di memoria e registri, passati direttamente ai moduli che li possiedono
	ssbus_if.slave     ss_wram,
	ssbus_if.slave     ss_cram,
	ssbus_if.slave     ss_sprb,
	ssbus_if.slave     ss_regs,
	// chunk del sotto-sistema audio (ss_sglue per ULTIMO: il suo commit fa
	// partire il replay dei registri del YM3526)
	ssbus_if.slave     ss_sram,
	ssbus_if.slave     ss_ymsh,
	ssbus_if.slave     ss_sglue,
	ssbus_if.slave     ss_sprl
);

// =====================================================================
// Clock enable
// =====================================================================
reg [3:0] div16;
reg [4:0] div24;
always @(posedge clk) begin
	if (reset) begin div16 <= 4'd0; div24 <= 5'd0; end
	else begin
		div16 <= (div16 == 4'd15) ? 4'd0 : div16 + 4'd1;
		div24 <= (div24 == 5'd23) ? 5'd0 : div24 + 5'd1;
	end
end
wire ce_main = (div16 == 4'd0);
wire ce_snd  = (div24 == 5'd0);
wire ce_ym   = (div24 == 5'd12);      // sfasato rispetto al Z80 sound

// Il blitter NB1414M4 condivide la porta A della char RAM con la CPU: mentre
// copia, la CPU deve stare ferma. E' anche cio' che fa la scheda vera — il
// gioco scrive la porta 0x86 e aspetta che il chip abbia finito.
wire blit_busy;
wire ce_main_g = ce_main & ~pause & ~blit_busy;
wire ce_snd_g  = ce_snd  & ~pause;
wire ce_ym_g   = ce_ym   & ~pause;

// =====================================================================
// Copia della spriteram: fronte di salita del VBlank
// =====================================================================
reg vblank_d;
always @(posedge clk) vblank_d <= vblank;
wire spr_buffer_copy = vblank & ~vblank_d;

// =====================================================================
// Interconnessioni
// =====================================================================
wire [16:0] main_rom_a;  wire [7:0] main_rom_d;  wire main_rom_req;
wire [15:0] snd_rom_a;   wire [7:0] snd_rom_d;   wire snd_rom_req, snd_rom_ok;

wire [7:0]  snd_latch;   wire snd_latch_wr;
wire [12:0] scroll_x, scroll_y;   // 13 bit: 512 tile su Ninja Emaki
wire [2:0]  layers;
wire        flip_screen;

wire [10:0] cram_a;  wire [7:0] cram_d;
wire [8:0]  spr_a;   wire [7:0] spr_d;   // 9 bit: 512 byte di spriteram

wire [14:0] bgmap_a; wire [7:0] bgmap_d;
wire [16:0] tile_a;  wire [7:0] tile_d;  wire tile_req, tile_ok, tile_busy;
wire [14:0] char_a;  wire [7:0] char_d;   // 15 bit: 32 KB su Ninja Emaki
wire [16:0] sprr_a;  wire [7:0] sprr_d;   // 17 bit: 128 KB su Ninja Emaki
wire [9:0]  prom_a;  wire [7:0] prom_d;
wire [7:0]  sprb_a;  wire [7:0] sprb_d;
wire [12:0] prot_a;  wire [7:0] prot_d;   // ROM DG-3 del chip NB1412M2 (set `dangarj`)
wire [13:0] blit_a;  wire [7:0] blit_d;   // ROM dati del blitter NB1414M4 (Ninja Emaki)

wire [27:0] ddr_rdaddr, ddr_wraddr;
wire [7:0]  ddr_dout;
wire        ddr_rd_req, ddr_rd_ack;
wire [15:0] ddr_din;
wire        ddr_we_req, ddr_we_ack;

// =====================================================================
// Memoria
// =====================================================================
dangar_mem u_mem (
	.clk            (clk),
	.reset          (reset),
	.ioctl_download (ioctl_download),
	.ioctl_wr       (ioctl_wr),
	.ioctl_addr     (ioctl_addr),
	.ioctl_dout     (ioctl_dout),
	.ioctl_index    (ioctl_index),
	.sdram_ready    (sdram_ready),
	.rom_loaded     (),
	.ioctl_wait     (ioctl_wait),

	.board_ninjemak (board_ninjemak),
	.board_youmab   (board_youmab),
	.board_ninjemat (board_ninjemat),
	.main_addr      (main_rom_a),
	.main_data      (main_rom_d),
	.char_addr      (char_a),
	.char_data      (char_d),
	.bgmap_addr     (bgmap_a),
	.bgmap_data     (bgmap_d),
	.sprrom_addr    (sprr_a),
	.sprrom_data    (sprr_d),
	.prom_addr      (prom_a),
	.prom_data      (prom_d),
	.sprbank_addr   (sprb_a),
	.sprbank_data   (sprb_d),
	.prot_addr      (prot_a),
	.prot_data      (prot_d),
	.blit_addr      (blit_a),
	.blit_data      (blit_d),

	.tile_addr      (tile_a),
	.tile_req       (tile_req),
	.tile_data      (tile_d),
	.tile_ok        (tile_ok),
	.tile_busy      (tile_busy),

	.snd_addr       (snd_rom_a),
	.snd_req        (snd_rom_req),
	.snd_data       (snd_rom_d),
	.snd_ok         (snd_rom_ok),

	.ba0_addr       (ba0_addr),
	.ba_rd          (ba_rd),
	.ba_rdy         (ba_rdy),
	.ba_ack         (ba_ack),
	.sdram_dout     (sdram_dout),
	.prog_en        (prog_en),
	.prog_addr      (prog_addr),
	.prog_ba        (prog_ba),
	.prog_rd        (prog_rd),
	.prog_wr        (prog_wr),
	.prog_din       (prog_din),
	.prog_dsn       (prog_dsn),
	.prog_ack       (prog_ack),
	.prog_rdy       (prog_rdy),

	.ddr_rdaddr     (ddr_rdaddr),
	.ddr_dout       (ddr_dout),
	.ddr_rd_req     (ddr_rd_req),
	.ddr_rd_ack     (ddr_rd_ack),
	.ddr_wraddr     (ddr_wraddr),
	.ddr_din        (ddr_din),
	.ddr_we_req     (ddr_we_req),
	.ddr_we_ack     (ddr_we_ack)
);

// ROM principale in BRAM: ack vero, un ciclo dopo la richiesta.
// dangar_main pretende un ack (non un "sempre pronto"): al ciclo T registra
// indirizzo e richiesta, al T+1 la BRAM vede l'indirizzo, al T+2 il dato e'
// valido. Con rom_ok fisso a 1 latcherebbe il byte precedente: boot nero.
reg main_ok_r;
always @(posedge clk) main_ok_r <= main_rom_req;

// =====================================================================
// DDR3 per la ROM audio. Un solo cliente in lettura + la porta di scrittura
// per il download. Gli altri port restano a zero.
// =====================================================================
ddram_4port u_ddram (
	.DDRAM_CLK       (DDRAM_CLK),
	.DDRAM_BUSY      (DDRAM_BUSY),
	.DDRAM_BURSTCNT  (DDRAM_BURSTCNT),
	.DDRAM_ADDR      (DDRAM_ADDR),
	.DDRAM_DOUT      (DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_RD        (DDRAM_RD),
	.DDRAM_DIN       (DDRAM_DIN),
	.DDRAM_BE        (DDRAM_BE),
	.DDRAM_WE        (DDRAM_WE),

	.wraddr  (ddr_wraddr),
	.din     (ddr_din),
	.we_byte (1'b0),
	.we_req  (ddr_we_req),
	.we_ack  (ddr_we_ack),

	.rdaddr  (ddr_rdaddr),
	.dout    (ddr_dout),
	.rd_req  (ddr_rd_req),
	.rd_ack  (ddr_rd_ack),

	.rdaddr2 (28'd0), .rd_req2 (1'b0), .dout2 (), .rd_ack2 (),
	.rdaddr3 (28'd0), .rd_req3 (1'b0), .dout3 (), .rd_ack3 (),
	.rdaddr4 (28'd0), .rd_req4 (1'b0), .dout4 (), .rd_ack4 (),
	.rdaddr5 (28'd0), .rd_req5 (1'b0), .dout5 (), .rd_ack5 (),
	.rdaddr6 (28'd0), .rd_req6 (1'b0), .dout6 (), .rd_ack6 (),
	.rdaddr7 (28'd0), .rd_req7 (1'b0), .dout7 (), .rd_ack7 (),
	.rdaddr8 (28'd0), .rd_req8 (1'b0), .dout8 (), .rd_ack8 (),
	.rdaddr9 (28'd0), .rd_req9 (1'b0), .dout9 (), .rd_ack9 (),

	.cpaddr  (28'd0), .cpdout (), .cpwr (), .cpreq (1'b0), .cpbusy (),

	.ss_idle (ss_idle),
	.ss_want (ss_want),
	.ss_hold (ss_hold)
);

// =====================================================================
// CPU principale
// =====================================================================
dangar_main #(
	.SS_IDX_WRAM (SS_IDX_WRAM),
	.SS_IDX_CRAM (SS_IDX_CRAM),
	.SS_IDX_SPRB (SS_IDX_SPRB),
	.SS_IDX_REGS (SS_IDX_REGS),
	.SS_IDX_SPRL (SS_IDX_SPRL)
) u_main (
	.clk             (clk),
	.reset           (reset),
	.ce_main         (ce_main_g),
	.pause           (1'b0),          // la pausa e' gia' nel ce
	.p1              (p1),
	.p2              (p2),
	.sys             (sys),
	.service         (service),
	.board_ninjemak  (board_ninjemak),
	.board_youmab    (board_youmab),
	.board_ninjemat  (board_ninjemat),
	.dsw1            (dsw1),
	.dsw2            (dsw2),
	.rom_addr        (main_rom_a),
	.rom_data        (main_rom_d),
	.rom_req         (main_rom_req),
	.rom_ok          (main_ok_r),
	.vblank          (vblank),
	.ss_cpu_reload   (ss_cpu_reload),
	.snd_latch       (snd_latch),
	.snd_latch_wr    (snd_latch_wr),
	.scroll_x        (scroll_x),
	.scroll_y        (scroll_y),
	.layers          (layers),
	.flip_screen     (flip_screen),
	.prot_addr       (prot_a),
	.prot_data       (prot_d),
	.cram_addr_r     (cram_a),
	.cram_data_r     (cram_d),
	.spr_addr_r      (spr_a),
	.spr_data_r      (spr_d),
	.spr_buffer_copy (spr_buffer_copy),
	.frame_tick      (spr_buffer_copy),   // stesso fronte: inizio del VBlank
	.blit_rom_addr   (blit_a),
	.blit_rom_data   (blit_d),
	.blit_busy       (blit_busy),
	.ss_cpu_in       (ss_main_in),
	.ss_cpu_wr       (ss_main_wr),
	.ss_cpu_out      (ss_main_out),
	.ss_wram         (ss_wram),
	.ss_cram         (ss_cram),
	.ss_sprb         (ss_sprb),
	.ss_regs         (ss_regs),
	.ss_sprl         (ss_sprl)
);

// =====================================================================
// Audio
// =====================================================================
// LATCH_XFORM(0): la trasformazione ((d & 0x7f) << 1) | 1 del soundlatch
// (galivan.cpp:702-705) la applica gia' dangar_main quando la CPU principale
// scrive su I/O 0x45. Farla anche qui la applicherebbe DUE volte e corromperebbe
// ogni comando sonoro. Il default del modulo e' 1: va sovrascritto.
dangar_sound #(
	.LATCH_XFORM (0),
	.SS_IDX_SRAM (SS_IDX_SRAM),
	.SS_IDX_YMSH (SS_IDX_YMSH),
	.SS_IDX_SGLUE(SS_IDX_SGLUE)
) u_sound (
	.clk        (clk),
	.reset      (reset),
	.ce_snd     (ce_snd_g),
	.ce_ym      (ce_ym_g),
	.latch_data (snd_latch),
	.latch_wr   (snd_latch_wr),
	.rom_addr   (snd_rom_a),
	.rom_data   (snd_rom_d),
	.rom_req    (snd_rom_req),
	.rom_ok     (snd_rom_ok),
	.audio_l    (audio_l),
	.audio_r    (audio_r),
	.ss_cpu_in  (ss_snd_in),
	.ss_cpu_wr  (ss_snd_wr),
	.ss_cpu_out (ss_snd_out),
	.ss_sram    (ss_sram),
	.ss_ymsh    (ss_ymsh),
	.ss_sglue   (ss_sglue)
);

// =====================================================================
// Video
// =====================================================================
dangar_video u_video (
	.clk          (clk),
	.reset        (reset),
	.ce_pix       (ce_pix),
	.board_ninjemak (board_ninjemak),
	.board_youmab   (board_youmab),
	.board_ninjemat (board_ninjemat),
	.hcnt         (hcnt),
	.vcnt         (vcnt),
	.scroll_x     (scroll_x),
	.scroll_y     (scroll_y),
	.layers       (layers),
	.flip_screen  (flip_screen),
	.cram_addr    (cram_a),
	.cram_data    (cram_d),
	.spr_addr     (spr_a),
	.spr_data     (spr_d),
	.bgmap_addr   (bgmap_a),
	.bgmap_data   (bgmap_d),
	.tile_addr    (tile_a),
	.tile_req     (tile_req),
	.tile_data    (tile_d),
	.tile_ok      (tile_ok),
	.tile_busy    (tile_busy),
	.char_addr    (char_a),
	.char_data    (char_d),
	.sprrom_addr  (sprr_a),
	.sprrom_data  (sprr_d),
	.prom_addr    (prom_a),
	.prom_data    (prom_d),
	.sprbank_addr (sprb_a),
	.sprbank_data (sprb_d),
	.en_bg        (en_bg),
	.en_txt       (en_txt),
	.en_spr       (en_spr),
	.rgb          (rgb)
);

endmodule
