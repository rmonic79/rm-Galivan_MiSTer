# SPDX-License-Identifier: GPL-3.0-or-later
# This file is part of rmGalivan_MiSTer.
# Author: Umberto Parisi (rmonic79)

derive_pll_clocks
derive_clock_uncertainty

# core specific constraints — rmGalivan (import da DJ Boy, tenuto solo il generico)

# ============================================================
# OSD HDMI (framework sys/osd.v): gp_outr (strobe HPS, dominio h2f) -> osd|bcnt (blanking
# counter dell'OSD, dominio video). Crossing HPS->OSD di CONFIG (non timing-critico).
set_false_path -from [get_registers {*gp_outr*}] -to [get_registers {*_osd|bcnt*}]

# CONFIG/STATUS HPS -> core (async, statici durante il gioco). Cambiano solo quando
# l'utente tocca l'OSD: crossing async, NON path runtime.
set_false_path -from [get_registers {*hps_io|status*}]
set_false_path -from [get_registers {*gp_outr*}] -to [get_registers {*cfg_custom*}]

# FALSE_PATH dal reset globale: reset_hold_cnt pilota SOLO `wire reset`, quasi-statico
# (decrementa al boot, poi 0 per sempre). Nessun requisito setup single-cycle.
set_false_path -from [get_registers {*reset_hold_cnt[*]}]

# ============================================================
# SAVESTATE — multicycle CONFINATI, mai a coperta.
#
# Correzione 2026-09-07. Prima c'erano due dichiarazioni `-from` SENZA `-to`:
#
#   set_multicycle_path -hold -from [get_registers {*u_save_state|*}] 7
#   set_multicycle_path -hold -from [get_registers {*memory_stream|*}] 7
#
# Un `-from` senza `-to` copre OGNI path che esce da quei registri, compresi
# quelli che finiscono nella logica di gioco. Su quelli l'`-hold 7` e' FALSO e
# autorizza il fitter a skewarli: e' esattamente il pattern che la nota qui
# sotto (2026-07-25) dice di non ripetere, e che su Act-Fancer dava STA verde e
# core che non parte.
#
# Ora i multicycle sono chiusi dentro il sotto-sistema savestate: sorgente E
# destinazione devono stare li'. Lo stream save/load avanza solo durante
# save/restore, a gioco fermo, quindi dentro quel recinto il multicycle e' vero.
set_multicycle_path -setup \
	-from [get_registers {*u_save_state|* *memory_stream|* *u_ss_ddr_gate|* *u_ss_mgr|*}] \
	-to   [get_registers {*u_save_state|* *memory_stream|* *u_ss_ddr_gate|* *u_ss_mgr|*}] 8
set_multicycle_path -hold \
	-from [get_registers {*u_save_state|* *memory_stream|* *u_ss_ddr_gate|* *u_ss_mgr|*}] \
	-to   [get_registers {*u_save_state|* *memory_stream|* *u_ss_ddr_gate|* *u_ss_mgr|*}] 7

# RIMOSSO 2026-09-07 — il vincolo sugli adaptor:
#   set_multicycle_path ... -from [get_registers {*_ss_adaptor|word_wr* ...}] 3/2
# Agganciava i registri word_wr/word_idx di `auto_save_lean_adaptor`, che era il
# lean adaptor del framework savestate di Darius. Qui il framework e' quello di
# Raiden, che il lean adaptor NON ce l'ha: il core usa `auto_save_adaptor`
# (caricamento a blocco unico), che quei registri non li ha. Verificato: in
# rtl/ss/ non esiste nessun word_wr ne' word_idx. Era una regola che non
# agganciava piu' niente.

# ============================================================
# MULTICYCLE CPU/AUDIO RIMOSSI 2026-07-25 — sospetti del boot rotto.
# I blocchi `-from X -to X` a coperta su tutta l'istanza (Z80 x3, BEAST) e il
# `-to *jt12_pg*` includevano anche i path in cui launch/latch NON sono entrambi
# cen-gated: su quelli l'-hold 7 e' FALSO e autorizza il fitter a skewarli ->
# boot instabile (pattern verificato Act-Fancer: MC falso = core non parte, STA
# verde bugiardo). Il timing negativo che ne risulta NON e' un fault (regola
# utente: timing negativo != core rotto). Se servira' chiudere il timing, andranno
# dichiarati MC MIRATI ai SOLI registri cen-gated verificati, MAI a coperta, MAI
# -hold su path con endpoint a clk pieno.
# Restano solo i multicycle savestate (sopra), veri per costruzione.

# CPU — multicycle CONFINATO dentro ciascun Z80, stessa regola del blocco sopra:
# sorgente E destinazione devono stare nella stessa CPU.
#
# Perche' e' VERO e non una pezza. I due Z80 sono istanziati con clock enable e
# avanzano solo quando l'enable e' alto:
#   main  ce_main = 96 MHz / 16  ->  un colpo ogni 16 periodi di clock
#   sound ce_snd  = 96 MHz / 24  ->  un colpo ogni 24
# Un percorso che parte da un registro della CPU e finisce in un altro registro
# della STESSA CPU viene quindi lanciato su un fronte abilitato e catturato sul
# fronte abilitato DOPO: ha a disposizione 16 (o 24) periodi, non uno. L'SDC
# senza questa dichiarazione lo valuta a ciclo singolo, e segnala come
# violazione un percorso che a runtime ha sedici volte il tempo che gli serve.
#
# Il valore e' 2, non 16: basta e avanza (raddoppia la finestra, +10.4 ns su uno
# sforamento di 0.23 ns) e resta vero anche nel caso peggiore immaginabile di un
# enable 1-su-2. Alzarlo darebbe al fitter licenza di skeware molto piu' di
# quanto serva.
#
# ATTENZIONE: entrambi gli estremi sono vincolati. Un `-from` senza `-to`
# coprirebbe anche i percorsi che ESCONO dalla CPU verso la logica di gioco —
# bus dati, indirizzi, strobe — che NON sono a ciclo multiplo, e sarebbe lo
# stesso errore descritto sopra per il savestate.
set_multicycle_path -setup \
	-from [get_registers {*u_main|tv80s:u_cpu|* *u_sound|tv80s:u_cpu|*}] \
	-to   [get_registers {*u_main|tv80s:u_cpu|* *u_sound|tv80s:u_cpu|*}] 2
set_multicycle_path -hold \
	-from [get_registers {*u_main|tv80s:u_cpu|* *u_sound|tv80s:u_cpu|*}] \
	-to   [get_registers {*u_main|tv80s:u_cpu|* *u_sound|tv80s:u_cpu|*}] 1
