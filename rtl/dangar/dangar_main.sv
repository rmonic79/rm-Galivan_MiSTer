// SPDX-License-Identifier: GPL-3.0-or-later
/*  This file is part of rmGalivan_MiSTer.
    Author: Umberto Parisi (rmonic79)
*/

//============================================================================
//  Ufo Robo Dangar (Nichibutsu 1986, PCB Galivan GV-1412) — CPU principale
//
//  Z80B @ 6 MHz (clock enable ce_main), mappa di memoria `galivan_state::main_map`
//  (galivan.cpp:726-735) e I/O `galivan_state::io_map` (galivan.cpp:748-763).
//
//  Contiene: tv80s main, decode memoria + banking ROM, char RAM 2 KB write-only
//  con porta B per il renderer, RAM 8 KB 0xE000-0xFFFF (di cui i primi 256 byte
//  sono la sprite RAM), doppio buffer sprite copiato a inizio VBlank, registri
//  di I/O (gfxbank / scroll / layers / soundlatch / ack IRQ), input + DSW e la
//  costante 0x58 sulla porta 0xC0.
//
//  Clock unico `clk` (96 MHz) + clock enable. Nessun clock derivato.
//============================================================================

module dangar_main #(
	// [SS-HOOK] indici ssbus dei chunk (-1 = chunk assente)
	parameter SS_IDX_WRAM = -1,
	parameter SS_IDX_CRAM = -1,
	parameter SS_IDX_SPRB = -1,
	parameter SS_IDX_REGS = -1,
	parameter SS_IDX_SPRL = -1
)
(
	input             clk,
	input             reset,
	input             ce_main,      // 6 MHz enable (galivan.cpp:1169, XTAL 12/2)
	input             board_ninjemak,  // 0 = Galivan/Dangar/dangarj, 1 = Ninja Emaki
	input             board_youmab,    // bootleg Game Electronics: IMPLICA board_ninjemak
	// Licenza Tecfri: NON implica board_ninjemak. Il programma e' quello di
	// Ninja Emaki ricompilato per il decodificatore di I/O di Galivan (input
	// 0x00-0x04, uscite 0x40-0x47, banco ROM a 2 vie sul bit 7 della 0x40),
	// quindi qui dentro e' una Galivan a tutti gli effetti. Le uniche due cose
	// che prende da Ninja Emaki sono la spriteram da 512 byte e l'alias della
	// VRAM testo; il resto delle differenze e' tutto nel modulo video.
	input             board_ninjemat,
	input             pause,

	// Input gia' active-low come il PCB (galivan.cpp:879-906, IP_ACTIVE_LOW)
	input      [7:0]  p1,
	input      [7:0]  p2,
	input      [7:0]  sys,
	input      [7:0]  service,      // solo Ninja Emaki: porta 0x83 (galivan.cpp:784)
	input      [7:0]  dsw1,
	input      [7:0]  dsw2,

	// ROM programma: offset DENTRO la regione maincpu del core
	//   0x00000-0x0BFFF = ROM fissa 48 KB   (galivan.cpp:728)
	//   0x0C000-0x0FFFF = 2 banchi da 8 KB  (galivan.cpp:730, 1117-1119)
	// Il chiamante somma MAIN_BASE.
	output     [16:0] rom_addr,
	input      [7:0]  rom_data,
	output            rom_req,
	input             rom_ok,

	input             vblank,       // livello: il fronte di salita assevera l'IRQ
	// [SS-HOOK] impulso esteso dopo il load: rimette a riposo le macchine che
	// hanno stato TRANSITORIO non salvato (schema Raiden, Raiden_main_top.sv:110).
	// Senza, dopo un restore la macchina del fetch puo' restare a meta' di una
	// richiesta e la CPU latcha un byte che non c'entra.
	input             ss_cpu_reload,

	output     [7:0]  snd_latch,
	output            snd_latch_wr,

	output     [12:0] scroll_x,
	output     [12:0] scroll_y,
	// Su Ninja Emaki i layer non sono programmabili: screen_update disegna
	// sempre bg -> sprite -> testo (galivan.cpp:685-700) e l'unico controllo e'
	// il bit 4 di gfxbank che spegne lo sfondo. Qui si presenta la stessa terna
	// che presenterebbe Galivan per ottenere quell'ordine.
	output     [2:0]  layers,       // {porta42[7],porta42[6],porta42[5]}
	// Blitter NB1414M4 (solo Ninja Emaki). Sta QUI dentro perche' lavora sulla
	// char RAM, di cui condivide la porta A con la CPU: mentre copia la CPU e'
	// ferma, quindi non serve una terza porta sull'M10K.
	input             frame_tick,      // impulso a inizio frame
	output     [13:0] blit_rom_addr,   // ROM dati da 16 KB del blitter
	input       [7:0] blit_rom_data,
	output            blit_busy,       // alto mentre copia: ferma la CPU
	output            flip_screen,

	// Porta B char RAM (2 KB) per il renderer del layer testo
	// ROM da 8 KB della scheda figlia DG-3, letta dal chip NB1412M2.
	// Presente solo nel set `dangarj`: sugli altri resta a zero e il chip non
	// viene mai interrogato, perche' nessuno scrive su 0x80/0x81.
	output     [12:0] prot_addr,
	input      [7:0]  prot_data,

	input      [10:0] cram_addr_r,
	output     [7:0]  cram_data_r,

	// Porta B del BUFFER sprite (256 byte) per il renderer
	input      [8:0]  spr_addr_r,
	output     [7:0]  spr_data_r,
	input             spr_buffer_copy,   // impulso a inizio VBlank

	// savestate: porte auto_ss del tv80s esposte verso l'alto
	input      [357:0] ss_cpu_in,
	input              ss_cpu_wr,
	output     [357:0] ss_cpu_out,

	// [SS-HOOK] chunk di stato posseduti da questo modulo.
	// Le RAM passano da ss_ram_adaptor, che si interpone sulla porta di
	// scrittura ed e' trasparente quando lo ssbus non e' in accesso.
	ssbus_if.slave     ss_wram,      // 8 KB 0xE000-0xFFFF (spriteram inclusa)
	ssbus_if.slave     ss_cram,      // 2 KB char RAM
	ssbus_if.slave     ss_sprb,      // 256 B buffer sprite
	ssbus_if.slave     ss_regs,      // registri di controllo
	ssbus_if.slave     ss_sprl       // 256 B copia viva della sprite RAM
);

//============================================================================
// Segnali CPU
//============================================================================

wire [15:0] cpu_addr;
wire [7:0]  cpu_dout;
reg  [7:0]  cpu_din;
wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, halt_n, busak_n;

wire        cpu_cen;

//============================================================================
// Strobe di scrittura a impulso singolo (1 ciclo di clk)
//
// Con cen a 6 MHz il segnale wr_n resta basso per piu' cicli di clk e, per gli
// I/O (IOWait=1), per piu' di un tick di cen: usare il livello genererebbe
// scritture ripetute e impulsi di snd_latch_wr multipli. Si prende il fronte.
// Il dato su cpu_dout e' gia' stabile un ciclo prima che wr_n scenda.
//============================================================================

wire       mem_wr = ~mreq_n & ~wr_n;
wire       io_sel =  ~iorq_n & m1_n;        // m1_n alto: esclude il ciclo INTA
wire       io_wr  = io_sel & ~wr_n;
wire       io_rd  = io_sel & ~rd_n;

reg        mem_wr_d, io_wr_d;
always @(posedge clk) begin
	mem_wr_d <= mem_wr;
	io_wr_d  <= io_wr;
end

wire       mem_wr_stb = mem_wr & ~mem_wr_d;
wire       io_wr_stb  = io_wr  & ~io_wr_d;

//============================================================================
// Decode memoria (galivan.cpp:726-735)
//   0x0000-0xBFFF  R   ROM fissa
//   0xC000-0xDFFF  R   ROM bancata  (.bankr: le scritture 0xC000-0xD7FF si perdono)
//   0xD800-0xDFFF  W   char RAM 2 KB (SOLO scrittura: in lettura resta ROM bancata)
//   0xE000-0xE0FF  RW  sprite RAM 256 byte
//   0xE100-0xFFFF  RW  work RAM 0x1F00
// 0xE000-0xFFFF e' un blocco contiguo di 8 KB: la sprite RAM ne e' la finestra bassa.
//============================================================================

// La Tecfri ha la spriteram di Ninja Emaki pur avendo l'I/O di Galivan: i suoi
// riferimenti a $E100-$E1FF sono gli STESSI di ninjemak ($E100, $E101, $E114,
// $E17C, $E180, $E194, $E1D9, $E1DD, $E1E4), mentre su Galivan in quella
// finestra ci sono variabili sparse. E la sua regione sprite e' da 128 KB.
wire nj_spr   = board_ninjemak | board_ninjemat;

wire is_ram   = (cpu_addr[15:13] == 3'b111);          // 0xE000-0xFFFF
wire is_bank  = (cpu_addr[15:13] == 3'b110);          // 0xC000-0xDFFF
// 0xD800-0xDFFF su tutte le schede. Sulla Tecfri la VRAM testo risponde pero'
// a DUE indirizzi, $C800-$CFFF e $D800-$DFFF: il bit A12 non e' decodificato.
// Lo dimostra la GUI, che il programma disegna da due punti diversi sulle
// stesse celle — l'interprete di testo a $1900 scrive "        CREDIT  " a
// $C869 e la routine a $BE59 ci mette le cifre dei crediti a $D878/$D879, che
// sono le ultime due celle di quella stessa stringa. Senza l'alias meta' della
// GUI finirebbe nella finestra bancata, cioe' nel nulla.
wire is_cram  = (cpu_addr[15:11] == 5'b11011)
              | (board_ninjemat & (cpu_addr[15:13] == 3'b110) & cpu_addr[11]);
// 0xE000-0xE0FF su Galivan (galivan.cpp:732), 0xE000-0xE1FF su Ninja Emaki
// (galivan.cpp:741): la spriteram e' il doppio, 128 sprite invece di 64.
wire is_spr   = nj_spr ? (cpu_addr[15:9] == 7'b1110000)
                       : (cpu_addr[15:8] == 8'hE0);

// Bootleg: 0x8000-0xBFFF non e' piu' ROM fissa ma la SECONDA finestra bancata,
// quella della ROM extra da 32 KB (galivan.cpp:795). Sugli altri set resta ROM
// fissa, quindi il wire e' gia' spento dal bit di variante.
wire is_xbank = board_youmab & (cpu_addr[15:14] == 2'b10);   // 0x8000-0xBFFF

// NOTA sul bootleg: MAME gli aggiunge map(0xd800,0xd81f).nopw()
// (galivan.cpp:796) col commento "scrolling isn't here..", cioe' l'autore
// non sapeva cosa fossero quelle scritture e le ha zittite. Ma quel set e'
// MACHINE_NOT_WORKING: non e' una fonte.
// Sulla scheda vera il chip NB1414M4 e' stato TOLTO, quindi 0xD800-0xDFFF e'
// VRAM testo e basta, tutti e 2 KB, e quelle scritture sono l'interfaccia che
// il codice dei bootlegger disegna da solo. Zittirle faceva sparire l'inizio
// della GUI. Qui NON si filtra niente: la scrittura vale per tutte le schede.
wire cram_we  = mem_wr_stb & is_cram;                 // galivan.cpp:731
wire wram_we  = mem_wr_stb & is_ram;                  // galivan.cpp:733-734
wire spr_we   = mem_wr_stb & is_spr;

//============================================================================
// ROM programma + banking
//
// Banco: bit 7 della porta 0x40 (galivan.cpp:551-552). 2 banchi da 0x2000
// a partire da 0x10000 della regione MAME (galivan.cpp:1117-1119); nella mappa
// ROM del core quella finestra e' MAINBNK a offset 0x0C000.
//   offset banco = 0x0C000 + (bank << 13) + (A - 0xC000) = {3'b011, bank, A[12:0]}
//============================================================================

reg [1:0]  rom_bank;      // 1 bit su Galivan, 2 su Ninja Emaki
reg        xbank;         // bootleg: porta 0x82, 0xFF = banco 1, 0x00 = banco 0

// Finestra bancata: la BASE NON E' LA STESSA IN TUTTE LE MAPPE, dipende da
// quanto e' lunga la ROM fissa che la precede.
//   Galivan/Dangar e Ninja Emaki: fissa da 48 KB -> MAINBNK a 0x0C000
//   bootleg youmab:               fissa da 32 KB -> MAINBNK a 0x008000,
//                                 perche' 0x8000-0xBFFF non e' piu' ROM fissa
//                                 ma la finestra del banco extra
// (YB_MAINBNK_BASE vale 0x008000; il modulo non include le tabelle, quindi il
// valore e' scritto qui e va tenuto allineato a youmab_rom_regions.vh.)
// Cambia anche quanti banchi ci stanno: due su Galivan, QUATTRO su Ninja Emaki
// e sul bootleg (regione maincpu 0x18000). Su Galivan rom_bank vale
// {1'b0, bit7}, quindi l'indirizzo e' identico a prima.
wire [16:0] mainbnk_base = board_youmab ? 17'h08000 : 17'h0C000;

reg  [16:0] bank_base;
always @(posedge clk)
	bank_base <= mainbnk_base + {2'd0, rom_bank, 13'd0};

// Base del banco extra, registrata esattamente come bank_base: 2 banchi da
// 16 KB a partire da XBANK, che nella mappa del bootleg sta a 0x10000.
//   offset = 0x10000 + (xbank << 14) + (A - 0x8000)
reg  [16:0] xbank_base;
always @(posedge clk)
	xbank_base <= 17'h10000 + {2'd0, xbank, 14'd0};

wire [16:0] rom_addr_w = is_xbank ? (xbank_base | {3'd0, cpu_addr[13:0]})
                       : is_bank  ? (bank_base  | {4'd0, cpu_addr[12:0]})
                                  : {1'b0, cpu_addr};

// Lettura ROM: tutto 0x0000-0xDFFF (la char RAM non e' rileggibile, T4)
wire        rom_rd = ~mreq_n & ~rd_n & ~is_ram;

reg  [16:0] rom_addr_q;
reg  [7:0]  rom_data_q;
reg         rom_req_q;
reg         rom_hold;      // rom_data_q e' valido per rom_addr_q

wire        rom_hit  = rom_hold & (rom_addr_q == rom_addr_w);
wire        rom_wait = rom_rd & ~rom_hit;

// CONTRATTO con dangar_top: rom_ok e' l'ack della richiesta corrente, quindi
// deve essere BASSO finche' rom_req e' basso (o comunque nel ciclo in cui
// rom_req sale). Un rom_ok "sempre pronto" farebbe latchare il dato sbagliato.
always @(posedge clk) begin
	if (reset || ss_cpu_reload) begin
		rom_req_q  <= 1'b0;
		rom_hold   <= 1'b0;
		rom_addr_q <= 17'd0;
		rom_data_q <= 8'd0;
	end
	else if (rom_req_q) begin
		if (rom_ok) begin
			rom_data_q <= rom_data;
			rom_hold   <= 1'b1;
			rom_req_q  <= 1'b0;
		end
	end
	else if (rom_rd & ~rom_hit) begin
		rom_addr_q <= rom_addr_w;
		rom_hold   <= 1'b0;
		rom_req_q  <= 1'b1;
	end
end

assign rom_addr = rom_addr_q;
assign rom_req  = rom_req_q;

assign cpu_cen  = ce_main & ~pause & ~rom_wait;

//============================================================================
// Char RAM 2 KB — 0xD800-0xDFFF, WRITE ONLY dal lato CPU (galivan.cpp:730-731)
// Porta A: scrittura CPU. Porta B: lettura renderer (indirizzo registrato).
// videoram_w non trasforma il dato (galivan.cpp:535-539).
//============================================================================

reg [7:0] cram[0:2047];
reg [7:0] cram_q;      // porta B: renderer
reg [7:0] cram_qa;     // porta A: rilettura per il savestate

// [SS-HOOK] l'adaptor si interpone sulla porta di SCRITTURA: a ssbus fermo
// wren/addr/wdata passano identici, quindi in gioco normale non cambia nulla.
wire       cram_we_o;
wire [10:0] cram_addr_o;
wire [7:0]  cram_wdata_o;
ss_ram_adaptor #(.WIDTH(8), .WIDTHAD(11), .SS_IDX(SS_IDX_CRAM)) u_ss_cram (
	.clk(clk),
	.wren_in(cram_we), .addr_in(cpu_addr[10:0]), .wdata_in(cpu_dout),
	.wren_out(cram_we_o), .addr_out(cram_addr_o), .wdata_out(cram_wdata_o),
	.q_in(cram_qa),
	.ssbus(ss_cram)
);

// Porta A condivisa: la CPU (e il savestate) quando il blitter e' a riposo,
// il blitter quando lavora. Non si sovrappongono mai — `blit_busy` tiene ferma
// la CPU e il savestate gira a gioco in pausa.
wire [10:0] blit_va;
wire        blit_vwe;
wire  [7:0] blit_vdin;

wire        cram_we_mux   = blit_busy ? blit_vwe  : cram_we_o;
wire [10:0] cram_addr_mux = blit_busy ? blit_va   : cram_addr_o;
wire  [7:0] cram_wd_mux   = blit_busy ? blit_vdin : cram_wdata_o;

dangar_nb1414m4 u_blit
(
	.clk        (clk),
	.reset      (reset),
	.trig       (blit_trig_r),
	.frame_tick (frame_tick),
	.rom_addr   (blit_rom_addr),
	.rom_data   (blit_rom_data),
	.vram_addr  (blit_va),
	.vram_we    (blit_vwe),
	.vram_din   (blit_vdin),
	.vram_dout  (cram_qa),
	.busy       (blit_busy),
	.scroll_x   (blit_scroll_x),
	.scroll_y   (blit_scroll_y)
);

always @(posedge clk) begin
	if (cram_we_mux) cram[cram_addr_mux] <= cram_wd_mux;
	cram_qa <= cram[cram_addr_mux];
	cram_q  <= cram[cram_addr_r];
end

assign cram_data_r = cram_q;

//============================================================================
// Work RAM 8 KB — 0xE000-0xFFFF (sprite RAM inclusa nella finestra bassa)
// Porta singola: la CPU o legge o scrive, mai entrambe nello stesso ciclo.
//============================================================================

reg [7:0] wram[0:8191];
reg [7:0] wram_q;

// [SS-HOOK] stessa forma della char RAM: adaptor sulla porta di scrittura.
wire        wram_we_o;
wire [12:0] wram_addr_o;
wire [7:0]  wram_wdata_o;
ss_ram_adaptor #(.WIDTH(8), .WIDTHAD(13), .SS_IDX(SS_IDX_WRAM)) u_ss_wram (
	.clk(clk),
	.wren_in(wram_we), .addr_in(cpu_addr[12:0]), .wdata_in(cpu_dout),
	.wren_out(wram_we_o), .addr_out(wram_addr_o), .wdata_out(wram_wdata_o),
	.q_in(wram_q),
	.ssbus(ss_wram)
);

always @(posedge clk) begin
	if (wram_we_o) wram[wram_addr_o] <= wram_wdata_o;
	wram_q <= wram[wram_addr_o];
end

//============================================================================
// Sprite RAM viva (copia ombra dei 256 byte 0xE000-0xE0FF)
//
// Serve una seconda copia perche' il motore di buffering deve leggere la lista
// mentre la CPU continua ad accedere alla work RAM: replicare 256 byte costa
// meno di forzare Quartus a inferire una RAM 8 KB con due porte di lettura.
// Le due memorie ricevono esattamente le stesse scritture (spr_we ⊂ wram_we).
//============================================================================

reg [7:0] spr_live[0:511];   // 512 = il massimo (Ninja Emaki)
reg [7:0] spr_live_q;

// [SS-HOOK] va salvata anche questa, non basta il buffer. spr_buf e' cio' che il
// renderer legge ADESSO, spr_live e' cio' che verra' copiato al prossimo VBlank:
// senza, dopo un restore il primo buffering riverserebbe i 256 byte rimasti da
// prima del caricamento e si vedrebbe un fotogramma di sprite sbagliati.
// Le memorie sono SEMPRE da 512 byte, anche su Galivan che ne usa 256: la
// dimensione di un blocco savestate e' una costante di compilazione e non si
// puo' condizionare. Costa 512 byte di stato in piu' e nessun ALM.
wire       sprl_we_o;
wire [8:0] sprl_addr_o;
wire [7:0] sprl_wdata_o;
ss_ram_adaptor #(.WIDTH(8), .WIDTHAD(9), .SS_IDX(SS_IDX_SPRL)) u_ss_sprl (
	.clk(clk),
	.wren_in(spr_we), .addr_in(cpu_addr[8:0]), .wdata_in(cpu_dout),
	.wren_out(sprl_we_o), .addr_out(sprl_addr_o), .wdata_out(sprl_wdata_o),
	.q_in(spr_live_q),
	.ssbus(ss_sprl)
);

//============================================================================
// Doppio buffer sprite — BUFFERED_SPRITERAM8, copia sul fronte di salita del
// VBlank (galivan.cpp:1178, 1182). draw_sprites legge SOLO il buffer
// (galivan.cpp:618): nessuna porta di trigger DMA lato CPU.
// 256 byte a 96 MHz = 2.7 us, ampiamente dentro il VBlank (23 righe).
//============================================================================

reg [8:0] copy_cnt;
reg [8:0] copy_addr;
reg       copy_run;
reg       copy_we;
reg       sbc_d;

always @(posedge clk) begin
	sbc_d   <= spr_buffer_copy;
	copy_we <= 1'b0;
	if (reset || ss_cpu_reload) begin
		copy_run <= 1'b0;
		copy_cnt <= 9'd0;
	end
	else if (spr_buffer_copy & ~sbc_d) begin
		copy_run <= 1'b1;
		copy_cnt <= 9'd0;
	end
	else if (copy_run) begin
		copy_addr <= copy_cnt;
		copy_we   <= 1'b1;
		copy_cnt  <= copy_cnt + 9'd1;
		// 256 byte su Galivan, 512 su Ninja Emaki. Anche a 512 la copia dura
		// 5.3 us a 96 MHz, dentro le 23 righe di VBlank con larghissimo margine.
		if (copy_cnt == (nj_spr ? 9'h1FF : 9'h0FF)) copy_run <= 1'b0;
	end
end

// Porta A: scrittura CPU e rilettura per il savestate. Porta B: il motore di
// copia, che legge con copy_cnt.
reg [7:0] spr_live_qb;
always @(posedge clk) begin
	if (sprl_we_o) spr_live[sprl_addr_o] <= sprl_wdata_o;
	spr_live_q  <= spr_live[sprl_addr_o];
	spr_live_qb <= spr_live[copy_cnt];
end

reg [7:0] spr_buf[0:511];    // 512 = il massimo (Ninja Emaki)
reg [7:0] spr_buf_q;    // porta B: renderer
reg [7:0] spr_buf_qa;   // porta A: rilettura per il savestate

// [SS-HOOK] il buffer sprite va salvato: e' quello che il renderer legge, e al
// restore la copia da spr_live non c'e' ancora stata (arriva al vblank dopo).
wire       sprb_we_o;
wire [8:0] sprb_addr_o;
wire [7:0] sprb_wdata_o;
ss_ram_adaptor #(.WIDTH(8), .WIDTHAD(9), .SS_IDX(SS_IDX_SPRB)) u_ss_sprb (
	.clk(clk),
	.wren_in(copy_we), .addr_in(copy_addr), .wdata_in(spr_live_qb),
	.wren_out(sprb_we_o), .addr_out(sprb_addr_o), .wdata_out(sprb_wdata_o),
	.q_in(spr_buf_qa),
	.ssbus(ss_sprb)
);

always @(posedge clk) begin
	if (sprb_we_o) spr_buf[sprb_addr_o] <= sprb_wdata_o;
	spr_buf_qa <= spr_buf[sprb_addr_o];
	spr_buf_q  <= spr_buf[spr_addr_r];
end

assign spr_data_r = spr_buf_q;

//----------------------------------------------------------------------------
// Stato del bootleg Game Electronics.
//
// SCROLL SERIALE. Tolto il blitter, lo scroll arriva un BIT ALLA VOLTA: ogni
// scrittura su 0x84 infila il bit 7 del dato nella posizione corrente e avanza
// il contatore; la scrittura su 0x86 latcha i 23 bit raccolti e riazzera
// (galivan.cpp:820-841). scrolly sono i 10 bit bassi, scrollx i 13 alti.
//----------------------------------------------------------------------------
reg [22:0] shift_val;
reg [4:0]  shift_scroll;
reg [12:0] yb_scroll_x;
reg [9:0]  yb_scroll_y;

//----------------------------------------------------------------------------
// Porta 0x8A. Due cose diverse nello stesso byte:
//
//   bit 3    ONDA QUADRA. Il gioco conta i giri di un ciclo da 52 T-state
//            fra due transizioni e pretende fra 240 e 271 iterazioni. A 6 MHz
//            sono 2,080-2,349 ms di semionda; il centro e' 2,219 ms, cioe'
//            212.992 cicli di clk_sys a 96 MHz. La tolleranza e' del +-6%:
//            non serve un valore esatto, questo sta in mezzo.
//            (analisi in docs/YOUMAB_PROTEZIONE.md, cap. 1)
//
//   bit 1-2  ENTROPIA. Il gioco si semina da solo con LD A,R — un valore che
//            NON puo' prevedere — scrive il seme su 0x81 e poi ACCUMULA i due
//            bit che rientrano, senza confrontarli con niente. Non e' un
//            controllo: e' una sorgente di casualita'. Va bene qualunque cosa,
//            quindi un LFSR libero, mescolato col seme scritto su 0x81.
//            (cap. 5 dello stesso documento)
//
// Entrambi i pezzi sono REGISTRI: il valore letto e' una pura concatenazione
// di flip-flop, non aggiunge un filo di logica alla catena che porta al bus
// dati della CPU — la stessa ragione per cui l'NB1412M2 ha l'uscita registrata.
//----------------------------------------------------------------------------
localparam [17:0] YB_SQ_HALF = 18'd212991;   // 212.992 cicli = 2,219 ms

reg [17:0] sq_cnt;
reg        sq_lvl;
reg  [7:0] lfsr;

always @(posedge clk) begin
	if (reset) begin
		sq_cnt <= 18'd0;
		sq_lvl <= 1'b0;
		lfsr   <= 8'hA5;            // qualunque valore non nullo
	end
	else begin
		if (sq_cnt == YB_SQ_HALF) begin
			sq_cnt <= 18'd0;
			sq_lvl <= ~sq_lvl;
		end
		else sq_cnt <= sq_cnt + 18'd1;

		// LFSR a 8 bit, polinomio x^8+x^6+x^5+x^4+1: gira libero, il gioco lo
		// campiona in momenti che non controlla.
		lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};

		// il seme scritto su 0x81 si mescola dentro (galivan.cpp:814-817)
		if (io_wr_stb & board_youmab & (cpu_addr[7:0] == 8'h81))
			lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]} ^ cpu_dout;
	end
end

wire [7:0] yb_8a = {4'd0, sq_lvl, lfsr[1:0], 1'b0};

//============================================================================
// I/O — map.global_mask(0xff): si decodificano SOLO A0-A7 (galivan.cpp:750).
// Lo Z80 mette B (o A) su A8-A15 durante IN/OUT: decodificare 16 bit farebbe
// sparire scritture di scroll e sound in modo intermittente (T5).
//============================================================================

reg [7:0] io_dout;

// Ninja Emaki ha una io_map TUTTA SUA (galivan.cpp:778-789), non un'aggiunta:
// gli ingressi stanno su 0x80-0x85 invece che su 0x00-0x04, e c'e' una porta
// SERVICE che su Galivan non esiste. In particolare 0x80/0x81 sono P1/P2, cioe'
// le stesse due porte su cui `dangarj` ha il chip NB1412M2: e' questo il motivo
// per cui serve il bit di variante e non bastano porte additive.
//
// TIMING: UNA sola case a 9 bit, non due case piu' un mux. Cosi' la profondita'
// resta quella di prima con un bit di decodifica in piu'; due case in parallelo
// con una scelta a valle aggiungerebbero un livello sul percorso combinatorio
// che arriva al bus dati della CPU.
always @(*) begin
	casez ({board_youmab, board_ninjemak, cpu_addr[7:0]})
		// ---- Galivan / Dangar / dangarj (galivan.cpp:748-763) ----
		10'b00_00000000: io_dout = p1;            // galivan.cpp:751
		10'b00_00000001: io_dout = p2;            // galivan.cpp:752
		10'b00_00000010: io_dout = sys;           // galivan.cpp:753
		10'b00_00000011: io_dout = dsw1;          // galivan.cpp:754
		10'b00_00000100: io_dout = dsw2;          // galivan.cpp:755
		// NB1412M2, solo `dangarj` (galivan.cpp:766-770): additiva, gli altri
		// set di questo gruppo su 0x80 non leggono mai.
		10'b00_10000000: io_dout = prot_dout;
		10'b00_11000000: io_dout = 8'h58;         // COSTANTE: se differisce dangar si resetta
		                                        // (galivan.cpp:713-717, 762)
		// ---- Ninja Emaki (galivan.cpp:778-789) ----
		10'b?1_10000000: io_dout = p1;
		10'b?1_10000001: io_dout = p2;
		10'b?1_10000010: io_dout = sys;
		10'b?1_10000011: io_dout = service;       // porta che Galivan non ha
		10'b?1_10000100: io_dout = dsw1;
		10'b?1_10000101: io_dout = dsw2;
		// ---- bootleg Game Electronics (galivan.cpp:843-852) ----
		// 0x8A: onda quadra + entropia, gia' tutto in registri (vedi sopra).
		10'b11_10001010: io_dout = yb_8a;
		// 0x00: DIVERGENZA VOLUTA DA MAME. La' la porta non e' mappata e legge
		// 0xFF; il gioco fa AND 0x18 e salta su uno dei quattro bersagli
		// calcolati, e 0xFF da' il ramo sbagliato — e' la causa del
		// "player is invincible" annotato nel driver (galivan.cpp:1922).
		// Il ramo giusto e' quello con i bit 3 e 4 A ZERO: lo si dimostra dal
		// percorso in cui il flag a $FFF6 satura a 0x23 e il salto si calcola
		// da quella costante senza piu' leggere la porta, dando $DB39 —
		// l'unico bersaglio che il gioco esegue di sicuro, quindi l'unico
		// valido. (dimostrazione in docs/YOUMAB_PROTEZIONE.md, cap. 4)
		10'b11_00000000: io_dout = 8'h00;
		default:       io_dout = 8'hFF;         // porte non mappate: scelta del core
	endcase
end

//============================================================================
// NB1412M2 — protezione del set `dangarj` (scheda figlia DG-3)
//
// Due porte AGGIUNTE a quelle di Galivan, non sostituite: la dangarj_io_map di
// MAME chiama io_map(map) e poi mappa 0x80/0x81 (galivan.cpp:766-770). Gli
// altri set su quelle porte non scrivono mai, quindi il chip si puo' lasciare
// sempre istanziato senza nessun bit di variante.
//============================================================================

wire [7:0] prot_dout;

dangar_nb1412m2 u_prot
(
	.clk      (clk),
	.reset    (reset),
	.cmd_wr   (io_wr_stb & (cpu_addr[7:0] == 8'h81)),
	.dat_wr   (io_wr_stb & (cpu_addr[7:0] == 8'h80)),
	.din      (cpu_dout),
	.dout     (prot_dout),
	.rom_addr (prot_addr),
	.rom_data (prot_data)
);

//============================================================================
// Registri di scrittura I/O
//============================================================================

reg [7:0] scrollx_lo, scrollx_hi;   // porte 0x41 / 0x42 (galivan.cpp:593-600)
reg [7:0] scrolly_lo, scrolly_hi;   // porte 0x43 / 0x44 (galivan.cpp:603-605)
reg [2:0] layers_r;                 // m_layers = data & 0xe0 (galivan.cpp:597)
reg       flip_r;                   // porta 0x40 bit 2 (galivan.cpp:548-549)
reg       bg_disable;               // solo Ninja Emaki: gfxbank bit 4 (galivan.cpp:573)
reg       blit_trig_r;              // solo Ninja Emaki: impulso su 0x86
wire [12:0] blit_scroll_x, blit_scroll_y;   // prodotti dal blitter
// TIMING: la terna dei layer esce REGISTRATA. Su Ninja Emaki non e'
// programmabile — screen_update disegna sempre bg, sprite, testo e l'unico
// controllo e' bg_disable — quindi si presenta la combinazione equivalente:
// bit2 (testo spento) = 0, bit1 (bg spento) = bg_disable, bit0 (ordine) = 0
// cioe' sprite prima, testo sopra.
reg [2:0] layers_eff;
always @(posedge clk)
	layers_eff <= board_ninjemak ? {1'b0, bg_disable, 1'b0} : layers_r;
reg [7:0] snd_latch_r;
reg       snd_latch_wr_r;
reg       irq_lvl;
reg       vbl_d;

always @(posedge clk) begin
	snd_latch_wr_r <= 1'b0;
	blit_trig_r    <= 1'b0;

	if (reset) begin
		// machine_reset: layers e scroll a 0 (galivan.cpp:1148-1155).
		// Il banco ROM in MAME NON viene azzerato dal reset a caldo
		// (set_entry(0) sta solo in machine_start, galivan.cpp:1119): qui lo
		// azzeriamo comunque, il latch sul PCB e' presumibilmente resettato.
		scrollx_lo  <= 8'd0;
		scrollx_hi  <= 8'd0;
		scrolly_lo  <= 8'd0;
		scrolly_hi  <= 8'd0;
		layers_r    <= 3'd0;
		flip_r      <= 1'b0;
		rom_bank    <= 2'd0;
		xbank       <= 1'b0;
		shift_val   <= 23'd0;
		shift_scroll<= 5'd0;
		yb_scroll_x <= 13'd0;
		yb_scroll_y <= 10'd0;
		snd_latch_r <= 8'd0;
		irq_lvl     <= 1'b0;
		vbl_d       <= 1'b0;
	end
	else begin
		vbl_d <= vblank;

		if (io_wr_stb) begin
			casez ({board_youmab, board_ninjemak, cpu_addr[7:0]})
				// ---- Galivan / Dangar / dangarj ----
				// gfxbank_w (galivan.cpp:542-555). bit0/bit1 = coin counter:
				// non modellati (nessuna porta richiesta). bit 3-6 mai letti:
				// verificato nel driver, usa SOLO 0,1,2 e 7.
				// Sulla Tecfri il banco e' a QUATTRO vie come su Ninja Emaki,
				// ma con i due bit SCAMBIATI: bit 6 alto, bit 7 basso. Non e'
				// un'ipotesi, si legge dai chiamanti di $1887, che e' l'unico
				// punto da cui ninjemat scrive la porta 0x40 durante il gioco.
				// Quella routine mette il bit 6 dove ninjemak mette il bit 7:
				//
				//   chiamante   ninjemat -> bit(7,6)   ninjemak       banco
				//   $00         (0,0)                  AND $3F          0
				//   $40         (1,0)                  OR  $40          1
				//   $80         (0,1)                  OR  $80          2
				//   $C0         (1,1)                  OR  $C0          3
				//
				// I quattro chiamanti combaciano uno a uno con quelli di
				// ninjemak agli stessi indirizzi ($0A9B e $0B04 identici), e i
				// banchi che ne escono tornano col contenuto: 0 e 1 sono la
				// mappa delle collisioni col terreno, 2 e 3 il codice — e la
				// ROM di ninjemat, `8.e16`, e' proprio i banchi 2 e 3 di
				// ninjemak (85% e 40% di byte uguali; a $CD00 in banco 3 c'e'
				// la stessa routine che ninjemak ha a $CF47).
				// Col banco a un bit solo i due percorsi di CODICE cadono
				// giusti per caso, ma la collisione legge il codice invece del
				// terreno: il personaggio sbatte contro ostacoli inesistenti.
				10'b00_01000000: begin
					flip_r   <= cpu_dout[2];
					rom_bank <= board_ninjemat ? {cpu_dout[6], cpu_dout[7]}
					                           : {1'b0, cpu_dout[7]};
				end

				// ---- Ninja Emaki: gfxbank_w su 0x80 (galivan.cpp:557-583) ----
				// Stessi bit 0,1 coin e 2 flip, ma in piu' il bit 4 spegne lo
				// sfondo e il banco ROM e' a DUE bit (6,7): la regione maincpu
				// e' 0x18000, quattro banchi invece di due. Onorare questi bit
				// anche su Galivan e' proprio cio' che romperebbe gli altri set.
				10'b?1_10000000: begin
					flip_r     <= cpu_dout[2];
					bg_disable <= cpu_dout[4];
					rom_bank   <= cpu_dout[7:6];
				end

				// scrollx_w offset 0: solo scroll X basso (galivan.cpp:599)
				10'b00_01000001: scrollx_lo <= cpu_dout;

				// scrollx_w offset 1: layers = data & 0xe0 E scrollx[1] = data
				// (galivan.cpp:595-599). I layer non sono separabili dallo
				// scroll alto: ogni scrittura riassegna entrambi (T10).
				10'b00_01000010: begin
					scrollx_hi <= cpu_dout;
					layers_r   <= cpu_dout[7:5];
				end

				10'b00_01000011: scrolly_lo <= cpu_dout;   // galivan.cpp:603-605
				10'b00_01000100: scrolly_hi <= cpu_dout;   // galivan.cpp:603-605

				// sound_command_w: il latch NON contiene il byte scritto
				// (galivan.cpp:702-705). bit7 scartato, shift a sinistra, bit0=1.
				// Galivan 0x45, Ninja Emaki 0x85 (galivan.cpp:786): due rami
				// espliciti, NON un pattern con i don't-care — 0x45 e 0x85
				// differiscono nei bit 6 e 7 e una maschera comune prenderebbe
				// anche 0xC5, che non e' mappata.
				10'b00_01000101,
				10'b?1_10000101: begin
					snd_latch_r    <= {cpu_dout[6:0], 1'b1};
					snd_latch_wr_r <= 1'b1;
				end

				// Ninja Emaki: trigger del blitter NB1414M4 (galivan.cpp:787).
				// Su Galivan quell'indirizzo non esiste.
				10'b01_10000110: blit_trig_r <= 1'b1;

				// ---- bootleg Game Electronics (galivan.cpp:843-852) ----
				// 0x82: banco della ROM extra. Solo 0xFF e 0x00 sono valori
				// buoni; su qualunque altro MAME stampa un avviso e non tocca
				// il banco (galivan.cpp:799-807), qui si fa lo stesso.
				10'b11_10000010: begin
					if (cpu_dout == 8'hFF)      xbank <= 1'b1;
					else if (cpu_dout == 8'h00) xbank <= 1'b0;
				end

				// 0x84: un bit alla volta dentro il registro a scorrimento.
				// Il contatore e' lasciato libero di avanzare come in MAME; la
				// scrittura e' limitata ai 23 bit utili perche' in RTL un
				// indice fuori range non e' "non succede niente per caso".
				10'b11_10000100: begin
					if (shift_scroll < 5'd23) shift_val[shift_scroll] <= cpu_dout[7];
					shift_scroll <= shift_scroll + 5'd1;
				end

				// 0x86: latch. Sul bootleg NON e' il trigger del blitter.
				10'b11_10000110: begin
					yb_scroll_y  <= shift_val[9:0];
					yb_scroll_x  <= shift_val[22:10];
					shift_val    <= 23'd0;
					shift_scroll <= 5'd0;
				end

				// 0x81: il seme entra nell'LFSR, gestito nel suo blocco.
				// 0x46 non mappata: la riga nopw e' commentata (galivan.cpp:760)

				default: ;
			endcase
		end

		// [SS-HOOK] restore: ricarica del blocco registri. Ha priorita' sulle
		// scritture I/O dello stesso ciclo perche' avviene a CPU ferma.
		if (ss_regs_ld) begin
			{scrollx_lo, scrollx_hi, scrolly_lo, scrolly_hi,
			 layers_r, flip_r, bg_disable, rom_bank, snd_latch_r, irq_lvl} <= ss_regs_out;
		end

		// IRQ main: LIVELLO asserito sul fronte di salita del VBlank
		// (irq0_line_assert, galivan.cpp:1170), cancellato SOLO dalla scrittura
		// sulla porta 0x47, dato ignorato (galivan.cpp:761). T2.
		if (vblank & ~vbl_d)
			irq_lvl <= 1'b1;
		else if (io_wr_stb & (cpu_addr[7:0] == (board_ninjemak ? 8'h87 : 8'h47)))
			irq_lvl <= 1'b0;
	end
end

// [SS-HOOK] registri di controllo in un chunk solo: scroll, layer, flip, banco,
// soundlatch e stato dell'IRQ. Senza questi, dopo un restore lo schermo scorre
// dal punto sbagliato, i layer possono essere spenti e la CPU perde l'IRQ
// pendente. auto_save_adaptor carica il blocco intero su bits_wr.
wire [47:0] ss_regs_out;
wire        ss_regs_ld;
auto_save_adaptor #(.N_BITS(48), .SS_IDX(SS_IDX_REGS)) u_ss_regs (
	.clk(clk), .ssbus(ss_regs),
	.bits_in ({scrollx_lo, scrollx_hi, scrolly_lo, scrolly_hi,
	           layers_r, flip_r, bg_disable, rom_bank, snd_latch_r, irq_lvl}),
	.bits_out(ss_regs_out),
	.bits_wr (ss_regs_ld)
);

// scroll a 11 bit: scroll[0] + 256*(scroll[1] & 0x07) (galivan.cpp:655-656)
// Su Galivan lo scroll sta nelle porte 0x41-0x44 (galivan.cpp:593-605) ed e' a
// 11 bit. Su Ninja Emaki quelle porte NON esistono: lo scroll lo latcha il
// blitter NB1414M4 dalla VRAM testo (galivan.cpp:343-345) e arriva da fuori a
// 13 bit, quanti ne servono per una tilemap larga 512 tile.
// Sul bootleg il blitter non c'e': lo scroll e' quello latchato dal registro
// a scorrimento seriale delle porte 0x84/0x86.
assign scroll_x     = board_youmab   ? yb_scroll_x
                    : board_ninjemak ? blit_scroll_x : {2'd0, scrollx_hi[2:0], scrollx_lo};
assign scroll_y     = board_youmab   ? {3'd0, yb_scroll_y}
                    : board_ninjemak ? blit_scroll_y : {2'd0, scrolly_hi[2:0], scrolly_lo};
assign layers       = layers_eff;       // [2]=testo OFF, [1]=bg OFF, [0]=priorita'
assign flip_screen  = flip_r;
assign snd_latch    = snd_latch_r;
assign snd_latch_wr = snd_latch_wr_r;

//============================================================================
// Bus dati verso la CPU
//============================================================================

always @(*) begin
	if (~iorq_n & ~m1_n)
		cpu_din = 8'hFF;          // ciclo INTA: 0xFF = RST 38h, identico a IM1
	else if (io_sel)
		cpu_din = io_dout;
	else if (is_ram)
		cpu_din = wram_q;
	else
		cpu_din = rom_data_q;     // 0x0000-0xDFFF: ROM fissa o bancata (T4)
end

//============================================================================
// Z80 main
//============================================================================

tv80s u_cpu
(
	.reset_n    ( ~reset       ),
	.clk        ( clk          ),
	.cen        ( cpu_cen      ),
	.wait_n     ( 1'b1         ),
	.int_n      ( ~irq_lvl     ),
	.nmi_n      ( 1'b1         ),   // nessun NMI in tutto il driver
	.busrq_n    ( 1'b1         ),
	.m1_n       ( m1_n         ),
	.mreq_n     ( mreq_n       ),
	.iorq_n     ( iorq_n       ),
	.rd_n       ( rd_n         ),
	.wr_n       ( wr_n         ),
	.rfsh_n     ( rfsh_n       ),
	.halt_n     ( halt_n       ),
	.busak_n    ( busak_n      ),
	.A          ( cpu_addr     ),
	.di         ( cpu_din      ),
	.dout       ( cpu_dout     ),
	.auto_ss_in ( ss_cpu_in    ),
	.auto_ss_wr ( ss_cpu_wr    ),
	.auto_ss_out( ss_cpu_out   )
);

endmodule
