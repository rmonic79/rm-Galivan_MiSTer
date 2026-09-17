# Youma Ninpou Chou, bootleg Game Electronics — l'hardware che MAME non emula

Analisi del codice Z80 dei set `youmab` e `youmab2`, che MAME marca
`MACHINE_NOT_WORKING | MACHINE_UNEMULATED_PROTECTION` con la nota *"player is
invincible"*.

Tutto quello che segue è **letto dal codice**, non dedotto dal comportamento.
Lo strumento e' un disassemblatore Z80 scritto apposta, con un
tracciatore di flusso che parte dai vettori e segue salti e chiamate, così le
istruzioni di I/O che riporta sono istruzioni vere e non byte `DB nn` capitati
dentro i dati — la scansione grezza dava oltre cento porte, quasi tutte false.

---

## Il punto di partenza

Il bootleg ha **tolto il chip NB1414M4** (il blitter del layer testo) e l'ha
sostituito con codice proprio, in una ROM da 32 KB (`electric2.3t`) bancata a
`0x8000-0xBFFF` dalla porta `0x82`. MAME lo riflette così
(`galivan.cpp`, `youmab_state::youmab`):

```cpp
ninjemak(config);
m_maincpu->set_addrmap(AS_PROGRAM, &youmab_state::main_map);
m_maincpu->set_addrmap(AS_IO,      &youmab_state::io_map);
config.device_remove("nb1414m4");
```

e delle porte nuove ne ha capite solo alcune. Restano dichiarate ignote:

```cpp
void youmab_state::_81_w(uint8_t data) { /* ?? */ }
uint8_t youmab_state::_8a_r()          { return machine().rand(); }
```

---

## Mappa delle porte, dal codice tracciato

Solo istruzioni raggiunte seguendo il flusso.

| Porta | Verso | Dove | Cosa fa |
|---|---|---|---|
| `0x00` | R/W | `electric2.3t`, `electric3.3r` | **letta e usata per calcolare un salto**; ci si scrive `0x03`, `0xFF`, `0x0B`, `0x0E` |
| `0x01` | R/W | `electric2.3t` | bit 3 letto come stato; ci si scrive `0x03`, `0x00`, `0x0B`, `0x0E` |
| `0x88` | R | `electric2.3t` | letta due volte, arma la misura di `0x8A` |
| `0x8A` | R | `electric2.3t` | **bit 3 = segnale periodico**, più una sorgente casuale |
| `0x81` | W | `electric2.3t` | riceve un seme pseudo-casuale |
| `0x83` | W | `electric2.3t` | sull'originale è il SERVICE in lettura; qui ci si **scrive** |
| `0xFC` | R | `electric2.3t` | letta prima del blocco pseudo-casuale |

---

## 1. La misura di tempo su `0x8A` — non è un valore, è una frequenza

Nel banco extra, a `$8843` (offset file `0x4843`):

```
883C  LD A,($FFF6)
883F  CP $24
8841  JR NC,$8890      ; gia' passato: salta tutto

8843  IN A,($88)       ; arma
8845  IN A,($8A)
8847  BIT 3,A
8849  JR Z,$8845       ; aspetta che il bit 3 SALGA

884B  IN A,($88)
884D  LD HL,$0000
8850  IN A,($8A)       ; --- ciclo di misura ---
8852  BIT 3,A
8854  JR NZ,$885E      ; esce quando il bit 3 SCENDE
8856  INC HL
8857  BIT 7,H
8859  JR Z,$8850       ; guardia: al massimo 0x8000 giri
885B  JP $AAA0         ; timeout -> errore

885E  LD BC,$00F0
8863  SBC HL,BC
8865  JR C,$885B       ; conteggio < 0xF0  -> errore
8868  LD BC,$0110
886C  SBC HL,BC
886E  JR NC,$885B      ; conteggio >= 0x110 -> errore
```

Il gioco **conta quanto dura la semionda alta** del bit 3 e pretende un
conteggio fra **0xF0 e 0x10F**, cioè 240..271 giri.

Nessuna costante può superare questo controllo, e nemmeno un valore casuale:
con `machine().rand()` il bit 3 cambia a ogni lettura e il conteggio esce
intorno a 2. **Serve un'onda quadra.**

### Il periodo, ricavato dai cicli di clock

Il ciclo di misura è sei istruzioni:

| | T-state |
|---|---|
| `IN A,($8A)` | 11 |
| `BIT 3,A` | 8 |
| `JR NZ` non preso | 7 |
| `INC HL` | 6 |
| `BIT 7,H` | 8 |
| `JR Z` preso | 12 |
| **totale** | **52** |

Il main gira a 6 MHz (12 MHz / 2), quindi un giro dura 8,667 µs.

| | giri | tempo |
|---|---|---|
| minimo accettato | 240 | 2,080 ms |
| massimo accettato | 271 | 2,349 ms |
| centro | 256 | 2,219 ms |

La semionda deve durare circa **2,2 ms**, cioè un'onda quadra da circa
**226 Hz** con duty 50%. Con 8 bit di margine la tolleranza è ±6%, quindi non
serve un valore esatto: un divisore qualsiasi che cada dentro la finestra va
bene.

---

## 2. Cosa succede se fallisce — il gioco lo scrive a schermo

`$AAA0` carica un puntatore a un messaggio, lo stampa con la stessa routine
usata per gli altri testi (`CALL $D645`), poi `DI`, scrive `0x30` sulla porta
`0x80` (bit 4 = sfondo spento) e si ferma.

I due messaggi, letti dalla ROM:

| Indirizzo | Testo |
|---|---|
| `$AA09` | `   IC 44  ` |
| `$AAB8` | `   IC 46 ` |

È un **autotest della scheda che dichiara quale integrato è guasto**. IC 44 e
IC 46 sono i due componenti che generano il segnale su `0x8A`.

---

## 3. È un test una volta sola

Il flag sta in `$FFF6`:

- `$883C`: se `$FFF6 >= 0x24` la misura si salta del tutto
- `$8889`: superato il test, scrive `0x24` e non lo rifà più

Dopo la misura, prima di segnare il flag:

```
8870  IN A,($01)
8872  BIT 3,A
8874  JR NZ,$8879
8876  JR $8870        ; aspetta il bit 3 anche qui
8879  LD A,$03 ; OUT ($00),A
887D  LD A,$FF ; OUT ($00),A
8881  LD A,$03 ; OUT ($01),A
8885  LD A,$00 ; OUT ($01),A
8889  LD ($FFF6),$24
```

Quindi **anche la porta `0x01` ha un bit 3 di stato** che deve salire, e le
porte `0x00`/`0x01` ricevono una sequenza di configurazione.

---

## 4. La porta `0x00` decide dove salta il programma — RISOLTA

> **Esito**: la porta deve restituire un valore con i **bit 3 e 4 a zero**.
> Sotto c'e' la dimostrazione, che non e' piu' una deduzione.
>
> `$DB39` — il bersaglio che si ottiene con quei bit a zero — non e' spazzatura
> come sembrava leggendo i byte: e' `RST $30`, cioe'
> `POP HL; RST $28; EX DE,HL; JP (HL)`. E `RST $28` e'
> `ADD A,A; RST $18; LD E,(HL); INC HL; LD D,(HL)`.
>
> Messi insieme: `POP HL` prende l'indirizzo **subito dopo** l'istruzione, che
> e' quindi un puntatore a dati in linea; `A` — che il `POP AF` della routine
> ha appena riempito col parametro del chiamante — viene raddoppiato e usato
> come indice; si legge una parola da quella tabella e ci si salta.
> **`$DB39` e' un dispatcher a tabella**, e i nove chiamanti trovati al capitolo
> precedente sono i nove indici.
>
> La prova finale e' nella tabella stessa, che sta a `$DB3A`:
> `$8765, $8A32, $8B90, $9410, $A011, $9123, $A321, $A120…` — tutti indirizzi
> in `0x8000-0xBFFF`, **il banco extra che lo stub ha appena inserito** con
> `OUT ($82),$FF` due istruzioni prima. A `$8765` del banco 1 c'e' codice vero.
> Gli altri tre bersagli cadono su dati.
>
> Percio' l'errore di prima era di metodo: avevo cercato **un banco in cui tutti
> e quattro i bersagli fossero validi**, mentre ne serve valido **uno solo** —
> quello che l'hardware seleziona. Gli altri tre sono trappole, per costruzione.

## 4bis. Come stava la voce prima (deduzione, poi confermata)

**Correzione di indirizzi.** `electric3.3r` sta a `0x10000` del `maincpu`, cioe'
nella finestra bancata `0xC000-0xDFFF` a banchi da 8 KB. Una prima lettura
l'aveva mappata a `0x8000`, sbagliando gli indirizzi di 0x2000: il codice qui
sotto e' a **`$DC01` nel banco 3**, non a `$BC01`. Le istruzioni erano giuste,
gli indirizzi no.

```
DC01  LD A,($FFF6)
DC04  OR A
DC05  JR NZ,$DC2A          ; flag gia' toccato -> ramo B
DC07  LD A,$03 ; OUT ($00),A ; OUT ($00),A
DC0D  LD A,$0B ; OUT ($01),A
DC11  LD A,$0E ; OUT ($01),A
DC15  LD ($FFF6),A         ; flag = 0x0E

DC18  IN A,($00)           ; <<< la porta
DC1A  AND $18              ; solo i bit 3 e 4
DC1C  ADD A,$FC
DC1E  LD L,A ; LD H,$DB    ; HL = 0xDBxx
DC21  POP DE ; POP AF      ; butta via due indirizzi di ritorno
DC23  PUSH HL
DC24  LD BC,$FF3D ; ADD HL,BC
DC28  PUSH HL
DC29  RET                  ; salta all'ultimo spinto

DC2A  LD HL,$FFF6
DC2D  LD A,(HL)
DC2E  CP $23
DC30  JR NC,$DC1A          ; flag >= 0x23: calcola dal FLAG, senza leggere la porta
DC32  INC (HL)
DC33  JR $DC18
```

I quattro esiti possibili:

| `IN($00) & 0x18` | salta a | ritorno a |
|---|---|---|
| `0x00` | `$DB39` | `$DBFC` |
| `0x08` | `$DA41` | `$DB04` |
| `0x10` | `$DA49` | `$DB0C` |
| `0x18` | `$DA51` | `$DB14` |

In MAME la porta non e' mappata e legge `0xFF`: `0xFF & 0x18 = 0x18`, quindi si
va **sempre** a `$DA51` e gli altri tre rami non vengono mai eseguiti. E' la
spiegazione piu' probabile del *"player is invincible"*.

### Chi la chiama, e la trappola dei due bus

`$DC01` **non e' codice morto**. Ci si arriva da uno stub a `$DB2C`:

```
DB2C  PUSH AF          ; il chiamante passa un valore in A
DB2D  LD A,$FF
DB2F  OUT ($82),A      ; banca dentro la ROM extra
DB31  CALL $DC01
DB34  RET
...
DBFC  LD A,$00 ; OUT ($82),A ; RET    ; il contrario, banca fuori
```

e quello stub ha **nove chiamanti** in banco 3 (`$D429`, `$D436`, `$D443`,
`$D44A`, `$D46E`, `$D498`, `$D627`, `$D634`, `$D69D`), ognuno della forma
`LD A,<n> / JP $DB2C`.

Il `PUSH AF` senza `POP` non e' un errore: e' proprio quello che `$DC01`
consuma con il suo `POP AF`, dopo aver tolto con `POP DE` l'indirizzo di
ritorno. Lo stack torna in pari e il `RET` finale salta dove vuole lui.

**La trappola, che mi aveva fatto sbagliare lettura**: nell'intervallo
`0xD800-0xDFFF` **la lettura e la scrittura vanno in due posti diversi**.

| Accesso | Dove finisce |
|---|---|
| lettura | la ROM bancata (`map(0xc000,0xdfff).bankr`) |
| scrittura | la **VRAM del testo** (`map(0xd800,0xdfff).w(videoram_w)`) |

Per questo `JP $DB2C` legge codice dalla ROM mentre, poco sopra, una serie di
`LD DE,$DB31 / LD BC,$0008 / LDIR` scrive otto caratteri **a schermo** allo
stesso indirizzo. Non e' una contraddizione: sono due bus.

**Cosa resta aperto.** I quattro bersagli del salto calcolato stanno tutti in
`0xD8xx-0xDBxx`, che in **lettura** e' la ROM bancata. Cercandoli nei quattro
banchi di `electric3.3r`:

| Banco | Cosa c'e' a `$DA41`/`$DA49`/`$DA51` |
|---|---|
| 0 | tutto zero |
| 1 | dati grafici (sequenze `80 5A 55 55 ...` ripetute) |
| 2 | codice vero, ma i bersagli cadono **in mezzo** alle istruzioni |
| 3 | testo: a `$DA49` c'e' la stringa `CONGRATULATIONS` |

Nessun banco da un punto d'ingresso pulito su tutti e quattro. Quindi manca un
pezzo: o il banco viene cambiato da chi chiama questa routine, o l'indirizzo
calcolato e' volutamente diverso da quello che sembra. Il prossimo passo e'
trovare **chi chiama `$DC01`** e con quale banco selezionato.

## 5. Il blocco pseudo-casuale su `0x81` / `0x8A`

A `$A773`:

```
A773  IN A,($FC)
A775  INC A
A776  LD HL,($FFF1)
A779  LD A,H ; OR L
A77B  JR NZ,$A79C
A77D  LD A,R           ; registro di refresh: seme pseudo-casuale
A780  AND $7F
A782  RRCA x4
A786  OUT ($81),A      ; <<< il seme esce dalla porta 0x81
A788  LD ($FFF3),A
...
A7BF  OUT ($81),A      ; riscrive il valore, con XOR $08
A7C2  IN A,($8A)       ; <<< rilegge
A7C4  RRCA
A7C5  AND $03
A7C7  LD L,$F5 ; ADD A,(HL) ; LD (HL),A   ; accumula in $FFF5
```

`LD A,R` è il modo classico di tirare fuori casualità su uno Z80. Il valore
esce da `0x81` e due bit rientrano da `0x8A`: le due porte sono **la stessa
periferica**, che prende un seme e restituisce bit.

Questo spiega perché `machine().rand()` su `0x8A` fa quasi funzionare il gioco
ma non del tutto: per questo blocco un valore casuale va benissimo, per la
misura di tempo del punto 1 è fatale.

---

## 6. `youmab2` — la stessa scheda, tre byte di differenza

I due set bootleg condividono **la stessa ROM del banco extra**: `electric2.3t`
di `youmab` e `2.2d` di `youmab2` hanno lo stesso CRC `99aee3bc`, e il driver
stesso lo annota (*"same as first bootleg"*). Quindi **tutto quello descritto
sopra — la misura di tempo su `0x8A`, i messaggi IC 44 / IC 46, il blocco
pseudo-casuale su `0x81` — vale identico per tutti e due**.

Le due ROM principali invece differiscono, ma pochissimo.

### `3.4d` contro `electric3.3r`: UN byte

Un byte solo, a `$DB5B` del banco 3 (offset file `0x7B5B`): `37` contro `36`,
cioe' i caratteri ASCII `7` e `6`. E' la **cifra dell'anno di copyright** nella
schermata del titolo:

| Set | Stringa nella ROM |
|---|---|
| `youmab`  | `@ 1987 GAME ELECTRONICS` |
| `youmab2` | `@ 1986 GAME ELECTRONICS` |

Tutto il resto di quella ROM, routine della porta `0x00` compresa, e'
identico byte per byte.

### `1.1d` contro `electric1.3u`: quattro byte, ed e' una tabella

A `0x181A` ci sono quattro byte consecutivi:

| Set | Tabella |
|---|---|
| `youmab`  | `02 03 04 05` |
| `youmab2` | `03 04 05 06` |

Chi la usa sta a `$184D`:

```
1843  AND $F0
1845  OR C
1846  CPL
1847  LD ($E441),A      ; parcheggia i DIP elaborati
184A  LD C,A
184B  AND $03           ; due bit
184D  LD HL,$181A       ; <<< la tabella
1850  RST $20           ; lookup: HL += A ; A = (HL)
1851  LD ($E443),A      ; risultato in RAM
```

`RST $20` e' proprio una lettura da tabella (`ADD A,L / LD L,A / ... / LD A,(HL)
/ RET`, a `$0020`), e l'indice sono due bit dei DIP.

Quattro valori consecutivi indicizzati da due bit dei DIP, in un gioco di
questa famiglia, sono il **numero di vite**: `youmab` da 2/3/4/5, `youmab2` da
3/4/5/6. E' la stessa differenza che separa gli INPUT_PORTS `dangar` e
`dangar2` sull'altro ramo del driver.

**Conclusione pratica**: `youmab` e `youmab2` non sono due hardware diversi.
Sono la stessa scheda con l'anno del copyright cambiato e una vita in piu' o in
meno. Per il core sono un solo insieme di regole, con due MRA.

---

## Cosa servirebbe per farlo girare

Sul core, in ordine di certezza:

1. **`0x8A` bit 3 = onda quadra ~226 Hz** (semionda 2,08–2,35 ms). Un contatore
   sul clock di sistema. Questo è dimostrato e si implementa subito.
2. **`0x01` bit 3** deve andare alto: probabilmente lo stesso segnale o uno
   analogo.
3. **`0x88`**: letta per armare, il valore non viene usato — basta che esista.
4. Gli altri bit di `0x8A` come sorgente casuale per il blocco `0x81`.
5. **`0x00`**: si sa esattamente *come* viene usata — bit 3 e 4, salto
   calcolato, quattro bersagli noti — ma non quale valore il gioco si aspetta,
   perche' i bersagli cadono nella finestra bancata e manca quale banco sia
   attivo. Passo successivo: trovare chi chiama `$DC01`.

Serve anche una regione ROM in più (`extra_banked_rom`, 32 KB) e un byte di
variante suo, perché è hardware che gli altri dieci set non hanno.

---

## Note di metodo

Le ROM lette sono i set MAME `youmab` e `youmab2`, che **non stanno in
`rom/`** (li' ci sono solo `dangar`, `galivan`, `ninjemak`): per rifare o
ricontrollare il disassemblaggio vanno rimessi li'. Le citazioni al driver
in questo documento sono invece state riverificate il 2026-09-14 contro
`reference/galivan.cpp`, e sono esatte parola per parola.

Il disassemblatore è stato validato prima di usarlo: sull'inizio della ROM
produce `DI` / `JP $0C45`, che coincide con i primi byte noti dal dump della
MRA, e mantiene l'allineamento per tutta la finestra successiva — se il decode
fosse sbagliato l'istruzione dopo cadrebbe fuori sincrono entro pochi byte.

`electric1.3u` è **identica** a `ninjemak.1` nella zona dei vettori: il bootleg
ha lasciato quasi intatta la ROM principale e ha spostato le sue aggiunte nel
banco extra.


---

## 7. Lo scroll seriale: MAME ne modella 23 bit, il codice ne spara 24

La routine che alimenta la porta `0x84` sta a `$95BF` nel banco extra 1:

```
95C3  LD B,$08 ; RRCA ; OUT ($84),A ; DJNZ    ; 8 bit da L  del primo valore
95CB  LD B,$02 ; RRCA ; OUT ($84),A ; DJNZ    ; 2 bit da H      -> 10 in tutto
95D5  LD HL,($E43D)
95D9  LD B,$08 ; RRCA ; OUT ($84),A ; DJNZ    ; 8 bit da L  del secondo valore
95E1  LD B,$06 ; RRCA ; OUT ($84),A ; DJNZ    ; 6 bit da H      -> 14 in tutto
```

`RRCA` prima di ogni `OUT` porta il bit 0 in posizione 7, che e' quello che
l'hardware campiona: i bit escono **dal meno significativo**, come modella MAME.

Ma i campi sono **10 + 14 = 24 bit**, mentre `nb1414m4`-less MAME fa
`scrolly = val & 0x3ff` (10) e `scrollx = (val & 0x7ffc00) >> 10` (13), per un
totale di 23. Il bit in piu' non ha effetto visibile — lo sfondo e' 2048 px e
si avvolge molto prima — e nel driver la ripartizione e' ancora indicata come
da verificare, accanto al commento *"scrolling is tied to a serial port"*.

---

## 8. Il layer testo: due regole che sul bootleg NON valgono

Sono la causa della GUI che cominciava troppo avanti.

Su Ninja Emaki le prime 18 celle della VRAM testo sono i **parametri del
NB1414M4**, quindi MAME non le disegna (`if (index < 0x12) index = 0x12`) e,
per il bootleg, aggiunge anche `map(0xd800,0xd81f).nopw()`.

**Sul bootleg quel chip e' stato tolto dalla scheda.** Quelle celle non sono
parametri di nessuno: sono caratteri, e il codice dei bootlegger ci scrive la
propria interfaccia — 21 riferimenti a `$D800`-`$D80F` nelle tre ROM, contati
sul disassemblato. Applicare la regola del blitter a una scheda che il blitter
non ce l'ha faceva sparire l'inizio della GUI.

Nel core entrambe le regole sono ora condizionate a `board_youmab`, quindi
valgono per Ninja Emaki e non per i bootleg. Gli altri undici set non cambiano
di un bit.


---

## 9. Il personaggio invincibile — RISOLTO: e' un DIP

MAME marca i due set col commento *"player is invincible"*. Non e' una
protezione mancante ne' un difetto della scheda: e' il **bit 7 di DSW2**, che
il gioco riusa come interruttore del danno.

### La catena, dal disassemblato

A `$18AA` il gioco impasta i due DSW in una sola parola:

```
189B  IN A,($85)          ; DSW2
189D  AND $F0             ; nibble alto
18A0  IN A,($84)          ; DSW1
18A2  RRCA x4 ; AND $0F   ; nibble alto, spostato in basso
18A8  OR C ; CPL          ; complementato
18AA  LD ($E442),A        ; $E442 = ~((DSW2 & 0xF0) | (DSW1 >> 4))
```

e a `$47C4`, che e' il gestore del colpo, lo interroga:

```
47C5  LD A,($E442) ; BIT 7,A ; JP Z,$47D3   ; bit 7 = 0 -> ramo del DANNO
47CD  LD A,($E464) ; CP $10 ; RET Z         ; bit 7 = 1 -> ESCE senza danno
47D3  LD A,$38 ; LD ($E4EE),A ; LD (IX+15),A  ; 0x38 frame di animazione colpito
```

Il bit 7 di `$E442` e' il **complemento** del bit 7 di DSW2, che nella tabella
dei DIP e' il bit alto di **Allow Continue**:

| Allow Continue | DSW2 bit 7 | `$E442` bit 7 | effetto |
|---|---|---|---|
| 99 Times (`0x00`) | 0 | 1 | secondo controllo, puo' NON fare danno |
| **5 Times (`0x40`)** | 0 | 1 | **idem — ed e' il default di MAME** |
| 3 Times (`0x80`) | 1 | 0 | danno applicato |
| No (`0xC0`) | 1 | 0 | danno applicato |

`$E464` e' il contatore dei **crediti**: lo scrivono le routine delle monete
(`$11FB`, `$1254`, `$12EB`, `$12FE`, `$22A3`) e il codice del bootleg lo stampa
come "CREDIT nn" a `$8B05`.

### Perche' MAME lo vede invincibile

Il driver dichiara `PORT_DIPNAME( 0xc0, 0x40, DEF_STR( Allow_Continue ) )`:
il default e' **`0x40` = "5 Times"**, che ha il bit 7 a zero. Con quel default
il gioco prende il ramo che salta il danno. Non e' un difetto di emulazione:
con quell'impostazione fa lo stesso sulla scheda.

### Cosa fa il core

Gli MRA dei due bootleg hanno il default DSW2 a **`BC`** ("3 Times", bit 7 = 1)
invece del `7C` ereditato da Ninja Emaki. Il giocatore muore. Chi vuole il
comportamento di MAME puo' rimettere "5 Times" dall'OSD.

---

## 10. Il conto dei byte del bootleg (analisi di supporto)

MAME marca i due set `MACHINE_NOT_WORKING` col commento *"player is invincible"*.
Ricavato dal disassemblato, confrontando il bootleg con l'originale giapponese
`youma` — che funziona — la conclusione e' che quel comportamento **non puo'
venire dalle ROM del bootleg**.

### Le ROM

Il bootleg e' l'originale modificato, e le modifiche sono tutte contate:

| ROM del bootleg | Originale | Differenza |
|---|---|---|
| `electric1.3u` | `ync-1.bin` | **57 byte** in 4 blocchi |
| `electric2.3t` banco 0 | `ync-2.bin` | **zero**: identica |
| `electric2.3t` banco 1 | — | tutta nuova: il rimpiazzo software del blitter |
| `electric3.3r` | `ync-3.bin` | **237 byte** in 7 blocchi |

Il trucco della scheda: la regione `0x8000-0xBFFF`, che sull'originale e' ROM
FISSA (`ync-2`), sul bootleg diventa BANCATA — banco 0 il gioco originale,
banco 1 il loro codice.

### La catena del danno e' intatta

Seguita a partire dall'unico ancoraggio ricavato dall'analisi, la tabella dei
DIP che scrive il numero di vite:

```
184B  AND $03 ; LD HL,$181A ; RST $20 ; LD ($E443),A   ; vite iniziali
1327  LD A,($E443) ; LD ($E4E6),A                      ; contatore vivo
244B  LD A,($E4D3) ; OR A ; JR NZ,$2459                ; flag colpito
2459  LD HL,$E4E6 ; DEC (HL)                           ; vita persa
```

**Tutti e 11 i riferimenti a `$E4E6` e tutti e 13 quelli a `$E4D3`**, in ogni
banco di ogni ROM, sono agli stessi indirizzi con le stesse istruzioni
nell'originale e nel bootleg. I bootlegger la morte non l'hanno toccata.

### Anzi, hanno reso il gioco piu' difficile

Le uniche modifiche al bilanciamento vanno nella direzione opposta
all'invincibilita':

| Tabella | Originale | Bootleg |
|---|---|---|
| vite, 4 posizioni DIP (`$181A`) | `03 04 05 06` | `02 03 04 05` — una in meno |
| soglia vita bonus (`$1824`) | `00 06 00` / `00 09 00` = 60k / 90k | `00 99 00` — 990.000, irraggiungibile |

Una vita in meno e nessuna vita extra: il tipico intervento per far mangiare
piu' gettoni. Chi scrive quelle due tabelle non rende il personaggio immortale.

### Nota

Il difetto quindi sta nel modello dell'hardware, non nel software del gioco.
I candidati sono le sole cose che sul bootleg differiscono dalla Ninja Emaki:
la finestra bancata `0x8000-0xBFFF`, lo scroll seriale — la cui ripartizione in
campi nel driver e' ancora da verificare — e le porte nuove.
