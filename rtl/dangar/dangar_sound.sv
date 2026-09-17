// SPDX-License-Identifier: GPL-3.0-or-later
/*  This file is part of rmGalivan_MiSTer.
    Author: Umberto Parisi (rmonic79)

    dangar_sound.sv — sotto-sistema audio di Ufo Robo Dangar (hardware Galivan GV-1412).

    Contenuto, tutto riferito a reference/galivan.cpp:

      - Z80 sound (tv80s) a 4 MHz  ................ galivan.cpp:1174  Z80 XTAL(8'000'000)/2
      - RAM 2 KB a 0xC000-0xC7FF  ................. galivan.cpp:854-858
      - ROM 48 KB a 0x0000-0xBFFF (esterna)  ...... galivan.cpp:856
      - IRQ periodico 8MHz/2/512 = 7812.5 Hz  ..... galivan.cpp:1177
      - soundlatch con DUE porte di lettura  ...... galivan.cpp:866-867
      - YM3526 (jtopl) clock 4 MHz  ............... galivan.cpp:1222 + :115
      - due DAC 8 bit R2R  ........................ galivan.cpp:1225-1226
      - mix ym 0.4922 / dac1 0.2095 / dac2 0.2983 . galivan.cpp:1208

    PUNTI CHE SI SBAGLIANO SEMPRE, messi qui in alto:

    1) L'UNICA sorgente di interrupt e' il timer periodico a 7812.5 Hz.
       Il YM3526 NON ha filo di IRQ verso la CPU sound (galivan.cpp:1222: nessun
       set_irq_handler) e il soundlatch NON genera interrupt (galivan.cpp:1184:
       GENERIC_LATCH_8 senza data_pending callback). Il programma fa POLLING della
       porta 0x06. Quindi irq_n della CPU e' pilotato SOLO dal divisore.

    2) Il YM3526 non ha porta di LETTURA in questo hardware: la sound_io_map mappa
       0x00-0x01 in sola scrittura (galivan.cpp:863). Il registro di stato non e'
       leggibile, quindi dout di jtopl e' scollegato e la CPU non puo' fare polling
       del busy: le attese le fa contando cicli.

    3) I DAC sono UNSIGNED (vedi blocco "CONVENZIONE DAC" piu' sotto).

    Interfaccia ROM: rom_addr/rom_data con handshake rom_req/rom_ok. In questo core
    la ROM sound sta in BRAM dentro dangar_mem (porta snd_addr/snd_data, latenza 1
    clk, sempre valida): li' rom_ok si lega a 1'b1 e rom_req resta scollegato. La
    logica di attesa qui sotto e' comunque corretta anche in quel caso, perche'
    pretende UN clk di indirizzo stabile prima di accettare rom_ok — che e' esatta-
    mente la latenza della BRAM.
*/

`timescale 1ns / 1ps

module dangar_sound #(
	// Se 1 il modulo applica lui la trasformazione del comando sonoro
	//   latch = ((data & 0x7f) << 1) | 1        (galivan.cpp:702, sound_command_w)
	// Se il TOP la applica gia' sul dato scritto in IO 0x45, mettere 0: NON deve
	// essere fatta due volte. Il bit0 sempre a 1 e' cio' che permette al programma
	// sound di distinguere "comando presente" da "latch azzerato" (=0x00).
	parameter LATCH_XFORM  = 1,
	// [SS-HOOK] indici ssbus (-1 = chunk assente)
	parameter SS_IDX_SRAM  = -1,
	parameter SS_IDX_YMSH  = -1,
	parameter SS_IDX_SGLUE = -1
)
(
	input                    clk,        // 96 MHz, clock unico del core
	input                    reset,      // attivo alto, sincrono
	input                    ce_snd,     // clock enable 4 MHz: Z80 sound  (galivan.cpp:1174)
	input                    ce_ym,      // clock enable 4 MHz: YM3526     (galivan.cpp:1222)

	// ---- soundlatch scritto dalla CPU main (IO 0x45, galivan.cpp:762) ----
	input              [7:0] latch_data,
	input                    latch_wr,

	// ---- ROM del programma sound, 0x0000-0xBFFF (galivan.cpp:856) ----
	output            [15:0] rom_addr,
	input              [7:0] rom_data,
	output                   rom_req,
	input                    rom_ok,

	// ---- uscita audio, mono duplicato (galivan.cpp:1186 SPEAKER front_center) ----
	output signed     [15:0] audio_l,
	output signed     [15:0] audio_r,

	// ---- savestate della sola CPU (tv80 auto_ss) ----
	input            [357:0] ss_cpu_in,
	input                    ss_cpu_wr,
	output           [357:0] ss_cpu_out,

	// [SS-HOOK] chunk di stato del sotto-sistema audio (schema di Raiden,
	// Raiden_audio_z80.sv:106-109). L'ORDINE DEGLI INDICI CONTA: ss_sglue deve
	// essere l'ULTIMO, perche' il suo commit fa da trigger al replay del chip e
	// a quel punto la shadow dei registri deve essere gia' stata ripristinata.
	ssbus_if.slave           ss_sram,    // RAM 2 KB del Z80 sound
	ssbus_if.slave           ss_ymsh,    // shadow dei 256 registri del YM3526
	ssbus_if.slave           ss_sglue    // soundlatch, IRQ, DAC, address latch
);

// =====================================================================
// Z80 sound
// =====================================================================
wire [15:0] cpu_a;
wire  [7:0] cpu_dout;
reg   [7:0] cpu_din;
wire        cpu_m1_n, cpu_mreq_n, cpu_iorq_n, cpu_rd_n, cpu_wr_n, cpu_rfsh_n;
wire        cpu_halt_n, cpu_busak_n;
wire        cpu_cen;
wire        cpu_int_n;

tv80s u_cpu
(
	.reset_n    ( ~reset      ),
	.clk        ( clk         ),
	.cen        ( cpu_cen     ),
	.wait_n     ( 1'b1        ),   // l'attesa la facciamo togliendo cen, non con WAIT
	.int_n      ( cpu_int_n   ),
	.nmi_n      ( 1'b1        ),   // nessun NMI su questo hardware (galivan.cpp:1174-1177)
	.busrq_n    ( 1'b1        ),
	.m1_n       ( cpu_m1_n    ),
	.mreq_n     ( cpu_mreq_n  ),
	.iorq_n     ( cpu_iorq_n  ),
	.rd_n       ( cpu_rd_n    ),
	.wr_n       ( cpu_wr_n    ),
	.rfsh_n     ( cpu_rfsh_n  ),
	.halt_n     ( cpu_halt_n  ),
	.busak_n    ( cpu_busak_n ),
	.A          ( cpu_a       ),
	.di         ( cpu_din     ),
	.dout       ( cpu_dout    ),
	.auto_ss_in ( ss_cpu_in   ),
	.auto_ss_wr ( ss_cpu_wr   ),
	.auto_ss_out( ss_cpu_out  )
);

// =====================================================================
// Decodifica bus
//   memoria : 0x0000-0xBFFF ROM, 0xC000-0xC7FF RAM 2 KB   (galivan.cpp:856-857)
//   io      : global_mask(0xff) -> contano solo A[7:0]    (galivan.cpp:862)
// =====================================================================
wire mem_cyc = ~cpu_mreq_n & cpu_rfsh_n;                 // il refresh non e' un accesso
wire rom_cs  = mem_cyc & ~cpu_rd_n & (cpu_a[15:14] != 2'b11);
wire ram_cs  = mem_cyc & (cpu_a[15:11] == 5'b11000);     // 0xC000-0xC7FF
wire ram_we  = ram_cs  & ~cpu_wr_n;

wire int_ack = ~cpu_m1_n & ~cpu_iorq_n;                  // ciclo di acknowledge interrupt
wire io_rd   = ~cpu_iorq_n & cpu_m1_n & ~cpu_rd_n;
wire io_wr   = ~cpu_iorq_n & cpu_m1_n & ~cpu_wr_n;

// strobe larghi 1 clk: gli accessi IO durano decine di clk a 96 MHz e le
// periferiche (jtopl, latch dei DAC, clear del soundlatch) vanno colpite UNA volta.
reg io_rd_d, io_wr_d, ram_we_d;
always @(posedge clk) begin
	io_rd_d  <= io_rd;
	io_wr_d  <= io_wr;
	ram_we_d <= ram_we;
end
wire io_rd_stb  = io_rd  & ~io_rd_d;
wire io_wr_stb  = io_wr  & ~io_wr_d;
wire ram_we_stb = ram_we & ~ram_we_d;

// =====================================================================
// ROM esterna + attesa
//
// rom_req resta alto per tutto il ciclo di lettura; si accetta rom_ok solo se
// l'indirizzo e' gia' stabile da un clk, altrimenti un rom_ok rimasto alto dalla
// lettura PRECEDENTE farebbe campionare il dato vecchio. Il costo e' 1 clk (10 ns)
// su una finestra di 24 clk fra due impulsi di ce_snd: nessun ce_snd viene mai
// perso, quindi la CPU non rallenta.
// =====================================================================
assign rom_addr = cpu_a;
assign rom_req  = rom_cs;

reg [15:0] rom_addr_d;
reg        rom_req_d;
always @(posedge clk) begin
	rom_addr_d <= rom_addr;
	rom_req_d  <= rom_req;
end
wire rom_stable = rom_req_d & (rom_addr_d == rom_addr);
wire rom_wait   = rom_req & ~(rom_ok & rom_stable);

// Durante il replay dei registri il Z80 sound resta fermo: il bus del chip ce
// l'ha la macchina di ripristino. (rp_active e' dichiarato qui perche' serve
// gia' a questa riga; la macchina che lo pilota sta piu' sotto, col chip.)
reg rp_active;
assign cpu_cen = ce_snd & ~rom_wait & ~rp_active;

// =====================================================================
// RAM 2 KB (galivan.cpp:857). Indirizzo di lettura registrato dentro il blocco
// clockato: e' l'inferenza standard di M10K, niente mux combinatorio sull'indice.
// =====================================================================
reg [7:0] ram[0:2047];
reg [7:0] ram_q;

// [SS-HOOK] adaptor sulla porta di scrittura: a ssbus fermo e' trasparente.
wire        sram_we_o;
wire [10:0] sram_addr_o;
wire [7:0]  sram_wdata_o;
ss_ram_adaptor #(.WIDTH(8), .WIDTHAD(11), .SS_IDX(SS_IDX_SRAM)) u_ss_sram (
	.clk(clk),
	.wren_in(ram_we_stb), .addr_in(cpu_a[10:0]), .wdata_in(cpu_dout),
	.wren_out(sram_we_o), .addr_out(sram_addr_o), .wdata_out(sram_wdata_o),
	.q_in(ram_q),
	.ssbus(ss_sram)
);

always @(posedge clk) begin
	if (sram_we_o) ram[sram_addr_o] <= sram_wdata_o;
	ram_q <= ram[sram_addr_o];
end

// =====================================================================
// IRQ periodico — UNICA sorgente di interrupt (galivan.cpp:1177)
//   XTAL(8'000'000) / 2 / 512 = 7812.5 Hz
// ce_snd e' gia' 8 MHz/2 = 4 MHz, quindi basta dividere per 512.
// irq0_line_hold: la linea resta asserita finche' la CPU non fa l'acknowledge.
// =====================================================================
reg [8:0] irq_div;
reg       irq_pend;
always @(posedge clk) begin
	if (reset) begin
		irq_div  <= 9'd0;
		irq_pend <= 1'b0;
	end else begin
		if (ce_snd) begin
			irq_div <= irq_div + 9'd1;
			if (irq_div == 9'd511) irq_pend <= 1'b1;
		end
		if (int_ack) irq_pend <= 1'b0;   // l'ack ha priorita' sull'asserzione
		// [SS-HOOK] restore: vince su tutto, avviene a CPU ferma
		if (sglue_ld) begin
			irq_pend <= sglue_out[8];
			irq_div  <= sglue_out[17:9];
		end
	end
end
assign cpu_int_n = ~irq_pend;

// =====================================================================
// Soundlatch (galivan.cpp:702, :866-867)
//   scrittura : dalla CPU main, IO 0x45
//   IN 0x06   : legge il comando
//   IN 0x04   : AZZERA il latch e ritorna 0 (soundlatch_clear_r, galivan.cpp:707)
// generic_latch_8_device::clear_w mette il valore a 0, che e' il valore "nessun
// comando" perche' ogni comando vero ha bit0 = 1.
// =====================================================================
wire [7:0] latch_in = LATCH_XFORM ? {latch_data[6:0], 1'b1} : latch_data;
reg  [7:0] soundlatch;
always @(posedge clk) begin
	if (reset) begin
		soundlatch <= 8'h00;
	end else begin
		// la scrittura della main CPU vince sull'azzeramento: un comando non si perde
		if (latch_wr)
			soundlatch <= latch_in;
		else if (io_rd_stb && cpu_a[7:0] == 8'h04)
			soundlatch <= 8'h00;
		if (sglue_ld) soundlatch <= sglue_out[7:0];   // [SS-HOOK] restore
	end
end

// =====================================================================
// [SS-HOOK] GLUE audio — un chunk unico con tutto lo stato che non sta ne'
// nei registri del Z80 ne' in una RAM (schema di Raiden, :309-322).
//
//   [7:0]   soundlatch        comando dalla CPU main
//   [8]     irq_pend          IRQ periodico in attesa
//   [17:9]  irq_div           fase del divisore /512: senza questo, al restore
//                             il primo IRQ arriva a distanza sbagliata e la
//                             musica ha uno scarto udibile
//   [25:18] dac1_r            latch del primo R2R
//   [33:26] dac2_r            latch del secondo R2R
//   [41:34] ym_addr_sel       address latch del YM3526 (serve al replay)
//
// bits_wr (sglue_ld) e' il COMMIT dell'ultima sezione: a quel punto la shadow
// dei registri e' gia' ripristinata, quindi e' il momento giusto per far
// partire il replay verso il chip.
// =====================================================================
wire [41:0] sglue_out;
wire        sglue_ld;
reg  [7:0]  ym_addr_sel;

auto_save_adaptor #(.N_BITS(42), .SS_IDX(SS_IDX_SGLUE)) u_ss_sglue (
	.clk(clk), .ssbus(ss_sglue),
	.bits_in ({ym_addr_sel, dac2_r, dac1_r, irq_div, irq_pend, soundlatch}),
	.bits_out(sglue_out),
	.bits_wr (sglue_ld)
);

// =====================================================================
// CONVENZIONE DAC — UNSIGNED
//
// galivan.cpp:1225-1226 usa DAC_8BIT_R2R, che in MAME e' il DAC a byte UNSIGNED
// (esiste a parte DAC_8BIT_R2R_TWOS_COMPLEMENT per il signed, e NON e' quello
// scelto qui). Lo conferma il commento del driver a galivan.cpp:1201-1203:
// "The R2R dacs are full range, min of 0v and max of (almost) 5v" — cioe' 0x00 =
// 0 V, 0x80 = meta' scala, 0xFF = fondo scala positivo, con offset in continua.
//
// Quindi: il valore scritto dal programma e' UNSIGNED 0..255, e la conversione a
// campione audio con segno e' la sottrazione della meta' scala, cioe' l'inversione
// del bit 7 (0x00 -> -32768, 0x80 -> 0, 0xFF -> +32512 su 16 bit).
// L'offset in continua sulla scheda vera lo toglie l'accoppiamento capacitivo.
//
// Valore di reset 0x80 (= silenzio dopo la rimozione dell'offset): sulla scheda il
// latch 74HC374 parte a 0x00, cioe' fondo scala negativo, che darebbe un "tump"
// all'accensione senza aggiungere niente di utile.
// =====================================================================
reg [7:0] dac1_r, dac2_r;
always @(posedge clk) begin
	if (reset) begin
		dac1_r <= 8'h80;
		dac2_r <= 8'h80;
	end else begin
		if (io_wr_stb) begin
			if (cpu_a[7:0] == 8'h02) dac1_r <= cpu_dout;   // galivan.cpp:864
			if (cpu_a[7:0] == 8'h03) dac2_r <= cpu_dout;   // galivan.cpp:865
		end
		// [SS-HOOK] restore: i due latch sono 74HC374 sulla scheda, senza questi
		// al ripristino le voci campionate riprendono dal valore sbagliato.
		if (sglue_ld) begin
			dac1_r <= sglue_out[25:18];
			dac2_r <= sglue_out[33:26];
		end
	end
end

wire signed [15:0] dac1_s = $signed({dac1_r ^ 8'h80, 8'h00});
wire signed [15:0] dac2_s = $signed({dac2_r ^ 8'h80, 8'h00});

// =====================================================================
// YM3526 = OPL (jtopl, OPL_TYPE=1). Scritture su IO 0x00 (indirizzo) e 0x01
// (dato), galivan.cpp:863. jtopl fa  write = !cs_n && !wr_n  e il blocco dei
// registri gira a velocita' di clk, non di cen: gli si da' quindi un impulso di
// UN clk con din/addr gia' registrati, non il livello lungo del bus Z80 (che
// verrebbe visto come decine di scritture consecutive e bloccherebbe la pulizia
// dei flag once-only in jtopl_mmr).
// =====================================================================
reg       ym_wr;
reg       ym_addr;
reg [7:0] ym_din;
wire      is_ym_w = io_wr_stb && (cpu_a[7:1] == 7'b0000000);   // 0x00 / 0x01
always @(posedge clk) begin
	ym_wr <= 1'b0;
	if (!reset && is_ym_w) begin
		ym_addr <= cpu_a[0];
		ym_din  <= cpu_dout;
		ym_wr   <= 1'b1;
	end
end

// =====================================================================
// [SS-HOOK] SHADOW DEI REGISTRI DEL YM3526 + REPLAY AL RESTORE
// Schema portato da Raiden (Raiden_audio_z80.sv:544-637), stesso chip jtopl.
//
// Lo stato interno del chip (inviluppi, fase degli operatori, timer) non e'
// accessibile e non si puo' salvare. Si salva invece cio' che il chip HA
// RICEVUTO: ogni scrittura della CPU aggiorna una shadow di 256 byte, e al
// restore una macchina la riversa tutta dentro al chip. Timbri, note, key-on e
// timer tornano al loro posto e la musica riprende dal punto giusto.
//
// L'ordine dei passi conta:
//   pre    scrive reg 0x04 = 0x80 -> azzera i flag dei timer rimasti dal
//          momento precedente il caricamento (altrimenti restano appesi)
//   sweep  registri 0..255, indirizzo poi dato
//   final  riscrive l'address latch com'era quando si e' salvato
//
// Le attese sono in colpi di ce_snd: fra un DATO e il successivo servono piu'
// di 84 cen, perche' la pipeline di jtopl gira a cen/4 su 18 slot. Durante il
// replay il Z80 sound e' fermo (vedi cpu_cen).
// =====================================================================
always @(posedge clk) begin
	if (reset)                          ym_addr_sel <= 8'd0;
	else if (sglue_ld)                  ym_addr_sel <= sglue_out[41:34];
	else if (is_ym_w && !cpu_a[0])      ym_addr_sel <= cpu_dout;
end

wire       ymsh_wren;
wire [7:0] ymsh_idx, ymsh_wdata;
reg  [7:0] ymsh_q;
(* ramstyle = "M10K,no_rw_check" *) reg [7:0] ym_shadow [0:255];

ss_ram_adaptor #(.WIDTH(8), .WIDTHAD(8), .SS_IDX(SS_IDX_YMSH)) u_ss_ymsh (
	.clk(clk),
	.wren_in(is_ym_w & cpu_a[0]), .addr_in(ym_addr_sel), .wdata_in(cpu_dout),
	.wren_out(ymsh_wren), .addr_out(ymsh_idx), .wdata_out(ymsh_wdata),
	.q_in(ymsh_q),
	.ssbus(ss_ymsh)
);

reg       rp_pre;      // passo iniziale: reg 0x04 <= 0x80
reg       rp_final;    // passo finale: rimette l'address latch
reg [7:0] rp_reg;
reg [1:0] rp_ph;       // 0=scrive addr, 1=attesa, 2=scrive dato, 3=attesa lunga
reg [6:0] rp_wait;

// La lettura per il SAVE esclude il replay in combinatoria: se un save parte
// mentre il replay e' in corso, senza questo la prima parola del chunk verrebbe
// presa dall'indirizzo dello sweep invece che da quello del bus (off-by-one).
wire       ymsh_ss_rd = ss_ymsh.access(SS_IDX_YMSH) && ss_ymsh.read;
wire [7:0] ymsh_raddr = (rp_active && !ymsh_ss_rd) ? rp_reg : ymsh_idx;

always @(posedge clk) begin
	if (ymsh_wren) ym_shadow[ymsh_idx] <= ymsh_wdata;
	ymsh_q <= ym_shadow[ymsh_raddr];
end

always @(posedge clk) begin
	if (reset) begin
		rp_active <= 1'b0; rp_pre <= 1'b0; rp_final <= 1'b0;
		rp_reg    <= 8'd0; rp_ph  <= 2'd0; rp_wait  <= 7'd0;
	end else if (sglue_ld) begin
		rp_active <= 1'b1; rp_pre <= 1'b1; rp_final <= 1'b0;
		rp_reg    <= 8'd0; rp_ph  <= 2'd0; rp_wait  <= 7'd0;
	end else if (rp_active && ymsh_ss_rd) begin
		rp_active <= 1'b0;    // save partito durante il replay: si abortisce
	end else if (rp_active && ce_snd) begin
		case (rp_ph)
		2'd0: begin rp_ph <= 2'd1; rp_wait <= 7'd8;   end
		2'd1: begin
			if (|rp_wait)      rp_wait   <= rp_wait - 1'b1;
			else if (rp_final) rp_active <= 1'b0;
			else               rp_ph     <= 2'd2;
		end
		2'd2: begin rp_ph <= 2'd3; rp_wait <= 7'd100; end
		2'd3: begin
			if (|rp_wait) rp_wait <= rp_wait - 1'b1;
			else begin
				rp_ph <= 2'd0;
				if (rp_pre) rp_pre <= 1'b0;
				else begin
					rp_reg <= rp_reg + 1'b1;
					if (rp_reg == 8'd255) rp_final <= 1'b1;
				end
			end
		end
		endcase
	end
end

wire       rp_wr  = rp_active && (rp_ph == 2'd0 || rp_ph == 2'd2);
wire       rp_a0  = (rp_ph == 2'd2);
wire [7:0] rp_din = rp_a0    ? (rp_pre ? 8'h80 : ymsh_q) :
                    rp_pre   ? 8'h04 :
                    rp_final ? ym_addr_sel : rp_reg;

// bus verso il chip: durante il replay comanda la macchina, la CPU e' ferma
wire       ym_wr_eff   = rp_active ? rp_wr  : ym_wr;
wire       ym_addr_eff = rp_active ? rp_a0  : ym_addr;
wire [7:0] ym_din_eff  = rp_active ? rp_din : ym_din;

wire signed [15:0] ym_snd;

jtopl u_opl
(
	.rst    ( reset     ),
	.clk    ( clk       ),
	.cen    ( ce_ym     ),   // 4 MHz (galivan.cpp:1222, XTAL(8'000'000)/2)
	.din    ( ym_din_eff   ),
	.addr   ( ym_addr_eff  ),
	.cs_n   ( ~ym_wr_eff   ),
	.wr_n   ( ~ym_wr_eff   ),
	.dout   (           ),   // nessuna porta di lettura in questo hardware (galivan.cpp:863)
	.irq_n  (           ),   // nessun filo di IRQ verso la CPU  (galivan.cpp:1222)
	.fmvol0 ( 8'h10     ),   // Q4.4, 0x10 = 1.0x su tutti i canali
	.fmvol1 ( 8'h10     ),
	.fmvol2 ( 8'h10     ),
	.fmvol3 ( 8'h10     ),
	.fmvol4 ( 8'h10     ),
	.fmvol5 ( 8'h10     ),
	.fmvol6 ( 8'h10     ),
	.fmvol7 ( 8'h10     ),
	.fmvol8 ( 8'h10     ),
	.snd    ( ym_snd    ),
	.sample (           )
);

// =====================================================================
// Dato verso la CPU
//   IN 0x04 -> 0x00 (soundlatch_clear_r ritorna 0, galivan.cpp:709)
//   IN 0x06 -> soundlatch
//   tutto il resto non e' mappato -> bus fluttuante = 0xFF
// In acknowledge di interrupt il bus e' libero: 0xFF = RST 38h, che coincide con
// il vettore dell'IM 1 usato dal programma.
// =====================================================================
reg [7:0] io_din;
always @(*) begin
	case (cpu_a[7:0])
		8'h04:   io_din = 8'h00;
		8'h06:   io_din = soundlatch;
		default: io_din = 8'hFF;
	endcase
end

always @(*) begin
	if (int_ack)        cpu_din = 8'hFF;
	else if (~cpu_iorq_n) cpu_din = io_din;
	else if (rom_cs)    cpu_din = rom_data;
	else if (ram_cs)    cpu_din = ram_q;
	else                cpu_din = 8'hFF;
end

// =====================================================================
// FILTRI ANALOGICI DELLA SCHEDA (galivan.cpp:1211-1219)
//
// Tre Sallen-Key passa-basso a guadagno unitario, uno sul YM e uno per ciascun
// DAC. Valori dal driver e frequenze calcolate con
//     fc = 1/(2*pi*sqrt(R1 R2 C1 C2))     Q = sqrt(R1 R2 C1 C2)/(C2 (R1+R2))
//
//   ymfilter    R 4.7k  C 3.3nF/1.0nF  -> fc 18640.8 Hz  Q 0.908  (galivan.cpp:1211)
//   dacfilter1  R  10k  C 10nF/4.7nF   -> fc  2321.5 Hz  Q 0.729  (galivan.cpp:1215)
//   dacfilter2  R  10k  C 10nF/4.7nF   -> fc  2321.5 Hz  Q 0.729  (galivan.cpp:1219)
//
// Quello del YM e' quasi solo anti-alias. Quelli dei DAC no: tagliano a 2.3 kHz
// e sono cio' che da' il timbro alle voci e alle percussioni campionate. Senza,
// i due R2R escono metallici e pieni di alias.
//
// FREQUENZA DI CAMPIONAMENTO: 96 MHz / 1728 = 55555.6 Hz.
//
// Non e' un numero comodo scelto a caso, e' il rate del chip. jtopl_div ha W=2,
// quindi cenop = cen/4; il YM3526 ha 18 slot, quindi un campione ogni 18 cenop =
// 72 cen. Con cen a 4 MHz sono 4e6/72 = 55555.6 Hz, cioe' il rate del YM3526
// vero. 96e6/1728 da' esattamente lo stesso numero.
//
// Prima era 96e6/2048 = 46875 Hz: SOTTO il rate della sorgente. Campionare un
// segnale a una frequenza piu' bassa di quella a cui cambia e' decimazione senza
// filtro anti-alias — le componenti sopra fs/2 si ripiegano dentro la banda e
// diventano toni che sulla scheda non ci sono. Il biquad del YM taglia a 18.6 kHz,
// che a 46875 Hz e' gia' oltre due terzi di Nyquist: non protegge niente.
//
// Coefficienti Q2.14 da trasformata bilineare CON pre-warping a questa fs.
// Verificati: guadagno in continua 1.00000 per entrambi, poli dentro il cerchio
// unitario (moduli 0.835 e 0.598).
// =====================================================================
reg [10:0] aud_div;
always @(posedge clk)
	aud_div <= (reset || aud_div == 11'd1727) ? 11'd0 : (aud_div + 11'd1);
wire ce_aud = (aud_div == 11'd0);          // 55555.6 Hz

wire signed [15:0] dac1_f, dac2_f, ym_f;

// DAC: fc 2321.5 Hz, Q 0.729
dangar_biquad #(
	.B0(18'sd238), .B1(18'sd477), .B2(18'sd238),
	.A1(-18'sd26863), .A2(18'sd11432)
) u_flt_dac1 (
	.clk(clk), .reset(reset), .ce(ce_aud), .din(dac1_s), .dout(dac1_f)
);

dangar_biquad #(
	.B0(18'sd238), .B1(18'sd477), .B2(18'sd238),
	.A1(-18'sd26863), .A2(18'sd11432)
) u_flt_dac2 (
	.clk(clk), .reset(reset), .ce(ce_aud), .din(dac2_s), .dout(dac2_f)
);

// YM3526: fc 18640.8 Hz, Q 0.908
dangar_biquad #(
	.B0(18'sd8408), .B1(18'sd16817), .B2(18'sd8408),
	.A1(18'sd11388), .A2(18'sd5861)
) u_flt_ym (
	.clk(clk), .reset(reset), .ce(ce_aud), .din(ym_snd), .dout(ym_f)
);

// =====================================================================
// MIX  (galivan.cpp:1195-1208)
//
// Il driver ha gia' fatto i conti delle resistenze di mixaggio E della diversa
// escursione fra YM3014 (2.5 Vpp) e R2R (5 Vpp), e ne esce:
//     ym 0.492203   dac1 0.209505   dac2 0.298291     (somma = 1.0)
//
// Qui i guadagni sono in Q0.8 su 256, con somma ESATTAMENTE 256:
//     ym   126/256 = 0.49219   (errore  +0.00%)
//     dac1  54/256 = 0.21094   (errore  +0.7%)
//     dac2  76/256 = 0.29688   (errore  -0.5%)
// (con jtframe_mixer, che ha guadagni in Q4.4, il passo minimo e' 1/16 = 0.0625 e
//  dac1 sbaglierebbe del 10%: per questo il mix e' fatto qui a mano.)
//
// Niente clipping, e si dimostra: gli ingressi stanno in [-32768, +32767] e i
// guadagni sommano a 256, quindi |somma| <= 32768*256 = 2^23 e il taglio [23:8]
// e' esatto. Caso peggiore positivo reale: 32767*126 + 32512*(54+76) = 8355202,
// sotto 2^23-1. Caso peggiore negativo: -32768*256 = -2^23 -> 0x8000 = -32768.
// =====================================================================
localparam signed [8:0] G_YM   = 9'sd126;
localparam signed [8:0] G_DAC1 = 9'sd54;
localparam signed [8:0] G_DAC2 = 9'sd76;

reg signed [24:0] m_ym, m_d1, m_d2;
reg signed [26:0] m_sum;
reg signed [15:0] mix_r;

always @(posedge clk) begin
	if (reset) begin
		m_ym  <= 25'sd0;
		m_d1  <= 25'sd0;
		m_d2  <= 25'sd0;
		m_sum <= 27'sd0;
		mix_r <= 16'sd0;
	end else begin
		m_ym  <= ym_f   * G_YM;      // usciti dai Sallen-Key della scheda
		m_d1  <= dac1_f * G_DAC1;
		m_d2  <= dac2_f * G_DAC2;
		m_sum <= {{2{m_ym[24]}}, m_ym} + {{2{m_d1[24]}}, m_d1} + {{2{m_d2[24]}}, m_d2};
		mix_r <= m_sum[23:8];
	end
end

// mono: la scheda ha un solo altoparlante (galivan.cpp:1186)
assign audio_l = mix_r;
assign audio_r = mix_r;

endmodule
