// SPDX-License-Identifier: GPL-3.0-or-later
/*  This file is part of rmGalivan_MiSTer.
    Author: Umberto Parisi (rmonic79)

    dangar_nb1414m4.sv — Nichibutsu NB1414M4, il blitter di Ninja Emaki.

    Riferimento: mame/nichibutsu/nb1414m4.cpp (Angelo Salese, su ricerche di
    Tomasz Slanina e Legion). ATTENZIONE: in MAME quel chip NON e' emulato dal
    silicio, e' una SIMULAZIONE del comportamento osservato. Qui si riproduce
    quella simulazione, quindi si eredita anche cio' che le manca — il driver
    annota "minor protection issues" e due comandi che restano ignoti.

    COSA FA
    Copia stringhe nella VRAM del layer testo pescandole dalla propria ROM dati
    da 16 KB. La VRAM e' 2 KB: 0x000-0x3FF codice del carattere, 0x400-0x7FF
    attributo/palette. Parte su scrittura alla porta 0x86 (galivan.cpp:772-776).

    A ogni esecuzione, PRIMA di qualunque comando, latcha lo scroll dello
    sfondo dalla VRAM (nb1414m4.cpp:343-345):
        scroll_x = vram[0x0d] | (vram[0x0e] << 8)
        scroll_y = vram[0x0b] | (vram[0x0c] << 8)
    E' l'unica via da cui Ninja Emaki ottiene lo scroll: nella sua io_map i
    registri 0x41-0x44 di Galivan non esistono.

    Il comando sono i primi due byte della VRAM, {vram[0], vram[1]}, smistato
    sul byte alto (nb1414m4.cpp:347-364):
        0x00  insert coin + crediti        0x02  fill oppure copia di pagina
        0x06  service mode                 0x0e  HUD di gioco
        0x80  attract di Ninja Emaki, non fa niente
        0xff  POST di Ninja Emaki, non fa niente

    I PRIMI 18 BYTE DELLA VRAM NON SI TOCCANO: sono i parametri del chip.
    Ogni scrittura li salta, come il `if(i+dst < 18) continue` del sorgente
    (nb1414m4.cpp:78, 94).

    ---------------------------------------------------------------------------
    STRUTTURA — TABELLA + QUATTRO PRIMITIVE SEPARATE
    ---------------------------------------------------------------------------
    Le quattro routine sono lunghe (il service mode da solo e' una trentina di
    operazioni) ma fatte tutte degli stessi gesti. Quindi:

      - un PROGRAMMA a microcodice, una riga per ogni riga del sorgente MAME,
        che si leggono affiancate: e' la parte dove un errore si vede;
      - quattro PRIMITIVE — DMA, FILL, PUT, SCORE — ognuna con i PROPRI stati
        e il PROPRIO contatore. Niente contatori condivisi, niente stati
        riusati fra primitive diverse, nessun salto calcolato sulle costanti
        di stato: sono esattamente le scorciatoie che fanno incastrare due
        routine senza che si veda.

    ---------------------------------------------------------------------------
    TIMING
    ---------------------------------------------------------------------------
    La VRAM ha UNA porta, condivisa con la CPU: mentre il blitter lavora la CPU
    resta ferma (`busy`). E' anche il comportamento giusto — sulla scheda il
    gioco scrive la porta 0x86 e aspetta.

    Caso peggiore, la copia di una pagina intera: 0x400 byte per 5 cicli = 5120
    cicli, 53 us a 96 MHz. Il fill costa 2 cicli a cella, 2048 cicli = 21 us.
    Entrambi dentro un frame (16.8 ms) con tre ordini di grandezza di margine.

    Gli indirizzi verso ROM e VRAM escono REGISTRATI. I selettori del
    microcodice (quale sorgente, quale condizione, quale valore) si valutano
    UNA volta all'inizio dell'istruzione e finiscono in registri: nel ciclo
    interno restano solo somme su contatori.
*/

module dangar_nb1414m4
(
	input             clk,
	input             reset,

	input             trig,          // impulso: scrittura su 0x86
	input             frame_tick,    // impulso a inizio frame

	// ROM dati da 16 KB. Contratto del core: indirizzo al ciclo T, dato a T+1.
	output reg [13:0] rom_addr,
	input       [7:0] rom_data,

	// VRAM del layer testo (char RAM da 2 KB), porta condivisa con la CPU
	output reg [10:0] vram_addr,
	output reg        vram_we,
	output reg  [7:0] vram_din,
	input       [7:0] vram_dout,

	output            busy,          // alto mentre lavora: tiene ferma la CPU

	output reg [12:0] scroll_x,
	output reg [12:0] scroll_y
);

// ===========================================================================
// Contatore di frame — serve solo al lampeggio di "insert coin", che nel
// sorgente e' `screen().frame_number() & 0x10` (nb1414m4.cpp:108, 130).
// ===========================================================================
reg [7:0] frame_cnt;
always @(posedge clk) begin
	if (reset)           frame_cnt <= 8'd0;
	else if (frame_tick) frame_cnt <= frame_cnt + 8'd1;
end
wire fl_cond = frame_cnt[4];

// ===========================================================================
// MICROCODICE — il programma
// ===========================================================================
localparam [3:0] OP_END   = 4'd0,   // fine
                 OP_DMA   = 4'd1,   // dst da `ptr`, copia `size` byte da `src`
                 OP_PUT   = 4'd2,   // dst da `ptr` (o dst+1), un carattere
                 OP_SCORE = 4'd3,   // dst da `ptr`, punteggio BCD a 8 cifre
                 OP_LOOP  = 4'd4,   // N copie da 3 byte, sorgente scelta da un bit
                 OP_CALL  = 4'd5,   // chiamata, un livello
                 OP_RET   = 4'd6,
                 OP_RETIF = 4'd7,   // torna se la condizione e' vera
                 OP_C0200 = 4'd8;   // comando 0x0200, sceglie fill o copia

localparam [1:0] C_ONE = 2'd0, C_FL = 2'd1, C_NCMD0 = 2'd2, C_NCMD1 = 2'd3;

localparam [3:0] K_NEVER = 4'd0, K_INGAME = 4'd1, K_CRED_NZ = 4'd2,
                 K_CRED_Z = 4'd3, K_CRED_NE1 = 4'd4, K_CRED_LE1 = 4'd5,
                 K_NCMD7 = 4'd6, K_CMD2 = 4'd7, K_CMD34 = 4'd8;

localparam [2:0] X_NONE = 3'd0, X_DIFF = 3'd1, X_CAB = 3'd2,
                 X_DEMO = 3'd3, X_2P = 3'd4;

localparam [3:0] V_LIVES = 4'd0, V_CREDHI_SP = 4'd1, V_CREDLO = 4'd2,
                 V_CA_HI = 4'd3, V_CA_LO = 4'd4, V_CB_HI = 4'd5,
                 V_CB_LO = 4'd6, V_SND_HI = 4'd7, V_SND_LO = 4'd8;

localparam [6:0] P_0000 = 7'd0,  P_IC   = 7'd4,  P_CR   = 7'd12,
                 P_0200 = 7'd24, P_0E00 = 7'd32, P_0600 = 7'd48,
                 P_NOP  = 7'd120;

reg  [6:0] pc, link;

reg  [3:0] uop;
reg [13:0] u_ptr, u_src, u_pal;
reg [10:0] u_size;
reg  [1:0] u_cond;
reg  [3:0] u_skip;
reg  [2:0] u_xsel;
reg  [3:0] u_vsel;
reg        u_dofs;
reg  [6:0] u_tgt;
reg        u_base2;
reg  [3:0] u_n;
reg  [2:0] u_bit0;
reg  [1:0] u_vsrc;

always @(*) begin
	uop = OP_END; u_ptr = 14'd0; u_src = 14'd0; u_size = 11'd0; u_pal = 14'd0;
	u_cond = C_ONE; u_skip = K_NEVER; u_xsel = X_NONE; u_vsel = V_LIVES;
	u_dofs = 1'b0; u_tgt = 7'd0; u_base2 = 1'b0;
	u_n = 4'd0; u_bit0 = 3'd0; u_vsrc = 2'd0;
	case (pc)
	// ---- 0x0000: insert coin + crediti (nb1414m4.cpp:350) ----------------
	P_0000+0: begin uop = OP_CALL; u_tgt = P_IC; end
	P_0000+1: begin uop = OP_CALL; u_tgt = P_CR; end
	P_0000+2: begin uop = OP_END; end

	// ---- insert_coin_msg (nb1414m4.cpp:102-123) --------------------------
	P_IC+0: begin uop = OP_RETIF; u_skip = K_INGAME; end
	P_IC+1: begin uop = OP_DMA; u_ptr = 14'h0001; u_src = 14'h0003;
	              u_size = 11'h10; u_cond = C_FL;  u_skip = K_CRED_NZ; end
	P_IC+2: begin uop = OP_DMA; u_ptr = 14'h0049; u_src = 14'h004b;
	              u_size = 11'h18; u_cond = C_ONE; u_skip = K_CRED_Z; end
	P_IC+3: begin uop = OP_RET; end

	// ---- credit_msg (nb1414m4.cpp:125-155) -------------------------------
	P_CR+0: begin uop = OP_DMA; u_ptr = 14'h0023; u_src = 14'h0025;
	              u_size = 11'h10; u_cond = C_ONE; end
	P_CR+1: begin uop = OP_PUT; u_ptr = 14'h0045; u_vsel = V_CREDHI_SP; u_pal = 14'h0047; end
	P_CR+2: begin uop = OP_PUT; u_dofs = 1'b1;    u_vsel = V_CREDLO;    u_pal = 14'h0048; end
	P_CR+3: begin uop = OP_RETIF; u_skip = K_INGAME; end
	P_CR+4: begin uop = OP_DMA; u_ptr = 14'h007b; u_src = 14'h007d;
	              u_size = 11'h18; u_cond = C_FL; u_skip = K_CRED_NE1; end
	P_CR+5: begin uop = OP_DMA; u_ptr = 14'h00ad; u_src = 14'h00af;
	              u_size = 11'h18; u_cond = C_FL; u_skip = K_CRED_LE1; end
	P_CR+6: begin uop = OP_RET; end

	// ---- 0x0200 (nb1414m4.cpp:186-212) -----------------------------------
	P_0200+0: begin uop = OP_C0200; end
	P_0200+1: begin uop = OP_END; end

	// ---- 0x0e00, HUD di gioco (nb1414m4.cpp:299-327) ---------------------
	P_0E00+0: begin uop = OP_DMA;   u_ptr = 14'h00df; u_src = 14'h00e1;
	                u_size = 11'd8; u_cond = C_ONE; end                  // hi-score
	P_0E00+1: begin uop = OP_DMA;   u_ptr = 14'h00fb; u_src = 14'h00fd;
	                u_size = 11'd8; u_cond = C_NCMD0; end                // messaggio 1P
	P_0E00+2: begin uop = OP_SCORE; u_ptr = 14'h010d; u_base2 = 1'b0; end
	P_0E00+3: begin uop = OP_DMA;   u_ptr = 14'h0117; u_src = 14'h0119;
	                u_size = 11'd8; u_cond = C_NCMD1; u_skip = K_NCMD7; end
	P_0E00+4: begin uop = OP_SCORE; u_ptr = 14'h0129; u_base2 = 1'b1;
	                u_skip = K_NCMD7; end
	P_0E00+5: begin uop = OP_DMA;   u_ptr = 14'h0133; u_src = 14'h0135;
	                u_size = 11'h10; u_cond = C_ONE; u_skip = K_CMD2; end // game over
	P_0E00+6: begin uop = OP_CALL;  u_tgt = P_IC; u_skip = K_CMD2; end
	P_0E00+7: begin uop = OP_CALL;  u_tgt = P_CR; u_skip = K_CMD34; end
	P_0E00+8: begin uop = OP_END; end

	// ---- 0x0600, service mode (nb1414m4.cpp:244-297) ---------------------
	P_0600+0:  begin uop = OP_PUT; u_ptr = 14'h01f5; u_vsel = V_LIVES; end
	P_0600+1:  begin uop = OP_DMA; u_ptr = 14'h01f8; u_src = 14'h01fa;
	                 u_xsel = X_DIFF; u_size = 11'd12; end
	P_0600+2:  begin uop = OP_DMA; u_ptr = 14'h0262; u_src = 14'h0264;
	                 u_xsel = X_CAB;  u_size = 11'd12; end
	P_0600+3:  begin uop = OP_DMA; u_ptr = 14'h0294; u_src = 14'h0296;
	                 u_xsel = X_DEMO; u_size = 11'd12; end
	P_0600+4:  begin uop = OP_PUT; u_ptr = 14'h02c6; u_vsel = V_CA_HI; end
	P_0600+5:  begin uop = OP_PUT; u_ptr = 14'h02c9; u_vsel = V_CA_LO; end
	P_0600+6:  begin uop = OP_PUT; u_ptr = 14'h02cc; u_vsel = V_CB_HI; end
	P_0600+7:  begin uop = OP_PUT; u_ptr = 14'h02cf; u_vsel = V_CB_LO; end
	P_0600+8:  begin uop = OP_PUT; u_ptr = 14'h02d2; u_vsel = V_SND_HI; end
	P_0600+9:  begin uop = OP_PUT; u_dofs = 1'b1;    u_vsel = V_SND_LO; end
	P_0600+10: begin uop = OP_DMA; u_ptr = 14'h02d6; u_src = 14'h02d8;
	                 u_xsel = X_2P; u_size = 11'd12; end
	P_0600+11: begin uop = OP_LOOP; u_ptr = 14'h0308; u_n = 4'd5;
	                 u_bit0 = 3'd4; u_vsrc = 2'd0; end   // input di sistema
	P_0600+12: begin uop = OP_LOOP; u_ptr = 14'h030a; u_n = 4'd7;
	                 u_bit0 = 3'd6; u_vsrc = 2'd1; end   // input 1P / 2P
	P_0600+13: begin uop = OP_LOOP; u_ptr = 14'h030c; u_n = 4'd8;
	                 u_bit0 = 3'd7; u_vsrc = 2'd2; end   // DSW1
	P_0600+14: begin uop = OP_LOOP; u_ptr = 14'h030e; u_n = 4'd8;
	                 u_bit0 = 3'd7; u_vsrc = 2'd3; end   // DSW2
	P_0600+15: begin uop = OP_END; end
	default: uop = OP_END;
	endcase
end

// ===========================================================================
// Stati — uno per ogni passo, nessuna aritmetica sulle costanti
// ===========================================================================
localparam [5:0]
	S_IDLE  = 6'd0,
	S_PAR0  = 6'd1,  S_PAR1  = 6'd2,  S_LAT   = 6'd3,  S_PARW = 6'd6,
	S_FETCH = 6'd4,  S_NEXT  = 6'd5,
	S_PTR0  = 6'd8,  S_PTR1  = 6'd9,  S_PTR2  = 6'd10, S_PTR3 = 6'd11, S_PTR4 = 6'd12,
	S_DMA0  = 6'd16, S_DMA1  = 6'd17, S_DMA2  = 6'd18, S_DMA3 = 6'd19, S_DMA4 = 6'd20,
	S_DMAE  = 6'd21,
	S_FIL0  = 6'd24, S_FIL1  = 6'd25, S_FIL2  = 6'd26,
	S_PUT0  = 6'd28, S_PUT1  = 6'd29, S_PUT2  = 6'd30,
	S_SC0   = 6'd32, S_SC1   = 6'd33, S_SC2   = 6'd34, S_SC3  = 6'd35,
	S_SCA   = 6'd50, S_SCB   = 6'd51,
	S_RFR0  = 6'd52, S_RFR1  = 6'd53,
	S_LP0   = 6'd36,
	S_C20A  = 6'd40, S_C20B  = 6'd41, S_C20C  = 6'd42, S_C20D = 6'd43,
	S_C20E  = 6'd44, S_C20F  = 6'd45, S_C20G  = 6'd46, S_C20H = 6'd47,
	S_C20I  = 6'd48, S_C20J  = 6'd49;

reg  [5:0] st;
reg  [2:0] after_ptr;                 // 0=DMA 1=PUT 2=SCORE 3=LOOP

reg [15:0] cmd;
reg [13:0] dst, src_r;
reg [10:0] size_r;
reg        cond_r;
reg  [7:0] tile_r, pal_r, data13, ptr_hi;
reg  [7:0] vpar [0:17];
reg  [4:0] pidx;
reg        in_game;
reg [15:0] prev0200;
reg  [7:0] prev0200_frame;

reg [10:0] d_i;                       // contatore della DMA
reg [10:0] f_i;                       // contatore del FILL
reg  [2:0] sc_i;                      // cifra del punteggio
reg        sc_first;
reg  [7:0] sc_prev5;
reg  [3:0] loop_i;                    // iterazione di OP_LOOP
reg        in_loop;

assign busy = (st != S_IDLE);

// ---- selettori, valutati a inizio istruzione ------------------------------
wire credit_z = (vpar[15] == 8'h00);
wire credit_1 = (vpar[15] == 8'h01);

wire skip_now =
	(u_skip == K_INGAME)   ? in_game             :
	(u_skip == K_CRED_NZ)  ? ~credit_z           :
	(u_skip == K_CRED_Z)   ?  credit_z           :
	(u_skip == K_CRED_NE1) ? ~credit_1           :
	(u_skip == K_CRED_LE1) ? (credit_z|credit_1) :
	(u_skip == K_NCMD7)    ? ~cmd[7]             :
	(u_skip == K_CMD2)     ?  cmd[2]             :
	(u_skip == K_CMD34)    ? (cmd[2]|cmd[3]|cmd[4]) : 1'b0;

wire cond_sel = (u_cond == C_FL)    ? fl_cond :
                (u_cond == C_NCMD0) ? ~cmd[0] :
                (u_cond == C_NCMD1) ? ~cmd[1] : 1'b1;

// Le tre scelte di stringa del service mode sono "0 oppure 0x18": un solo
// prodotto per un bit, cioe' un mux, non un moltiplicatore.
wire [13:0] xofs =
	(u_xsel == X_DIFF) ? ({12'd0, vpar[7][5:4]} * 14'h18) :
	(u_xsel == X_CAB)  ? (vpar[7][7] ? 14'h18 : 14'd0)    :
	(u_xsel == X_DEMO) ? (vpar[7][6] ? 14'h18 : 14'd0)    :
	(u_xsel == X_2P)   ? (cmd[0]     ? 14'h18 : 14'd0)    : 14'd0;

wire [7:0] put_val =
	(u_vsel == V_LIVES)  ? {5'h06, vpar[7][2:0]} :
	(u_vsel == V_CREDLO) ? {4'h3, vpar[15][3:0]} :
	(u_vsel == V_CA_HI)  ? {4'h3, vpar[15][7:4]} :
	(u_vsel == V_CA_LO)  ? {4'h3, vpar[15][3:0]} :
	(u_vsel == V_CB_HI)  ? {4'h3, vpar[16][7:4]} :
	(u_vsel == V_CB_LO)  ? {4'h3, vpar[16][3:0]} :
	(u_vsel == V_SND_HI) ? {4'h3, vpar[17][7:4]} :
	(u_vsel == V_SND_LO) ? {4'h3, vpar[17][3:0]} :
	(vpar[15][7:4] != 4'd0) ? {4'h3, vpar[15][7:4]} : 8'h20;   // V_CREDHI_SP

wire [7:0] loop_src = (u_vsrc == 2'd0) ? vpar[4]
                    : (u_vsrc == 2'd1) ? (cmd[0] ? vpar[3] : vpar[2])
                    : (u_vsrc == 2'd2) ? vpar[5] : vpar[6];
wire [2:0] loop_bit = u_bit0 - loop_i[2:0];
wire       loop_on  = loop_src[loop_bit];

wire [13:0] dst_i  = dst + {3'd0, d_i};
wire        skip18 = (dst_i < 14'd18);

// indirizzo di scrittura di PUT: dst oppure dst+1, deciso dal microcodice
wire [10:0] put_a = u_dofs ? (dst[10:0] + 11'd1) : dst[10:0];

// ===========================================================================
// Sequenziatore
// ===========================================================================
always @(posedge clk) begin
	vram_we <= 1'b0;

	if (reset) begin
		st <= S_IDLE; scroll_x <= 13'd0; scroll_y <= 13'd0;
		prev0200 <= 16'hFFFF; prev0200_frame <= 8'd0; in_game <= 1'b0;
		pc <= P_NOP; link <= P_NOP; in_loop <= 1'b0;
	end
	else case (st)

	S_IDLE: if (trig) begin pidx <= 5'd0; vram_addr <= 11'd0; st <= S_PAR0; end

	// ---- i 18 byte di parametro, letti una volta sola --------------------
	S_PAR0: st <= S_PAR1;
	S_PAR1: begin
		vpar[pidx] <= vram_dout;
		// rom_addr si stabilizza a fine ciclo: il dato di rom[0x13] arriva
		// due cicli dopo, non uno. Da qui lo stato di attesa.
		if (pidx == 5'd17) begin rom_addr <= 14'h0013; st <= S_PARW; end
		else begin pidx <= pidx + 5'd1; vram_addr <= {6'd0, pidx} + 11'd1; st <= S_PAR0; end
	end

	S_PARW: st <= S_LAT;

	S_LAT: begin
		scroll_x <= {vpar[14][4:0], vpar[13]};
		scroll_y <= {vpar[12][4:0], vpar[11]};
		cmd      <= {vpar[0], vpar[1]};
		data13   <= rom_data;                 // rom[0x13]: palette di riposo
		in_loop  <= 1'b0;
		case (vpar[0])
			8'h00: pc <= P_0000;
			8'h02: pc <= P_0200;
			8'h06: pc <= P_0600;
			8'h0e: pc <= P_0E00;
			default: pc <= P_NOP;             // 0x80, 0xff e ignoti
		endcase
		st <= S_FETCH;
	end

	// ---- prelievo ed esecuzione dell'istruzione --------------------------
	S_FETCH: if (skip_now && (uop != OP_RETIF)) st <= S_NEXT;
	         else case (uop)
			OP_END:   st <= S_IDLE;
			OP_RET:   begin pc <= link; st <= S_FETCH; end
			OP_RETIF: begin pc <= skip_now ? link : (pc + 7'd1); st <= S_FETCH; end
			OP_CALL:  begin link <= pc + 7'd1; pc <= u_tgt; st <= S_FETCH; end
			OP_DMA:   begin src_r <= u_src + xofs; size_r <= u_size;
			                cond_r <= cond_sel; in_loop <= 1'b0;
			                after_ptr <= 3'd0; st <= S_PTR0; end
			OP_PUT:   begin tile_r <= put_val; after_ptr <= 3'd1;
			                st <= u_dofs ? S_PUT0 : S_PTR0; end
			OP_SCORE: begin after_ptr <= 3'd2; st <= S_PTR0; end
			OP_LOOP:  begin loop_i <= 4'd0; in_loop <= 1'b1;
			                after_ptr <= 3'd3; st <= S_PTR0; end
			OP_C0200: st <= S_C20A;
			default:  st <= S_NEXT;
		endcase

	// I 18 byte di parametro si RILEGGONO fra un'istruzione e l'altra.
	// MAME li legge sempre dalla VRAM viva, e le scritture di un carattere
	// singolo (crediti, punteggio, service mode) NON hanno il filtro dei primi
	// 18 byte: possono quindi cambiare cio' che l'istruzione dopo legge. Una
	// fotografia presa a inizio esecuzione darebbe risultati diversi.
	// Costa 36 cicli per istruzione, nulla rispetto al resto.
	S_NEXT: begin pc <= pc + 7'd1; pidx <= 5'd0; vram_addr <= 11'd0; st <= S_RFR0; end
	S_RFR0: st <= S_RFR1;
	S_RFR1: begin
		vpar[pidx] <= vram_dout;
		if (pidx == 5'd17) st <= S_FETCH;
		else begin pidx <= pidx + 5'd1; vram_addr <= {6'd0, pidx} + 11'd1; st <= S_RFR0; end
	end

	// ---- primitiva PTR: dst = (rom[ptr]<<8 | rom[ptr+1]) & 0x3fff --------
	S_PTR0: begin rom_addr <= u_ptr;                             st <= S_PTR1; end
	S_PTR1: st <= S_PTR2;
	S_PTR2: begin ptr_hi <= rom_data; rom_addr <= u_ptr + 14'd1; st <= S_PTR3; end
	S_PTR3: st <= S_PTR4;
	S_PTR4: begin
		dst <= {ptr_hi[5:0], rom_data};
		case (after_ptr)
			3'd0: begin d_i <= 11'd0;  st <= S_DMA0; end
			3'd1: begin                st <= S_PUT0; end
			3'd2: begin sc_i <= 3'd0; sc_first <= 1'b0; st <= S_SC0; end
			default: st <= S_LP0;
		endcase
	end

	// ---- primitiva DMA (nb1414m4.cpp:73-86) ------------------------------
	S_DMA0: if (d_i == size_r)    st <= S_DMAE;
	        else if (skip18)      d_i <= d_i + 11'd1;
	        else begin rom_addr <= src_r + {3'd0, d_i}; st <= S_DMA1; end
	S_DMA1: st <= S_DMA2;
	S_DMA2: begin
		vram_addr <= dst_i[10:0];
		vram_din  <= cond_r ? rom_data : 8'h20;
		vram_we   <= 1'b1;
		rom_addr  <= src_r + {3'd0, size_r} + {3'd0, d_i};
		st        <= S_DMA3;
	end
	S_DMA3: st <= S_DMA4;
	S_DMA4: begin
		vram_addr <= dst_i[10:0] + 11'h400;
		vram_din  <= cond_r ? rom_data : data13;
		vram_we   <= 1'b1;
		d_i       <= d_i + 11'd1;
		st        <= S_DMA0;
	end
	// fine della DMA: se e' dentro OP_LOOP si ricomincia 0x20 celle piu' in la'
	S_DMAE: if (in_loop && ((loop_i + 4'd1) < u_n)) begin
			loop_i <= loop_i + 4'd1;
			dst    <= dst + 14'h20;
			st     <= S_LP0;
		end else st <= S_NEXT;

	// ---- OP_LOOP: prepara una copia da 3 byte (nb1414m4.cpp:289-297) -----
	S_LP0: begin
		src_r  <= 14'h0310 + (loop_on ? 14'd6 : 14'd0);
		size_r <= 11'd3;
		cond_r <= 1'b1;
		d_i    <= 11'd0;
		st     <= S_DMA0;
	end

	// ---- primitiva PUT: un carattere, e la palette se il microcodice la da'
	S_PUT0: begin
		vram_addr <= put_a;
		vram_din  <= tile_r;
		vram_we   <= 1'b1;
		rom_addr  <= u_pal;
		st        <= S_PUT1;
	end
	S_PUT1: st <= S_PUT2;
	S_PUT2: begin
		// nel service mode la palette non si tocca (nb1414m4.cpp:251, 269-283):
		// li' il microcodice lascia u_pal a zero e si scrive solo il carattere.
		if (|u_pal) begin
			vram_addr <= put_a + 11'h400;
			vram_din  <= rom_data;
			vram_we   <= 1'b1;
		end
		st <= S_NEXT;
	end

	// ---- primitiva SCORE, punteggio BCD (nb1414m4.cpp:156-184) -----------
	// Le cifre 0..5 vengono dai nibble di vram[(i/2)+5+base*3], letti VIVI: le
	// scritture del punteggio stesso non hanno il filtro dei 18 byte e con una
	// destinazione bassa cambierebbero cio' che le cifre dopo leggono.
	S_SC0: begin
		vram_addr <= {9'd0, sc_i[2:1]} + (u_base2 ? 11'd8 : 11'd5);
		rom_addr  <= 14'h010f + (u_base2 ? 14'h1c : 14'd0) + {11'd0, sc_i};
		st        <= S_SCA;
	end
	S_SCA: st <= S_SCB;
	S_SCB: begin
		if (sc_i == 3'd6)
			tile_r <= (sc_prev5 == 8'h20) ? 8'h20 : 8'h30;
		else if (sc_i == 3'd7)
			tile_r <= 8'h30;
		else begin
			// res = (vram[...] >> (i pari ? 4 : 0)) & 0xf
			if (sc_i[0]) begin
				if (sc_first || (vram_dout[3:0] != 4'd0)) begin
					tile_r <= {4'h3, vram_dout[3:0]}; sc_first <= 1'b1;
				end else tile_r <= 8'h20;
			end else begin
				if (sc_first || (vram_dout[7:4] != 4'd0)) begin
					tile_r <= {4'h3, vram_dout[7:4]}; sc_first <= 1'b1;
				end else tile_r <= 8'h20;
			end
		end
		st <= S_SC1;
	end
	S_SC1: st <= S_SC2;
	S_SC2: begin
		vram_addr <= dst[10:0] + {8'd0, sc_i};
		vram_din  <= tile_r;
		vram_we   <= 1'b1;
		if (sc_i == 3'd5) sc_prev5 <= tile_r;   // serve alla cifra 6
		st <= S_SC3;
	end
	S_SC3: begin
		vram_addr <= dst[10:0] + {8'd0, sc_i} + 11'h400;
		vram_din  <= rom_data;
		vram_we   <= 1'b1;
		sc_i      <= sc_i + 3'd1;
		st        <= (sc_i == 3'd7) ? S_NEXT : S_SC0;
	end

	// ---- comando 0x0200 (nb1414m4.cpp:186-212) ---------------------------
	S_C20A: begin
		in_game <= cmd[7];
		// stesso comando entro un frame: si ignora, altrimenti la schermata di
		// continue di Ninja Emaki viene cancellata subito dopo essere disegnata
		if ((prev0200 == {8'd0, cmd[7:0] & 8'h87}) &&
		    ((frame_cnt - prev0200_frame) <= 8'd1)) st <= S_IDLE;
		else begin
			prev0200       <= {8'd0, cmd[7:0] & 8'h87};
			prev0200_frame <= frame_cnt;
			// indice = (mcu_cmd & 0xf) DOPO la maschera 0x87, quindi solo i
			// bit 2-0: il bit 3 se lo mangia la maschera (nb1414m4.cpp:353, 201)
			rom_addr       <= 14'h0330 + {10'd0, cmd[2:0], 1'b0};
			st             <= S_C20B;
		end
	end
	S_C20B: st <= S_C20C;
	S_C20C: begin
		ptr_hi   <= rom_data;
		rom_addr <= 14'h0330 + {10'd0, cmd[2:0], 1'b0} + 14'd1;
		st       <= S_C20D;
	end
	S_C20D: st <= S_C20E;
	S_C20E: begin dst <= {ptr_hi[5:0], rom_data}; st <= S_C20F; end
	S_C20F: if (|dst[10:0]) begin
			rom_addr <= dst;                     // fill: tile e palette da rom[dst]
			st       <= S_C20G;
		end else begin
			src_r  <= dst;                       // copia di pagina intera
			dst    <= 14'd0;
			size_r <= 11'd1024;
			cond_r <= 1'b1;
			d_i    <= 11'd0;
			in_loop<= 1'b0;
			st     <= S_DMA0;
		end
	S_C20G: st <= S_C20H;
	S_C20H: begin tile_r <= rom_data; rom_addr <= dst + 14'd1; st <= S_C20I; end
	S_C20I: st <= S_C20J;
	S_C20J: begin pal_r <= rom_data; f_i <= 11'd0; st <= S_FIL0; end

	// ---- primitiva FILL (nb1414m4.cpp:88-100) ----------------------------
	S_FIL0: st <= S_FIL1;
	S_FIL1: if (f_i == 11'd1024)  st <= S_NEXT;
	        else if (f_i < 11'd18) f_i <= f_i + 11'd1;
	        else begin
			vram_addr <= f_i;
			vram_din  <= tile_r;
			vram_we   <= 1'b1;
			st        <= S_FIL2;
		end
	S_FIL2: begin
		vram_addr <= f_i + 11'h400;
		vram_din  <= pal_r;
		vram_we   <= 1'b1;
		f_i       <= f_i + 11'd1;
		st        <= S_FIL1;
	end

	default: st <= S_IDLE;
	endcase
end

endmodule
