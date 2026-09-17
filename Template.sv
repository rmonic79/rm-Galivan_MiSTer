// SPDX-License-Identifier: GPL-3.0-or-later
/*  This file is part of rmGalivan_MiSTer.
    GPL-3.
    Based on the MiSTer core Template by Sorgelig.
    Author: Umberto Parisi (rmonic79)
*/

// Ufo Robo Dangar (Nichibutsu 1986) — MiSTer core
// HW Galivan (PCB GV-1412-I / GV-1412-II):
//   Z80B @6MHz main + Z80A @4MHz sound, YM3526 + 2x DAC 8bit R2R,
//   char 8x8x4 + tiles 16x16x4 + sprite, palette da PROM, 256x224 @59.41Hz ROT270
// Base: import da DJBoy (Kaneko 1989), da cui eredita infrastruttura e savestate.

module emu
(
	input         CLK_50M,
	input         RESET,
	inout  [45:0] HPS_BUS,
	output        CLK_VIDEO,
	output        CE_PIXEL,
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,
	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER,
	output        VGA_DISABLE,

	// CRT Adjust (sys-side): valori dall'OSD + VBlank VERO, inoltrati agli stadi
	// crt_vsize / crt_adjust_sys che stanno in sys_top (solo ramo VGA analogico).
	output              CRT_ON,
	output signed [5:0] CRT_HSIZE,
	output signed [8:0] CRT_HPOS,
	output signed [5:0] CRT_VSHIFT,
	output signed [5:0] CRT_VSIZE,
	output              CRT_VSMODE,
	output              CRT_VBL,

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,

`ifdef MISTER_FB
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,
`ifdef MISTER_FB_PALETTE
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,
	output  [1:0] BUTTONS,

	input         CLK_AUDIO,
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,
	output  [1:0] AUDIO_MIX,

	inout   [3:0] ADC_BUS,

	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Unused ports /////////
assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
// DDRAM HPS pilotato dal game (ROM CPU + OKI + savestate via ddram_4port)
assign DDRAM_CLK = clk_sys;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
// joy0/1 = P1/P2 (dichiarati qui: usati dal blocco pausa sotto).
wire [15:0] joy0, joy1;
// Pause: toggle on rising edge of joy[12] (bit MiSTer pause built-in,
// indipendente dai bottoni in J1).
reg pause_toggle;
reg joy_pause_prev;
always @(posedge clk_sys) begin
	if (reset) begin
		pause_toggle <= 1'b0;
		joy_pause_prev <= 1'b0;
	end else begin
		joy_pause_prev <= joy0[12] | joy1[12];
		if ((joy0[12] | joy1[12]) && !joy_pause_prev)
			pause_toggle <= ~pause_toggle;
	end
end
wire pause = pause_toggle;     // solo joypad (bit 12 built-in MiSTer)
wire clean_pause = status[35]; // overlay off durante pausa
assign HDMI_FREEZE = 1'b0;  // overlay pause è renderizzato in real-time, no freeze scaler
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 1;  // signed audio
wire signed [15:0] game_audio_l, game_audio_r;
// Pausa frame-aligned. Logica portata da Raiden.sv:159-182: una volta che il
// savestate ha chiesto la pausa e siamo gia' fermi, si RESTA fermi finche'
// ss_mgr_pause non scende (cioe' a DMA finito), altrimenti memory_stream
// campionerebbe uno stato incoerente.
reg  paused_safe_r;
wire paused_safe = paused_safe_r;
always @(posedge clk_sys) begin
	if (reset)
		paused_safe_r <= 1'b0;
	else if (VBlank) begin
		if (ss_mgr_pause & paused_safe_r) paused_safe_r <= 1'b1;
		else                              paused_safe_r <= pause | ss_mgr_pause;
	end
end
assign AUDIO_L = game_audio_l;
assign AUDIO_R = game_audio_r;
assign AUDIO_MIX = 0;

assign LED_USER  = 0;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

`include "build_id.v"
localparam CONF_STR = {
	"Galivan;SS3E000000:200000;",
	"-;",
	"O[109:105],Savestate Slot,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32;",
	"R[110],Save state (Alt-F1);",
	"R[111],Restore state (F1);",
	"-;",
	"P1,Video;",
	"P1O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O[21:19],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer,HV-Integer;",
	"P1O[2:1],Rotate,No,CCW (TATE),CW;",
	"P1O[3],Flip 180,Off,On;",
	"P1O[22],Refresh Rate,Original 59.4Hz,60Hz;",
	"P1O[112],CRT Adjust,Off,On;",
	"H1P1O[67:62],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H1P1O[104:98],CRT H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,+32,+33,+34,+35,+36,+37,+38,+39,+40,+41,+42,+43,+44,+45,+46,+47,+48,-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H1P1O[61:56],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H1P1O[116:113],CRT V-Size,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H1P1O[117],CRT V-Size Mode,PVM,Cabinet;",
	"-;",
	"O[35],Clean Pause,Off,On;",
	"-;",
	"O[30],Layer BG,On,Off;",
	"O[31],Sprite,On,Off;",
	"O[32],Layer Text,On,Off;",
	"-;",
	"DIP;",
	"-;",
	"T[36],Service;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"-;",
	// J1: bit 4=Punch(A), 5=Kick(B), 6=Jump(X), 7,8,9=unused, 10=Start1, 11=Coin1,
	// 12=Pause, 13=Start2, 14=Coin2 (MiSTer arcade convention fissa — pattern Raiden)
	"J1,Punch,Kick,Jump,-,-,-,Start,Coin,Pause,Start 2P,Coin 2P;",
	"jn,A,B,X,,,,Start,R,L,Select,;",
	"V,v",`BUILD_DATE
};

wire forced_scandoubler;
wire [21:0] gamma_bus;   // OSD framework <-> gamma_fast (inout, decodifica interna)
wire  [1:0] buttons;
wire [127:0] status;
wire [10:0] ps2_key;
// ROM di Dangar non crittate: ioctl va diretto a dangar_mem (nessuna cascata decrypt).
wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;   // 16-bit: WIDE=1
// ioctl_wait: lo produce il gioco. dangar_mem tiene fermo l'HPS finche' le
// scritture verso SDRAM e DDR3 non sono passate; le BRAM non hanno attesa.
// (Prima c'era anche `ioctl_wait_sdram`, che lo pilotava il bridge SDRAM di
//  DJ Boy: cancellato quello, restava un wire NON PILOTATO in OR dentro il
//  percorso di caricamento della ROM.)
wire        ioctl_wait_game;
wire        ioctl_wait = ioctl_wait_game;

hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),
	.forced_scandoubler(forced_scandoubler),
	.buttons(buttons),
	.status(status),
	.status_menumask({14'd0, ~status[112], 1'b0}),  // H1: gruppo CRT Adjust visibile solo se On
	.ps2_key(ps2_key),
	.joystick_0(joy0),
	.joystick_1(joy1),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait)
);

// === Savestate UI: trigger save/load da tasti (Alt+F1-F4 / F1-F4), gamepad, OSD ===
wire        ss_save, ss_load;
wire [4:0]  ss_slot;        // 32 slot: [4:3]=regione (file .ss1-.ss4), [2:0]=sotto-slot
wire [15:0] joy_all = joy0 | joy1;
savestate_ui #(.INFO_TIMEOUT_BITS(25)) u_ss_ui (
	.clk         (clk_sys),
	.ps2_key     (ps2_key),
	.allow_ss    (1'b1),
	.joySS       (joy_all[13]),   // Select
	.joyRight    (joy_all[0]),
	.joyLeft     (joy_all[1]),
	.joyDown     (joy_all[2]),
	.joyUp       (joy_all[3]),
	.joyStart    (joy_all[12]),
	.joyRewind   (1'b0),
	.rewindEnable(1'b0),
	.status_slot (status[109:105]),
	.autoincslot (1'b0),
	.OSD_saveload(status[111:110]),  // R[110]=save, R[111]=restore
	.ss_save     (ss_save),
	.ss_load     (ss_load),
	.ss_info_req (),
	.ss_info     (),
	.statusUpdate(),
	.selected_slot(ss_slot)
);

// --- INPUT DANGAR ---------------------------------------------------------
// INPUT_PORTS_START(dangar) = PORT_INCLUDE(galivan) + PORT_MODIFY (galivan.cpp:962-991).
// Tutto ATTIVO BASSO (IP_ACTIVE_LOW). Letti dalla CPU su I/O 0x00/0x01/0x02
// (galivan.cpp:751-753).
//
//   P1/P2 (galivan.cpp:879-895):
//     bit0 UP  bit1 DOWN  bit2 LEFT  bit3 RIGHT  bit4 BUTTON1  bit5 BUTTON2
//     bit6 UNKNOWN
//     bit7 BUTTON3 su GALIVAN ("hold to move while hanging", galivan.cpp:884),
//          IPT_UNKNOWN su dangar (PORT_MODIFY :965-969). Lo stesso RBF serve
//          entrambi i set: qui il bit si collega sempre, e su Dangar resta
//          semplicemente un ingresso che il gioco non legge.
//   SYSTEM (galivan.cpp:898-906):
//     bit0 START1  bit1 START2  bit2 COIN1  bit3 COIN2
//     bit4 SERVICE1  bit5 PORT_SERVICE (dip di servizio)  bit6-7 UNKNOWN
//
// Layout joystick MiSTer: [0]=Right [1]=Left [2]=Down [3]=Up
//   [4]=A [5]=B [10]=Start [11]=Coin [12]=Pause [13]=Start2 [14]=Coin2
// Board select — un byte dalla regione MRA index=1, NON dai DIP.
//
// L'HPS scarica nell'ordine index=1 -> index=0 (ROM) -> index=254 (DIP), quindi
// questo e' gia' latchato quando comincia il download delle ROM. I DIP no:
// arrivano DOPO, e lo status dell'OSD e' peggio ancora (runtime, e l'utente lo
// cambia). Serve valido DURANTE il download perche' decide dove vanno le ROM.
//
// bit 0 = Ninja Emaki ; bit 1 = bootleg Game Electronics (implica il bit 0) ;
// bit 2 = licenza Tecfri (`ninjemat`), che NON implica il bit 0: ha l'I/O di
// Galivan e il video di Ninja Emaki, quindi i due bit sono indipendenti.
// Tutti a zero = Galivan / Dangar (compreso dangarj).
//
// Default 0: un MRA senza la regione index=1 — cioe' tutti gli otto gia' fatti —
// si comporta esattamente come prima. Non azzerato dal reset di gioco: lo scrive
// solo ioctl_wr, cosi' un soft reset dall'OSD non riporta il core alla variante
// base. ioctl_index e' a 16 bit: si confronta con 16'd1, non con l'indice corto.
reg board_ninjemak = 1'b0;
reg board_youmab   = 1'b0;
reg board_ninjemat = 1'b0;
always @(posedge clk_sys)
	if (ioctl_wr && (ioctl_index == 16'd1)) begin
		board_ninjemak <= ioctl_dout[0];
		board_youmab   <= ioctl_dout[1];
		board_ninjemat <= ioctl_dout[2];
	end

// Terzo pulsante: STA SU UN BIT DIVERSO nelle due schede, verificato negli
// INPUT_PORTS di galivan.cpp.
//   Galivan      bit 7 = BUTTON3 ("hold to move while hanging", pulsante di
//                gioco vero), bit 6 non usato
//   Ninja Emaki  bit 6 = BUTTON3 ("only in test mode"), bit 7 non usato
//   Dangar       nessuno dei due: la sua PORT_MODIFY mette IPT_UNKNOWN su 0x80
// Mandarlo sempre sul bit 7 lo rendeva inerte su Ninja Emaki e per giunta
// teneva mosso un bit che li' deve stare a riposo.
wire b3_p1 = ~joy0[6];
wire b3_p2 = ~joy1[6];

wire [7:0] p1_port = {
	board_ninjemak ? 1'b1 : b3_p1,   // bit 7 BUTTON3 su Galivan
	board_ninjemak ? b3_p1 : 1'b1,   // bit 6 BUTTON3 su Ninja Emaki
	~joy0[5],                   // bit 5 BUTTON2
	~joy0[4],                   // bit 4 BUTTON1
	~joy0[0],                   // bit 3 RIGHT
	~joy0[1],                   // bit 2 LEFT
	~joy0[2],                   // bit 1 DOWN
	~joy0[3]                    // bit 0 UP
};
wire [7:0] p2_port = {
	board_ninjemak ? 1'b1 : b3_p2,   // bit 7 BUTTON3 su Galivan
	board_ninjemak ? b3_p2 : 1'b1,   // bit 6 BUTTON3 su Ninja Emaki
	~joy1[5],
	~joy1[4],
	~joy1[0],
	~joy1[1],
	~joy1[2],
	~joy1[3]
};
wire [7:0] sys_port = {
	2'b11,                      // bit 7,6 non usati
	1'b1,                       // bit 5 dip di servizio (a riposo)
	~status[36],                // bit 4 SERVICE1 (tasto OSD)
	~(joy1[11] | joy0[14]),     // bit 3 COIN2
	~joy0[11],                  // bit 2 COIN1
	~(joy1[10] | joy0[13]),     // bit 1 START2
	~joy0[10]                   // bit 0 START1
};

// Porta SERVICE, esiste SOLO su Ninja Emaki (galivan.cpp, INPUT_PORTS ninjemak):
// un unico bit vero, PORT_SERVICE su 0x02; tutto il resto e' IPT_UNKNOWN a
// riposo. Attiva bassa come il resto della PCB. Sugli altri set questo filo non
// viene mai letto, perche' la porta 0x83 nella loro io_map non c'e'.
wire [7:0] service_port = {6'b111111, ~status[36], 1'b1};

// DSW dall'MRA via ioctl (index 254): {DSW2, DSW1}.
// Default di fabbrica dal driver: DSW1=0xDF, DSW2=0x7F (galivan.cpp:908-991,
// stessi valori dichiarati in tools/dangar.yaml -> <switches default="DF,7F">).
reg [15:0] dsw_port = 16'h7FDF;
always @(posedge clk_sys)
	if (ioctl_wr && (ioctl_index == 16'd254) && !ioctl_addr[26:1])
		dsw_port <= ioctl_dout;


///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
wire pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

// Game reset: includes download (game held in reset while ROM loads)
// + hold counter: tiene reset alto per ~2^17 cicli dopo che la causa cade,
// per dare tempo a SDRAM/clear FSM/PLL di stabilizzarsi.
wire reset_cause = RESET | status[0] | buttons[1] | ~pll_locked | ioctl_download;
reg [16:0] reset_hold_cnt = 17'h1FFFF;  // parte carico al power-on
always @(posedge clk_sys) begin
	if (reset_cause) reset_hold_cnt <= 17'h1FFFF;  // ricarica finche' c'e' causa
	else if (reset_hold_cnt != 17'd0) reset_hold_cnt <= reset_hold_cnt - 17'd1;
end
wire reset = (reset_hold_cnt != 17'd0);
// Bridge reset: ONLY pll_locked — bridge must run during download, before RESET drops
wire bridge_reset = ~pll_locked;
// Video reset: ONLY pll_locked — CRT needs sync always, even during RESET and download
wire video_reset = ~pll_locked;

///////////////////////   SDRAM (jtframe_sdram64, banchi paralleli)  //
//
// Banco 0 = grafica dei tile 16x16 (128 KB). Gli altri tre non sono usati:
// tutto il resto sta in BRAM dentro dangar_mem, tranne la ROM del Z80 audio
// che sta in DDR3 via ddram_4port.
//
// Download: le scritture verso il banco 0 le genera dangar_mem sui prog_*.
///////////////////////////////////////////////////////////////////////

localparam SDRAM_AW = 22;

// Per-bank request signals (driven by bridge)
wire [SDRAM_AW-1:0] ba0_addr, ba1_addr, ba2_addr, ba3_addr;
wire [3:0]          ba_rd, ba_wr;
wire [15:0]         ba0_din, ba1_din, ba2_din, ba3_din;
wire [1:0]          ba0_dsn, ba1_dsn, ba2_dsn, ba3_dsn;
wire [3:0]          ba_ack, ba_rdy, ba_dst, ba_dok;
wire [15:0]         sdram_dout_jt;

// Program (download) interface
wire                prog_en;
wire [SDRAM_AW-1:0] prog_addr;
wire [1:0]          prog_ba;
wire                prog_rd, prog_wr;
wire [15:0]         prog_din;
wire [1:0]          prog_dsn;
wire                prog_ack, prog_rdy, prog_dst, prog_dok;

// Refresh trigger: 1 pulse al rising edge di HBlank/VBlank — refresh module accumula debt.
reg vblank_d, hblank_d;
always @(posedge clk_sys) begin vblank_d <= VBlank; hblank_d <= HBlank; end
wire rfsh_pulse = (HBlank & ~hblank_d) | (VBlank & ~vblank_d);

// Solo il banco 0 e' in uso (grafica dei tile). Gli altri tre restano a zero:
// jtframe_sdram64 li istanzia comunque, ma non li si stimola mai.
assign ba1_addr = {SDRAM_AW{1'b0}};
assign ba2_addr = {SDRAM_AW{1'b0}};
assign ba3_addr = {SDRAM_AW{1'b0}};
assign ba_wr    = 4'b0000;
assign ba0_din  = 16'd0;
assign ba1_din  = 16'd0;
assign ba2_din  = 16'd0;
assign ba3_din  = 16'd0;
assign ba0_dsn  = 2'b11;
assign ba1_dsn  = 2'b11;
assign ba2_dsn  = 2'b11;
assign ba3_dsn  = 2'b11;

wire sdram_init_w;
wire sdram_ready = ~sdram_init_w;

jtframe_sdram64 #(
	.AW           ( SDRAM_AW ),
	.HF           ( 1        ),     // 96 MHz operation
	.SHIFTED      ( 0        ),
	.BA0_LEN      ( 16       ),     // single-word burst (1 word per fetch)
	.BA1_LEN      ( 16       ),
	.BA2_LEN      ( 16       ),
	.BA3_LEN      ( 16       ),
	.PROG_LEN     ( 16       ),     // program writes 1 word
	.MISTER       ( 1        ),
	.BA1_WEN      ( 0        ),
	.BA2_WEN      ( 0        ),
	.BA3_WEN      ( 0        ),
	.BA0_AUTOPRECH( 0        ),
	.BA1_AUTOPRECH( 0        ),
	.BA2_AUTOPRECH( 0        ),
	.BA3_AUTOPRECH( 0        )
) u_sdram_jt (
	.rst        ( ~pll_locked ),
	.clk        ( clk_sys     ),
	.init       ( sdram_init_w ),

	.ba0_addr   ( ba0_addr ),
	.ba1_addr   ( ba1_addr ),
	.ba2_addr   ( ba2_addr ),
	.ba3_addr   ( ba3_addr ),

	.rd         ( ba_rd    ),
	.wr         ( ba_wr    ),
	.ba0_din    ( ba0_din  ),
	.ba0_dsn    ( ba0_dsn  ),
	.ba1_din    ( ba1_din  ),
	.ba1_dsn    ( ba1_dsn  ),
	.ba2_din    ( ba2_din  ),
	.ba2_dsn    ( ba2_dsn  ),
	.ba3_din    ( ba3_din  ),
	.ba3_dsn    ( ba3_dsn  ),

	.rdy        ( ba_rdy ),
	.ack        ( ba_ack ),
	.dst        ( ba_dst ),
	.dok        ( ba_dok ),

	// Program (ROM-load) interface
	.prog_en    ( prog_en   ),
	.prog_addr  ( prog_addr ),
	.prog_ba    ( prog_ba   ),
	.prog_rd    ( prog_rd   ),
	.prog_wr    ( prog_wr   ),
	.prog_din   ( prog_din  ),
	.prog_dsn   ( prog_dsn  ),
	.prog_rdy   ( prog_rdy  ),
	.prog_dst   ( prog_dst  ),
	.prog_dok   ( prog_dok  ),
	.prog_ack   ( prog_ack  ),

	// SDRAM pins
	.sdram_dq   ( SDRAM_DQ   ),
	.sdram_a    ( SDRAM_A    ),
	.sdram_dqml ( SDRAM_DQML ),
	.sdram_dqmh ( SDRAM_DQMH ),
	.sdram_nwe  ( SDRAM_nWE  ),
	.sdram_ncas ( SDRAM_nCAS ),
	.sdram_nras ( SDRAM_nRAS ),
	.sdram_ncs  ( SDRAM_nCS  ),
	.sdram_ba   ( SDRAM_BA   ),
	.sdram_cke  ( SDRAM_CKE  ),

	// Shared read data bus
	.dout       ( sdram_dout_jt ),
	.rfsh       ( rfsh_pulse    )
);

// SDRAM_CLK driven via altddio_out (180° shift) — pattern identico a Sorgelig.
altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk_sys),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

///////////////////////   CLOCK ENABLES   ///////////////////////////////
// XTAL PCB: 12 MHz (CPU/audio) + 16 MHz (video). clk_sys = 96 MHz.
// ce_pix: 96/16 = 6 MHz pixel clock.
// set_raw(XTAL(12'000'000)/2, 384, 0, 256, 263, 16, 240) (galivan.cpp:1181):
// 6e6/384 = 15625.0 Hz ; 6e6/(384*263) = 59.4106 Hz. NON i 15.6242/59.40776 delle
// note PCB in testa al driver: quelle sono della board di Ninja Emaki.
reg [3:0] ce_pix_cnt;
reg       ce_pix_r;
always @(posedge clk_sys) begin
	if (video_reset) begin
		ce_pix_cnt <= 4'd0;
		ce_pix_r   <= 1'b0;
	end else if (ce_pix_cnt == 4'd15) begin
		ce_pix_cnt <= 4'd0;
		ce_pix_r   <= 1'b1;
	end else begin
		ce_pix_cnt <= ce_pix_cnt + 4'd1;
		ce_pix_r   <= 1'b0;
	end
end
wire ce_pix = ce_pix_r;

// Layer enable OSD ("On,Off" → bit=0 = ON)
wire layer_bg_en  = ~status[30];
wire layer_spr_en = ~status[31];
wire layer_txt_en = ~status[32];

wire [9:0]  render_x;
wire [8:0]  render_y;

// =========================================================================
// [SS-HOOK] SAVESTATE — framework portato da Raiden (Raiden.sv:1244-1367)
// -------------------------------------------------------------------------
// Cancellando questo blocco, rtl/ss/ e gli hook [SS-HOOK] in dangar_top il core
// torna identico al baseline senza savestate.
//
// SS_IDX_* = indice univoco di ogni blocco di stato. Per ora ci sono solo i tre
// Z80 (gestione Darius: tv80s auto_ss 358 bit + auto_save_adaptor). RAM, video e
// contesto chip audio si aggiungono qui man mano che il game RTL di Dangar sale.
// =========================================================================
localparam SS_IDX_Z80M   = 0;   // registri Z80 main   (tv80s auto_ss, 358 bit)
localparam SS_IDX_Z80SND = 1;   // registri Z80 sound  (tv80s auto_ss, 358 bit)
localparam SS_IDX_WRAM   = 2;   // work RAM 8 KB 0xE000-0xFFFF (spriteram inclusa)
localparam SS_IDX_CRAM   = 3;   // char RAM 2 KB
localparam SS_IDX_SPRB   = 4;   // buffer sprite 256 B
localparam SS_IDX_REGS   = 5;   // scroll, layer, flip, banco, soundlatch, IRQ
// --- sotto-sistema audio (schema di Raiden) ---
localparam SS_IDX_SRAM   = 6;   // RAM 2 KB del Z80 sound
localparam SS_IDX_YMSH   = 7;   // shadow dei 256 registri del YM3526
localparam SS_IDX_SPRL   = 8;   // copia viva della sprite RAM (256 B)
localparam SS_IDX_SGLUE  = 9;   // soundlatch, IRQ, DAC, address latch del chip
                                // DEVE restare l'ULTIMO: il suo commit fa
                                // partire il replay dei registri nel chip, e a
                                // quel punto la shadow deve essere gia' a posto.
localparam SS_NSLAVES    = 10;
localparam SS_MS_COUNT   = 16;  // potenza di 2 >= NSLAVES. Fissato a 16 come Raiden:
                                // definisce il layout dell'header dello slot, quindi
                                // NON va cambiato dopo il primo save (romperebbe i .ss).

// Bus DDR (pattern Taito F2 ddr_if + mux), identico a Raiden.sv:1244-1248:
//   ddr_game = client a  -> ddram_4port dentro il game (ROM CPU + OKI)
//   ddr_rot  = client b  -> FIFO del rotate (write del framebuffer HPS)
//   ddr_host = uscita del mux -> ss_ddr_gate -> pin DDRAM_*
//   ddr_ss   = client del savestate (memory_stream) -> gate -> pin
ddr_if     ddr_game();
ddr_if     ddr_rot();
ddr_if     ddr_host();
ddr_if     ddr_ss();
ssbus_if   ssbus();
ssbus_if   ssb[SS_NSLAVES]();

wire ss_busy;                   // DMA savestate in corso
wire ss_slot_empty;             // load su slot mai scritto
wire ss_mgr_pause;              // richiesta pausa dal coordinatore (-> paused_safe nel game)
wire ss_mgr_wr, ss_mgr_rd;
wire ss_cpu_reload;             // impulso esteso dopo il load: va al game e rimette
                                // a riposo le macchine con stato transitorio non
                                // salvato (fetch ROM, copia sprite). E' il requisito
                                // del restore deterministico.

// raiden_ss_manager: ss_save/ss_load NON triggano il DMA direttamente (partirebbe a
// meta' frame). Il manager mette in pausa PRIMA, aspetta paused_safe stabile (confine
// frame), POI pulsa read/write_start.
raiden_ss_manager u_ss_mgr (
	.clk           (clk_sys),
	.reset         (reset),
	.ss_save       (ss_save),
	.ss_load       (ss_load),
	.paused_safe   (paused_safe),
	.ss_busy       (ss_busy),
	.slot_empty    (ss_slot_empty),
	.ss_pause      (ss_mgr_pause),
	.write_start   (ss_mgr_wr),
	.read_start    (ss_mgr_rd),
	.ss_cpu_reload (ss_cpu_reload)
);

save_state_data #(.COUNT(SS_MS_COUNT)) u_ss_data (
	.clk         (clk_sys),
	.reset       (reset),
	.ddr         (ddr_ss),
	.read_start  (ss_mgr_rd),
	.write_start (ss_mgr_wr),
	.index       (ss_slot),
	.busy        (ss_busy),
	.slot_empty  (ss_slot_empty),
	.ssbus       (ssbus)
);

ssbus_mux #(.COUNT(SS_NSLAVES)) u_ssbus_mux (
	.clk    (clk_sys),
	.masters(ssb),
	.slave  (ssbus)
);

// --- mux gioco/rotate, poi gate col savestate ---
// A SS inattivo il gate e' inerte: i pin seguono il mux, bit-identico al baseline.
wire        ss_hold, ss_ddr_grant, ss_idle, ss_want;
wire        ss_tx_inflight = ddr_ss.read | ddr_ss.write;
wire  [7:0] game_DDRAM_BURSTCNT;
wire [28:0] game_DDRAM_ADDR;
wire        game_DDRAM_RD;
wire [63:0] game_DDRAM_DIN;
wire  [7:0] game_DDRAM_BE;
wire        game_DDRAM_WE;

// Adattamento del ddram_4port (che parla in pin DDRAM_*) al ddr_if del mux.
// addr del ddr_if e' un indirizzo di BYTE, DDRAM_ADDR e' a parole da 64 bit:
// {addr29, 3'b0} e il gate poi rifa addr[31:3]. acquire = ss_want (richiesta
// pendente): quando il gioco non ha nulla da fare lo lascia al rotate.
assign ddr_game.addr       = {game_DDRAM_ADDR, 3'b0};
assign ddr_game.wdata      = game_DDRAM_DIN;
assign ddr_game.read       = game_DDRAM_RD;
assign ddr_game.write      = game_DDRAM_WE;
assign ddr_game.burstcnt   = game_DDRAM_BURSTCNT;
assign ddr_game.byteenable = game_DDRAM_BE;
assign ddr_game.acquire    = ss_want;

raiden_ddr_mux u_ddr_mux (
	.clk     (clk_sys),
	.ss_hold (ss_hold),   // durante SS blocca l'emissione dei client alla sorgente
	.x       (ddr_host),
	.a       (ddr_game),
	.b       (ddr_rot)
);

ss_ddr_gate #(.AW(29), .DRAIN_TH(3)) u_ss_ddr_gate (
	.clk             (clk_sys),
	.reset           (reset),
	.ss_busy         (ss_busy),
	.ss_tx_inflight  (ss_tx_inflight),
	// master GIOCO = uscita del mux (gioco + rotate gia' arbitrati)
	.game_burstcnt   (ddr_host.burstcnt),
	.game_addr       (ddr_host.addr[31:3]),
	.game_rd         (ddr_host.read),
	.game_din        (ddr_host.wdata),
	.game_be         (ddr_host.byteenable),
	.game_we         (ddr_host.write),
	// master SAVESTATE
	.ss_burstcnt     (ddr_ss.burstcnt),
	.ss_addr         (ddr_ss.addr[31:3]),
	.ss_rd           (ddr_ss.read),
	.ss_din          (ddr_ss.wdata),
	.ss_be           (ddr_ss.byteenable),
	.ss_we           (ddr_ss.write),
	// controller
	.DDRAM_BUSY      (DDRAM_BUSY),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_BURSTCNT  (DDRAM_BURSTCNT),
	.DDRAM_ADDR      (DDRAM_ADDR),
	.DDRAM_RD        (DDRAM_RD),
	.DDRAM_DIN       (DDRAM_DIN),
	.DDRAM_BE        (DDRAM_BE),
	.DDRAM_WE        (DDRAM_WE),
	.ss_hold         (ss_hold),
	.ss_ddr_grant    (ss_ddr_grant)
);

// Ritorno DDR ai due master (forma identica a Raiden.sv:1357-1367).
// Al lato gioco/rotate: dout_ready mascherata quando il bus e' concesso al SS;
// busy alto anche in fase di drain (ss_hold) cosi' i client stallano e il bus si
// svuota, permettendo al gate di concedere.
assign ddr_host.rdata       = DDRAM_DOUT;
assign ddr_host.rdata_ready = ss_ddr_grant ? 1'b0 : DDRAM_DOUT_READY;
assign ddr_host.busy        = (ss_ddr_grant | ss_hold) ? 1'b1 : DDRAM_BUSY;
assign ddr_ss.rdata         = DDRAM_DOUT;
assign ddr_ss.rdata_ready   = ss_ddr_grant ? DDRAM_DOUT_READY : 1'b0;
assign ddr_ss.busy          = ss_ddr_grant ? DDRAM_BUSY : 1'b1;

///////////////////////   GAME   ///////////////////////////////

wire [23:0] game_rgb;

dangar_top #(
	.SS_IDX_WRAM (SS_IDX_WRAM),
	.SS_IDX_CRAM (SS_IDX_CRAM),
	.SS_IDX_SPRB (SS_IDX_SPRB),
	.SS_IDX_REGS (SS_IDX_REGS),
	.SS_IDX_SRAM (SS_IDX_SRAM),
	.SS_IDX_YMSH (SS_IDX_YMSH),
	.SS_IDX_SGLUE(SS_IDX_SGLUE),
	.SS_IDX_SPRL (SS_IDX_SPRL)
) u_game
(
	.clk   (clk_sys),
	.reset (reset),
	.pause (paused_safe),
	.board_ninjemak (board_ninjemak),
	.board_youmab   (board_youmab),
	.board_ninjemat (board_ninjemat),
	.ss_cpu_reload (ss_cpu_reload),

	// input di gioco (mappatura Dangar, INPUT_PORTS_START(dangar) galivan.cpp:962)
	.p1   (p1_port),
	.p2   (p2_port),
	.sys  (sys_port),
	.service (service_port),
	.dsw1 (dsw_port[7:0]),
	.dsw2 (dsw_port[15:8]),

	// raster
	.hcnt   (hcnt),
	.vcnt   (vcnt),
	.hblank (HBlank),
	.vblank (VBlank),
	.ce_pix (ce_pix),

	// enable di debug dall'OSD
	.en_bg  (layer_bg_en),
	.en_txt (layer_txt_en),
	.en_spr (layer_spr_en),

	// download
	.ioctl_download (ioctl_download),
	.ioctl_wr       (ioctl_wr),
	.ioctl_addr     (ioctl_addr),
	.ioctl_dout     (ioctl_dout),
	.ioctl_index    (ioctl_index),
	.sdram_ready    (sdram_ready),
	.ioctl_wait     (ioctl_wait_game),

	// SDRAM: solo il banco 0, la grafica dei tile (128 KB)
	.ba0_addr   (ba0_addr),
	.ba_rd      (ba_rd),
	.ba_rdy     (ba_rdy),
	.ba_ack     (ba_ack),
	.sdram_dout (sdram_dout_jt),
	.prog_en    (prog_en),
	.prog_addr  (prog_addr),
	.prog_ba    (prog_ba),
	.prog_rd    (prog_rd),
	.prog_wr    (prog_wr),
	.prog_din   (prog_din),
	.prog_dsn   (prog_dsn),
	.prog_ack   (prog_ack),
	.prog_rdy   (prog_rdy),

	// DDR3: ROM del Z80 audio, via ddram_4port dentro il gioco.
	// I pin non li tocca: le sue uscite vanno al ddr_mux (client a) e da li'
	// al ss_ddr_gate; i ritorni glieli da' il mux, che lo mette in busy quando
	// il bus ce l'ha il rotate o il savestate.
	.DDRAM_CLK        (clk_sys),
	.DDRAM_BUSY       (ddr_game.busy),
	.DDRAM_BURSTCNT   (game_DDRAM_BURSTCNT),
	.DDRAM_ADDR       (game_DDRAM_ADDR),
	.DDRAM_DOUT       (ddr_game.rdata),
	.DDRAM_DOUT_READY (ddr_game.rdata_ready),
	.DDRAM_RD         (game_DDRAM_RD),
	.DDRAM_DIN        (game_DDRAM_DIN),
	.DDRAM_BE         (game_DDRAM_BE),
	.DDRAM_WE         (game_DDRAM_WE),
	.ss_idle          (ss_idle),
	.ss_want          (ss_want),
	.ss_hold          (ss_hold),

	// uscite
	.rgb     (game_rgb),
	.audio_l (game_audio_l),
	.audio_r (game_audio_r),

	// [SS-HOOK] chunk savestate dei due Z80
	.ss_main_in  (z80m_ss_in),
	.ss_main_wr  (z80m_ss_wr),
	.ss_main_out (z80m_ss_out),
	.ss_snd_in   (z80s_ss_in),
	.ss_snd_wr   (z80s_ss_wr),
	.ss_snd_out  (z80s_ss_out),
	.ss_wram     (ssb[SS_IDX_WRAM]),
	.ss_cram     (ssb[SS_IDX_CRAM]),
	.ss_sprb     (ssb[SS_IDX_SPRB]),
	.ss_regs     (ssb[SS_IDX_REGS]),
	.ss_sram     (ssb[SS_IDX_SRAM]),
	.ss_ymsh     (ssb[SS_IDX_YMSH]),
	.ss_sglue    (ssb[SS_IDX_SGLUE]),
	.ss_sprl     (ssb[SS_IDX_SPRL])
);

// [SS-HOOK] adattatori ssbus dei registri Z80 (pattern Darius: blocco unico da 358 bit)
wire [357:0] z80m_ss_in, z80m_ss_out;  wire z80m_ss_wr;
wire [357:0] z80s_ss_in, z80s_ss_out;  wire z80s_ss_wr;

auto_save_adaptor #(.N_BITS(358), .SS_IDX(SS_IDX_Z80M)) u_ss_z80m (
	.clk(clk_sys), .ssbus(ssb[SS_IDX_Z80M]),
	.bits_in(z80m_ss_out), .bits_out(z80m_ss_in), .bits_wr(z80m_ss_wr)
);
auto_save_adaptor #(.N_BITS(358), .SS_IDX(SS_IDX_Z80SND)) u_ss_z80snd (
	.clk(clk_sys), .ssbus(ssb[SS_IDX_Z80SND]),
	.bits_in(z80s_ss_out), .bits_out(z80s_ss_in), .bits_wr(z80s_ss_wr)
);


///////////////////////   VIDEO   ///////////////////////////////

// Raster DANGAR (galivan.cpp: set_raw(XTAL(12M)/2, 384, 0, 256, 263, 16, 240)):
//   pixel clock 6 MHz, htotal 384, vtotal 263, visibile 256x224 (righe 16..239)
//   -> HSync 15.625 kHz, VSync 59.4106 Hz. ROT270 (verticale).
// La catena CRT sys-side e' parametrizzata sugli stessi numeri (VTOTAL 263,
// HTOTAL 384) e il conteggio righe di sys_top parte da 263.
wire HBlank, VBlank, HSync, VSync;
wire [7:0] video_r, video_g, video_b;

// Refresh rate (OSD status[22]): V_TOTAL 263 nativo o 260 a 60 Hz.
// Porch VERTICALI ricalcolati su V_TOTAL (pattern NightSlashers): area attiva
// FISSA (vcnt 16..239, 224 righe), VSync a posizione fissa subito dopo con
// front porch fisso, BACK PORCH che assorbe la differenza di V_TOTAL ->
// modeline sempre valida -> niente desync.
//   15625/263 = 59.4106 Hz (nativo)      15625/260 = 60.0962 Hz
// Coda dopo il sync: 263-251 = 12 righe nativo, 260-251 = 9 righe a 60 Hz.
// HSync resta 15625.0 Hz in entrambi i modi: si tocca solo il conteggio righe.
wire       mode_60hz = status[22];
wire [9:0] V_TOTAL   = mode_60hz ? 10'd260 : 10'd263;
wire [9:0] V_LAST    = V_TOTAL - 10'd1;

reg [9:0] hcnt, vcnt;
always @(posedge clk_sys) begin
	if (video_reset) begin
		hcnt <= 10'd0;
		vcnt <= 10'd0;
	end else if (ce_pix) begin
		if (hcnt == 10'd383) begin
			hcnt <= 10'd0;
			vcnt <= (vcnt >= V_LAST) ? 10'd0 : vcnt + 10'd1;
		end else hcnt <= hcnt + 10'd1;
	end
end
// Coordinate del pixel che il gioco sta calcolando in questa finestra, usate
// dal pause_overlay per sapere dove disegnare. dangar_video calcola il pixel
// (hcnt, vcnt) e lo presenta al ce_pix che chiude la finestra, quindi qui NON
// va nessun anticipo: l'overlay ha gia' il suo read-ahead interno di 1 px
// (pause_overlay.sv:115) per compensare la latenza della sua BRAM.
assign render_x = hcnt;
assign render_y = vcnt[8:0];
assign HBlank = ~(hcnt < 10'd256);
assign VBlank = ~((vcnt >= 10'd16) && (vcnt < 10'd240));
assign HSync  = (hcnt >= 10'd296) && (hcnt < 10'd328);
assign VSync  = (vcnt >= 10'd248) && (vcnt < 10'd251);

assign video_r = game_rgb[23:16];
assign video_g = game_rgb[15:8];
assign video_b = game_rgb[7:0];

assign CLK_VIDEO = clk_sys;

// ============================================================
// Screen rotation (TATE) - portato 1:1 da Raiden.sv:1824-1892
// ============================================================
// Dangar e' ROT270 (verticale) esattamente come Raiden, quindi la catena e' la
// stessa: screen_rotate snoopa VGA_* a CLK_VIDEO, la FIFO da 1024 entry assorbe
// i write, il ddr_mux arbitra fra il gioco (a) e il rotate (b).
// status[2:1]: 00=No rotate, 01=CCW (TATE), 10=CW. status[3]=Flip 180.
wire [1:0] rotate_sel = status[2:1];
wire rotate_en  = (rotate_sel != 2'd0);
wire rotate_ccw = (rotate_sel == 2'd1);
wire flip_180   = status[3];
wire video_rotated;

// VGA_SCALER deve restare 0 (assegnato in testa al file): il CRT analogico non
// deve MAI cambiare routing quando attivi il rotate. La rotazione HDMI la fa
// screen_rotate via framebuffer HPS, NON tramite VGA_SCALER. Legandolo a
// video_rotated, abilitare la rotazione dirotta anche l'uscita analogica.
// Per questo video_rotated resta volutamente inutilizzato.

// -- Pause overlay ---------------------------------------------------------
// Versione Raiden: ha rotate_en e ruota l'overlay CCW (gioco verticale), cosi'
// il logo resta diritto sia con rotate Off che On. Geometria gia' giusta per
// Dangar: il modulo e' scritto per un raster nativo 256x224 ruotato, che e'
// esattamente quello di Dangar.
wire [7:0] av_r, av_g, av_b;
pause_overlay u_pause_ovl (
	.clk         (clk_sys),
	.pause       (paused_safe),
	.clean       (clean_pause),
	.vblank      (VBlank),
	.rotate_en   (rotate_en),
	.render_x_in (render_x[8:0]),
	.render_y_in (render_y),
	.rgb_r_in    (video_r),
	.rgb_g_in    (video_g),
	.rgb_b_in    (video_b),
	.rgb_r_out   (av_r),
	.rgb_g_out   (av_g),
	.rgb_b_out   (av_b)
);

// -- CRT Adjust + V-Size: integrazione SYS-SIDE ----------------------------
// I due stadi NON stanno qui: vivono in sys/sys_top.v, sul solo ramo VGA
// analogico (fra scanlines e vga_osd), cosi' l'HDMI resta bit-identico mentre
// si regola il CRT. Il core decodifica solo l'OSD ed esporta i valori con le
// porte CRT_*. Riferimento: MiSTer_Discovery_Docs doc 17 (regole) e 18 (playbook).
//
// Regola 1.6: con lo scandoubler attivo il CE pixel raddoppia e la base del
// generatore di lettura non e' piu' valida -> si spegne tutto il gruppo.
//
// Su questo core l'unico scandoubler e' forced_scandoubler (MiSTer.ini): non
// c'e' video_mixer e non c'e' Scandoubler Fx. Fino al 2026-09-16 il gate
// guardava anche ~(|status[21:19]), cioe' l'opzione OSD "Scale" dell'integer
// scaling HDMI, e il CRT Adjust dell'uscita analogica si SPEGNEVA appena si
// sceglieva un integer scaling. Era un omonimo: la regola dice
// `scale || forced_scandoubler` dove `scale` e' la variabile dello Scandoubler
// Fx del template classico, non l'opzione "Scale". Lo Scale non tocca
// l'analogico — in video_freak entra solo in video_scale_int, che calcola
// l'aspetto per lo scaler HDMI; VGA_DE esce dal crop e CE_PIXEL non cambia.
// Trovato dall'utente. Doc 17, sezione 1bis.
wire crt_adj_on = status[112] & ~forced_scandoubler;

// H-Size: bidirezionale, complemento a due a 6 BIT. 0 = nativo; +1..+31 enlarge
// (read piu' lento); -1..-32 shrink. Passo = 1 ottavo di ciclo = 0.78%: la base
// del generatore sta in sys_top e vale (96/6)*8 = 128, cioe' il rapporto nativo.
//
// Sei bit invece dei cinque del template canonico (doc 17), su richiesta: prima
// la base era stata alzata a 148 per allargare l'immagine di default, ma quello
// era un ritocco fuori regola. Ora la base e' di nuovo quella nativa e la
// larghezza si recupera dall'OSD, con il doppio dei passi a disposizione.
// Lo status 67 era libero (verificato su tutti i range di status e di O[]).
reg  signed [5:0] hsize_s;
always @(posedge clk_sys) if (ce_pix) hsize_s <= crt_adj_on ? $signed(status[67:62]) : 6'sd0;

// H-Position: sposta il CONTENUTO, non il sync. La lista OSD ha 97 voci
// (0, +1..+48, -48..-1) e il menu salva l'INDICE: il wrap va fatto sulla
// LUNGHEZZA DELLA LISTA (97), non a 128. Col wrap a 128 la voce "-1" vale -32 px
// e l'immagine salta di 32 pixel al primo scatto (bug reale visto su HW).
reg  [6:0] hsize_hoff_d;
always @(posedge clk_sys) if (ce_pix) hsize_hoff_d <= crt_adj_on ? status[104:98] : 7'd0;
wire signed [8:0] hsize_hoffset = (hsize_hoff_d <= 7'd48)
	? $signed({2'b0, hsize_hoff_d})
	: $signed({2'b0, hsize_hoff_d}) - 9'sd97;

// V-Shift: signed +-32 righe, campionato a fine riga.
wire line_tick = ce_pix && (hcnt == 10'd383);
reg signed [5:0] osd_vga_vshift_d;
always @(posedge clk_sys) if (line_tick) osd_vga_vshift_d <= crt_adj_on ? $signed(status[61:56]) : 6'sd0;

// V-Size: un passo OSD = 3 righe; la negazione fa si' che "+" per l'utente =
// piu' alta. Il campo e' a complemento a due su 4 bit, quindi va esteso col
// segno (14 = -2, non +14).
reg signed [5:0] crt_vsize;
reg              crt_vsmode;
wire signed [5:0] crt_vsz_step = $signed({{2{status[116]}}, status[116:113]});
always @(posedge clk_sys) if (ce_pix) begin
	crt_vsize  <= crt_adj_on ? -(crt_vsz_step + (crt_vsz_step <<< 1)) : 6'sd0;
	crt_vsmode <= status[117];
end

assign CRT_ON     = crt_adj_on;
assign CRT_HSIZE  = hsize_s;
assign CRT_HPOS   = hsize_hoffset;
assign CRT_VSHIFT = osd_vga_vshift_d;
assign CRT_VSIZE  = crt_vsize;
assign CRT_VSMODE = crt_vsmode;
assign CRT_VBL    = VBlank;          // VBlank VERO nativo, MAI il blank combinato

// -- GAMMA CORRECTION (gamma_fast) -----------------------------------------
// Il core non usa video_mixer, quindi la gamma va agganciata a mano: gamma_bus
// era scollegata e la voce OSD non faceva nulla. gamma_fast prende gamma_bus
// come inout e lo decodifica da solo, ha tre LUT parallele e gia' DE in ingresso
// e in uscita. Sta sul flusso NATIVO: la regolazione CRT e' a valle, in sys_top,
// sul solo ramo analogico.
wire [23:0] vid_rgb_out;
wire        vid_hs_out, vid_vs_out, vid_de_out;
gamma_fast u_gamma (
	.clk_vid   (clk_sys),
	.ce_pix    (ce_pix),
	.gamma_bus (gamma_bus),
	.HSync     (HSync),
	.VSync     (VSync),
	.HBlank    (HBlank | VBlank),
	.VBlank    (1'b0),
	.DE        (~(HBlank | VBlank)),
	.RGB_in    ({av_r, av_g, av_b}),
	.HSync_out (vid_hs_out),
	.VSync_out (vid_vs_out),
	.HBlank_out(),
	.VBlank_out(),
	.DE_out    (vid_de_out),
	.RGB_out   (vid_rgb_out)
);

assign VGA_R    = vid_rgb_out[23:16];
assign VGA_G    = vid_rgb_out[15:8];
assign VGA_B    = vid_rgb_out[7:0];
assign VGA_HS   = vid_hs_out;
assign VGA_VS   = vid_vs_out;
assign CE_PIXEL = ce_pix;

// Aspect ratio: Original = 4:3. Quando ruota (TATE) swap ARX/ARY: la scena e'
// gia' ruotata dal framebuffer dell'HPS scaler -> da 4:3 landscape a 3:4 portrait.
wire [11:0] arx = (!ar) ? (rotate_en ? 12'd3 : 12'd4) : (ar - 1'd1);
wire [11:0] ary = (!ar) ? (rotate_en ? 12'd4 : 12'd3) : 12'd0;

// Integer scaling (Scale menu)
video_freak video_freak
(
	.CLK_VIDEO(clk_sys),
	.CE_PIXEL(ce_pix),
	.VGA_VS(VSync),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(VGA_DE),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),
	.VGA_DE_IN(vid_de_out),
	.ARX(arx),
	.ARY(ary),
	.CROP_SIZE(12'd0),
	.CROP_OFF(5'd0),
	.SCALE(status[21:19])   // 0=Normal 1=V-Int 2=Narrower 3=Wider 4=HV-Integer
);

// -- Rotate: screen_rotate -> FIFO -> ddr_if (client b del ddr_mux) ---------
wire [28:0] rot_addr;
wire [63:0] rot_data;
wire  [7:0] rot_be;
wire        rot_we;

screen_rotate u_screen_rotate
(
	.CLK_VIDEO     (clk_sys),
	.CE_PIXEL      (ce_pix),

	.VGA_R         (VGA_R),
	.VGA_G         (VGA_G),
	.VGA_B         (VGA_B),
	.VGA_HS        (VGA_HS),
	.VGA_VS        (VGA_VS),
	.VGA_DE        (VGA_DE),

	.rotate_ccw    (rotate_ccw),
	.no_rotate     (~rotate_en),
	.flip          (flip_180),
	.video_rotated (video_rotated),

	.FB_EN         (FB_EN),
	.FB_FORMAT     (FB_FORMAT),
	.FB_WIDTH      (FB_WIDTH),
	.FB_HEIGHT     (FB_HEIGHT),
	.FB_BASE       (FB_BASE),
	.FB_STRIDE     (FB_STRIDE),
	.FB_VBL        (FB_VBL),
	.FB_LL         (FB_LL),

	.DDRAM_CLK     (),
	.DDRAM_BUSY    (1'b0),         // la FIFO assorbe (pattern Taito F2)
	.DDRAM_BURSTCNT(),
	.DDRAM_ADDR    (rot_addr),
	.DDRAM_DIN     (rot_data),
	.DDRAM_BE      (rot_be),
	.DDRAM_WE      (rot_we),
	.DDRAM_RD      ()
);

raiden_rotate_fifo u_rot_fifo (
	.clk      (clk_sys),
	.rot_addr (rot_addr),
	.rot_data (rot_data),
	.rot_be   (rot_be),
	.rot_we   (rot_we),
	.ddr      (ddr_rot)
);


endmodule
