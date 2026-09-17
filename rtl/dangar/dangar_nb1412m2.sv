// SPDX-License-Identifier: GPL-3.0-or-later
/*  This file is part of rmGalivan_MiSTer.
    Author: Umberto Parisi (rmonic79)

    dangar_nb1412m2.sv — Nichibutsu NB1412M2, la protezione di `dangarj`.

    Sta su una scheda figlia DG-3 insieme a un quarzo da 8 MHz e a una ROM da
    8 KB (regione `prot_chip`, galivan.cpp ROM_START(dangarj)). Il main lo vede
    su DUE sole porte, aggiunte a quelle di Galivan (galivan.cpp:766-770):

        0x81  W   comando: latcha l'indirizzo di un registro INTERNO al chip
        0x80  R/W dato:    legge/scrive il registro selezionato dal comando

    Riferimento: mame/nichibutsu/nb1412m2.cpp (Angelo Salese). Il chip fa tre
    mestieri — decrypter, timer e controllo DAC — ma timer e DAC li usa solo
    Mighty Guy sulla sua CPU audio. Dangar usa SOLO il decrypter, quindi qui
    c'e' solo quello: i registri di timer/DAC non sono modellati.

    REGISTRI INTERNI (nb1412m2.cpp:90-115, la nb1412m2_map)
      0x32  W   rom_op        comando di operazione. 5 = "carica il risultato".
                              Il valore non cambia il calcolo: si latcha e basta.
      0x33  W   rom_address   byte ALTO  (offset 0 = hi, nb1412m2.cpp:229-231)
      0x34  W   rom_address   byte BASSO
      0x35  W   adj_address   byte ALTO
      0x36  W   adj_address   byte BASSO
      0x37  R   risultato del decrypter
      0x90  R/W latch (const90)
      0x92  R/W latch
      0x94  R/W latch
      0xA0..0xA3 R/W latch (due registri a 16 bit)

    IL DECRYPTER (nb1412m2.cpp:256-272)

        prot_adj = (0x43 - rom[adj_address]) & 0xff
        risultato = rom[rom_address & 0x1fff] - prot_adj

    Tutta l'aritmetica e' a 8 bit e wrappa, come gli uint8_t di MAME. Il
    commento del sorgente spiega il perche' del 0x43: la somma fra la voce di
    aggiustamento e il valore atteso fa sempre 0x143.

    NOTA sulla maschera: MAME maschera & 0x1fff solo rom_address e lascia
    adj_address nudo. Qui sono mascherati tutti e due, perche' la ROM e' di
    8 KB e un indirizzo fuori range in RTL non "non succede", legge un'altra
    cella. Il gioco non ci va mai fuori, quindi il comportamento e' identico.

    PERCHE' UN CONTATORE A 4 STATI

    Il calcolo vuole DUE letture dalla stessa ROM, ma la BRAM ha una porta di
    scrittura (download ioctl) e una di lettura: tre accessi non stanno in un
    M10K (vedi il commento in testa a dangar_mem.sv). Quindi le due letture si
    alternano su un contatore libero e il risultato resta in un registro.

    Non serve nessun trigger: il giro completo dura 4 cicli di clk (~42 ns a
    96 MHz), mentre fra l'ultima scrittura dell'indirizzo e la lettura della
    porta 0x80 il Z80 spende un OUT intero piu' un IN, centinaia di cicli. Il
    registro e' sempre gia' aggiornato quando la CPU lo legge.

    Contratto della ROM: indirizzo al ciclo T, dato al ciclo T+1 — lo stesso di
    tutti gli altri clienti in BRAM del core.
*/

module dangar_nb1412m2
(
	input             clk,
	input             reset,

	// porte del main: strobe di scrittura gia' decodificati dal chiamante
	input             cmd_wr,      // scrittura su 0x81
	input             dat_wr,      // scrittura su 0x80
	input       [7:0] din,
	output reg  [7:0] dout,        // lettura di 0x80 (combinatoria sul comando)

	// ROM DG-3 da 8 KB
	output reg [12:0] rom_addr,
	input       [7:0] rom_data
);

// ---------------------------------------------------------------------------
// Comando: e' l'indirizzo del registro interno su cui agisce la porta 0x80.
// nb1412m2.cpp:  command_w -> m_command ;  data_r/data_w -> space[m_command]
// ---------------------------------------------------------------------------
reg [7:0] cmd;

always @(posedge clk) begin
	if (reset)      cmd <= 8'h00;
	else if (cmd_wr) cmd <= din;
end

// ---------------------------------------------------------------------------
// Registri interni
// ---------------------------------------------------------------------------
reg [7:0]  rom_op;
reg [15:0] rom_address;
reg [15:0] adj_address;
reg [7:0]  const90, lat92, lat94;
reg [7:0]  latA0, latA1, latA2, latA3;

always @(posedge clk) begin
	if (reset) begin
		rom_op      <= 8'h00;
		rom_address <= 16'h0000;
		adj_address <= 16'h0000;
		const90     <= 8'h00;
		lat92       <= 8'h00;
		lat94       <= 8'h00;
		latA0       <= 8'h00;
		latA1       <= 8'h00;
		latA2       <= 8'h00;
		latA3       <= 8'h00;
	end
	else if (dat_wr) begin
		case (cmd)
			8'h32: rom_op              <= din;
			8'h33: rom_address[15:8]   <= din;   // offset 0 = byte alto
			8'h34: rom_address[7:0]    <= din;
			8'h35: adj_address[15:8]   <= din;
			8'h36: adj_address[7:0]    <= din;
			8'h90: const90             <= din;
			8'h92: lat92               <= din;
			8'h94: lat94               <= din;
			8'hA0: latA0               <= din;
			8'hA1: latA1               <= din;
			8'hA2: latA2               <= din;
			8'hA3: latA3               <= din;
			default: ;                            // timer e DAC: non modellati
		endcase
	end
end

// ---------------------------------------------------------------------------
// Decrypter: due letture alternate sulla stessa porta di lettura.
//
//   fase 0: cattura rom[rom_address] -> risultato, e presenta adj_address
//   fase 1: indirizzo adj stabile: la BRAM registra il dato a fine fase
//   fase 2: cattura rom[adj_address], e presenta rom_address
//   fase 3: indirizzo rom stabile: la BRAM registra il dato a fine fase
//
// Il contratto della BRAM e' indirizzo al ciclo T, dato al ciclo T+1: se
// l'indirizzo viene scritto a fine fase 0 e' stabile DURANTE la fase 1, e il
// dato si legge nella fase 2. Da qui lo sfasamento delle catture.
//
// adj_val catturato in fase 2 e rom_data catturato in fase 0 del giro dopo
// vengono dalla stessa coppia di indirizzi: il risultato e' coerente.
// ---------------------------------------------------------------------------
// TIMING: le due sottrazioni di MAME sono in serie. Qui la prima si fa gia'
// nella fase 2, quando il dato di adj arriva, e resta in un registro: nella
// fase 0 ne resta UNA sola sulla strada verso `result`.
reg [1:0] phase;
reg [7:0] prot_adj;
reg [7:0] result;

always @(posedge clk) begin
	if (reset) begin
		phase    <= 2'd0;
		prot_adj <= 8'h43;
		result   <= 8'h00;
		rom_addr <= 13'd0;
	end
	else begin
		phase <= phase + 2'd1;
		case (phase)
			2'd0: begin
				result   <= rom_data - prot_adj;    // rom[rom_address] - prot_adj
				rom_addr <= adj_address[12:0];
			end
			2'd1: ;                                 // indirizzo adj stabile
			2'd2: begin
				prot_adj <= 8'h43 - rom_data;       // (0x43 - rom[adj_address])
				rom_addr <= rom_address[12:0];
			end
			2'd3: ;                                 // indirizzo rom stabile
		endcase
	end
end

// ---------------------------------------------------------------------------
// Lettura della porta 0x80.
//
// TIMING: REGISTRATA, non combinatoria. Il chiamante la infila in `io_dout`,
// che e' gia' una catena combinatoria fino al bus dati della CPU: aggiungerci
// un'altra case a otto vie allungherebbe il percorso critico per niente.
// `cmd` e i latch sono fermi da centinaia di cicli quando la CPU legge, quindi
// un ciclo di ritardo qui non e' osservabile.
// ---------------------------------------------------------------------------
always @(posedge clk) begin
	case (cmd)
		8'h37:   dout <= result;
		8'h90:   dout <= const90;
		8'h92:   dout <= lat92;
		8'h94:   dout <= lat94;
		8'hA0:   dout <= latA0;
		8'hA1:   dout <= latA1;
		8'hA2:   dout <= latA2;
		8'hA3:   dout <= latA3;
		default: dout <= 8'hFF;
	endcase
end

endmodule
