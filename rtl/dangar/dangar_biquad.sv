// SPDX-License-Identifier: GPL-3.0-or-later
/*  This file is part of rmGalivan_MiSTer.
    Author: Umberto Parisi (rmonic79)

    dangar_biquad.sv — un passa-basso Sallen-Key della PCB, in forma digitale.

    Sulla scheda di Dangar ci sono TRE filtri attivi a 2 poli (galivan.cpp:1211-1219,
    FILTER_BIQUAD ... opamp_sk_lowpass_setup). Sono Sallen-Key a guadagno unitario:

        fc = 1 / (2*pi*sqrt(R1 R2 C1 C2))      Q = sqrt(R1 R2 C1 C2) / (C2 (R1+R2))

      filtro       R      C1      C2        fc          Q      peso nel mix
      ymfilter     4.7k   3.3nF   1.0nF   18640.8 Hz   0.908   0.4922
      dacfilter1  10.0k  10.0nF   4.7nF    2321.5 Hz   0.729   0.2095
      dacfilter2  10.0k  10.0nF   4.7nF    2321.5 Hz   0.729   0.2983

    Quello del YM taglia a 18.6 kHz: e' solo anti-alias e quasi non si sente.
    Quelli dei due DAC tagliano a 2.3 kHz e NON sono un dettaglio: i due R2R suonano
    voci e percussioni campionate, e senza quel taglio escono metalliche e piene di
    alias. E' il filtro che da' il timbro alla scheda.

    Realizzazione: biquad in forma diretta I, coefficienti da trasformata bilineare
    CON pre-warping a fs = 96 MHz / 1728 = 55555.6 Hz, che e' il rate a cui esce il
    YM3526 (jtopl_div W=2 -> cen/4, 18 slot -> un campione ogni 72 cen = 4e6/72).
    Campionare piu' lentamente della sorgente sarebbe decimazione senza anti-alias.

        y[n] = b0 x[n] + b1 x[n-1] + b2 x[n-2] - a1 y[n-1] - a2 y[n-2]

    Coefficienti in Q2.14 passati come parametri: il modulo e' generico, i valori
    stanno dove si vedono accanto ai componenti da cui derivano. Verificato che i
    poli stiano dentro il cerchio unitario (moduli 0.835 e 0.598) e che il guadagno
    in continua resti 1.00000 per entrambi.
*/

`timescale 1ns / 1ps

module dangar_biquad #(
	parameter signed [17:0] B0 = 0,
	parameter signed [17:0] B1 = 0,
	parameter signed [17:0] B2 = 0,
	parameter signed [17:0] A1 = 0,     // gia' normalizzati su a0
	parameter signed [17:0] A2 = 0
) (
	input                     clk,
	input                     reset,
	input                     ce,       // 55555.6 Hz
	input  signed      [15:0] din,
	output signed      [15:0] dout
);

localparam FRAC = 14;

// =====================================================================
// TRE STADI, non uno.
//
// Il calcolo completo (cinque prodotti, albero di somme a 40 bit, troncamento
// in magnitudine, saturazione) in un solo ciclo da 10.4 ns non ci sta: misurato
// -8.1 ns di slack, con il percorso peggiore din -> y1. Ma questo filtro lavora
// una volta ogni 1728 cicli (ce_aud a 55555.6 Hz su clk a 96 MHz), quindi di
// tempo ce n'e' in abbondanza: basta spezzarlo.
//
//   stadio 0 (su ce) : campiona l'ingresso e calcola i cinque prodotti
//   stadio 1         : somma
//   stadio 2         : tronca, satura, fa scorrere lo stato
//
// Il risultato numerico e' identico a prima, solo disponibile due cicli dopo su
// 1728: nessun effetto udibile e nessun cambio di comportamento. I prodotti
// usano x1/x2/y1/y2 PRIMA che scorrano allo stadio 2, che e' l'ordine giusto.
// =====================================================================

reg signed [15:0] x1, x2, y1, y2;
reg signed [15:0] y;
reg signed [15:0] din_l;                       // ingresso campionato sul ce
reg signed [33:0] p_b0, p_b1, p_b2, p_a1, p_a2;
reg signed [39:0] acc;
reg        [1:0]  st;

// troncamento in MAGNITUDINE (verso zero) sull'accumulatore GIA' registrato.
//
// `acc[39:FRAC]` da solo e' uno shift aritmetico: tronca verso -infinito, quindi
// l'errore che introduce ha media -0.5 LSB invece di 0. In un IIR quell'errore
// rientra nel feedback moltiplicato per il guadagno di anello 1/(1+a1+a2), che
// per il filtro dei DAC vale ~17. Misurato sul modello bit-esatto: dopo un
// impulso l'uscita NON torna a zero, si ferma a -12 e ci resta. E' un limit
// cycle, cioe' un offset che non se ne va piu'.
//
// Troncando in magnitudine l'errore diventa a media nulla e il ciclo sparisce
// (verificato: coda 0/0 su entrambi i filtri, guadagno DC 0.9995 e 1.0000).
// Il semplice arrotondamento NON basta, si ferma a +5; ne' aiuta aggiungere bit
// di stato, con 4 bit extra il ciclo resta.
wire signed [39:0] acc_abs  = acc[39] ? -acc : acc;
wire        [25:0] scal_abs = acc_abs[39:FRAC];
wire signed [26:0] scal_pos = $signed({1'b0, scal_abs});
wire signed [26:0] scal     = acc[39] ? -scal_pos : scal_pos;

// saturazione all'uscita: i poli sono stabili, ma un transitorio all'accensione
// non deve poter far girare il valore attorno.
wire signed [15:0] sat = (scal >  27'sd32767) ?  16'sd32767 :
                         (scal < -27'sd32768) ? -16'sd32768 : scal[15:0];

always @(posedge clk) begin
	if (reset) begin
		x1 <= 0; x2 <= 0; y1 <= 0; y2 <= 0; y <= 0;
		din_l <= 0; acc <= 0; st <= 2'd0;
		p_b0 <= 0; p_b1 <= 0; p_b2 <= 0; p_a1 <= 0; p_a2 <= 0;
	end else begin
		case (st)
		2'd0: if (ce) begin
			din_l <= din;
			p_b0  <= B0 * din;
			p_b1  <= B1 * x1;
			p_b2  <= B2 * x2;
			p_a1  <= A1 * y1;
			p_a2  <= A2 * y2;
			st    <= 2'd1;
		end
		2'd1: begin
			acc <= {{6{p_b0[33]}}, p_b0} + {{6{p_b1[33]}}, p_b1} + {{6{p_b2[33]}}, p_b2}
			     - {{6{p_a1[33]}}, p_a1} - {{6{p_a2[33]}}, p_a2};
			st  <= 2'd2;
		end
		2'd2: begin
			x2 <= x1;
			x1 <= din_l;
			y2 <= y1;
			y1 <= sat;
			y  <= sat;
			st <= 2'd0;
		end
		default: st <= 2'd0;
		endcase
	end
end

assign dout = y;

endmodule
