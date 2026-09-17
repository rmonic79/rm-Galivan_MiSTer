# I due chip custom Nichibutsu: NB1412M2 e NB1414M4

Documentazione dei moduli `rtl/dangar/dangar_nb1412m2.sv` e
`rtl/dangar/dangar_nb1414m4.sv`.

Servono entrambi a questo core, ma **nessuno dei due è esclusivo di questa
scheda**: girano su altri driver Nichibutsu, quindi sono riutilizzabili così
come sono. Questo documento sta qui per quello.

| Chip | Dove serve in MAME |
|---|---|
| **NB1412M2** | `galivan.cpp` (`dangarj`) · `cop01.cpp` (Cop 01, **Mighty Guy**) · `terracre.cpp` (Terra Cresta, Soldier Girl Amazon, Sei Senshi Amatelass, Kid no Hore Hore Daisakusen) |
| **NB1414M4** | `galivan.cpp` (Ninja Emaki, Youma Ninpou Chou) · `armedf.cpp` (**Legion**, **Terra Force**, **Kozure Ookami**, **Crazy Climber 2**, **Armed F**) |

Le schede sono diverse — `armedf` e `terracre` hanno un 68000, non uno Z80 —
ma i due moduli non dipendono dalla CPU: hanno un'interfaccia a porte e una ROM
propria.

---

# NB1412M2 — il decrypter

Riferimento: `mame/nichibutsu/nb1412m2.cpp` (Angelo Salese).

## Dov'è, fisicamente

Su `dangarj` **non è sulla scheda principale**: sta su una **scheda figlia
DG-3**, con un oscillatore da 8 MHz suo e una ROM da 8 KB (`dg-3.ic7.2764`,
regione `prot_chip`). Lo annota MAME nel `ROM_START`.

## Interfaccia

Due sole porte, **aggiunte** a quelle della scheda base — la `dangarj_io_map`
chiama `io_map(map)` e poi mappa (galivan.cpp:765-770):

| Porta | Verso | Cosa fa |
|---|---|---|
| `0x81` | W | comando: latcha l'indirizzo di un registro **interno** al chip |
| `0x80` | R/W | dato: legge o scrive il registro scelto dal comando |

Essendo additive, sul core il chip può restare **sempre istanziato**: gli altri
set non scrivono mai su quelle porte, quindi non serve un bit di variante.

## Registri interni

Solo quelli che servono qui. Il chip ne ha altri per timer e controllo DAC, che
però **usa solo Mighty Guy** sulla sua CPU audio: nel modulo non ci sono, ed è
la prima cosa da aggiungere se un giorno si fa quel core.

| Reg | Verso | Significato |
|---|---|---|
| `0x32` | W | comando di operazione (5 = "carica il risultato"); non entra nel calcolo |
| `0x33` / `0x34` | W | `rom_address`, byte **alto** / basso |
| `0x35` / `0x36` | W | `adj_address`, byte alto / basso |
| `0x37` | R | risultato del decrypter |
| `0x90`, `0x92`, `0x94`, `0xA0`-`0xA3` | R/W | latch, senza effetti |

Attenzione all'ordine: nel sorgente `offset == 0` è il byte **alto**
(nb1412m2.cpp:229-231), non il basso.

## Il calcolo

Tutta la protezione è una riga (nb1412m2.cpp:256-272):

```
prot_adj  = (0x43 - rom[adj_address]) & 0xff
risultato =  rom[rom_address & 0x1fff] - prot_adj
```

Aritmetica a 8 bit che wrappa, come gli `uint8_t` di MAME. Il perché del `0x43`
lo spiega il sorgente: la somma fra la voce di aggiustamento e il valore atteso
fa sempre `0x143`.

**Una differenza voluta rispetto a MAME**: lì `& 0x1fff` è applicata solo a
`rom_address`, `adj_address` resta nudo. Nel modulo sono mascherati tutti e
due, perché in RTL un indirizzo fuori range non "non succede": legge un'altra
cella. Il gioco non ci va mai fuori, quindi il comportamento è identico.

## Come è fatto il modulo, e perché

Tre scelte, tutte di timing:

- **`dout` è registrata, non combinatoria.** Finisce dentro `io_dout` del main,
  che è già una catena combinatoria fino al bus dati della CPU: aggiungerci una
  `case` a otto vie allungherebbe il percorso critico per niente. Comando e
  latch sono fermi da centinaia di cicli quando la CPU legge, quindi il ciclo
  di ritardo non è osservabile.
- **Le due sottrazioni di MAME sono in serie**: la prima è precalcolata in un
  registro quando arriva il dato di `adj`, così nel ciclo finale ne resta una.
- **Le due letture della ROM si alternano su un contatore a 4 stati.** La BRAM
  ha una porta di scrittura (download) e una di lettura: tre accessi non stanno
  in un M10K. Il giro completo dura ~42 ns a 96 MHz, mentre fra l'ultima
  scrittura dell'indirizzo e la lettura della porta il Z80 spende un `OUT`
  intero più un `IN` — centinaia di cicli. Nessun trigger, nessun caso limite.

---

# NB1414M4 — il blitter del layer testo

Riferimento: `mame/nichibutsu/nb1414m4.cpp` (Angelo Salese, su ricerche di
Tomasz Slanina e Legion).

> **In MAME questo chip NON è emulato dal silicio: è una simulazione** del
> comportamento osservato. Il modulo riproduce quella simulazione, quindi ne
> eredita anche i limiti — il driver annota *"minor protection issues"* e due
> comandi che restano ignoti.

## Cosa fa

Si scrive da solo il layer testo pescando da una **ROM dati da 16 KB**. La VRAM
è 2 KB: `0x000-0x3FF` codice del carattere, `0x400-0x7FF` attributo/palette.
Parte su scrittura alla porta `0x86` (galivan.cpp:787, gestore
772-776).

**Produce anche lo scroll dello sfondo.** A ogni esecuzione, prima di qualunque
comando, latcha (nb1414m4.cpp:343-345):

```
scroll_x = vram[0x0d] | (vram[0x0e] << 8)
scroll_y = vram[0x0b] | (vram[0x0c] << 8)
```

È l'unica via da cui Ninja Emaki ottiene lo scroll: nella sua `io_map` i
registri `0x41-0x44` di Galivan non esistono.

## Comandi

Il comando sono i primi due byte della VRAM, `{vram[0], vram[1]}`, smistato sul
byte alto:

| Comando | Cosa fa |
|---|---|
| `0x0000` | insert coin + crediti |
| `0x0200` | riempimento di una pagina, oppure copia di una pagina intera |
| `0x0600` | service mode (una trentina di operazioni in fila) |
| `0x0e00` | HUD di gioco: hi-score, messaggi 1P/2P, punteggi, game over |
| `0x8000`, `0xff00` | niente (Ninja Emaki li manda, MAME non sa cosa siano) |

## Due regole che non si intuiscono

**I primi 18 byte della VRAM non sono caratteri**: sono i parametri del chip —
comando, input, DSW, crediti, scroll. Le primitive `dma` e `fill` li saltano
(`if(i+dst < 18) continue`), ma **le scritture di un carattere singolo no**:
punteggio, crediti e service mode ci scrivono sopra.

Conseguenza per il video: il layer testo non deve disegnare quelle celle. MAME
le sostituisce tutte con la cella `0x12`
(`ninjemak_state::get_tx_tile_info`: `if (index < 0x12) index = 0x12`). Senza
questo si vedono i byte di parametro disegnati come caratteri.

**MAME rilegge la VRAM viva, non una fotografia.** Poiché le scritture di un
carattere singolo possono cambiare i parametri, un'operazione successiva legge
valori diversi da quelli di inizio esecuzione. Nel modulo i 18 byte si
rileggono fra un'istruzione e l'altra, e le cifre del punteggio si leggono
viventi, una per una.

## Come è fatto il modulo, e perché

Le quattro routine sono lunghe ma fatte tutte degli stessi gesti: leggi dalla
ROM una coppia di byte che dà la destinazione, copia N byte, scrivi un
carattere, scrivi un punteggio in BCD. Quindi:

- un **programma a microcodice**, una riga per ogni riga del sorgente MAME, che
  si leggono affiancate — è la parte dove un errore si vede;
- **quattro primitive separate** — DMA, FILL, PUT, SCORE — ognuna con i propri
  stati e il proprio contatore. Niente contatori condivisi, niente stati
  riusati, nessun salto calcolato sulle costanti di stato: sono esattamente le
  scorciatoie che fanno incastrare due routine senza che si veda. Due tentativi
  scritti "compatti" sono stati buttati proprio per questo.

**Integrazione**: il blitter sta dentro `dangar_main` e condivide la **porta A
della char RAM** con la CPU, che resta ferma mentre lui copia (`blit_busy`).
Nessuna terza porta sull'M10K, ed è anche ciò che fa la scheda vera: il gioco
scrive la porta `0x86` e aspetta.

**Costo in tempo**: caso peggiore la copia di una pagina intera, 0x400 byte per
5 cicli = 5120 cicli, 53 µs a 96 MHz. Il fill costa 2 cicli a cella, 21 µs.
Dentro un frame con tre ordini di grandezza di margine.

## Come è stato verificato

Non a occhio: un banco differenziale dà la **stessa ROM sintetica** e gli
**stessi parametri** a due implementazioni — un porting Python di
`nb1414m4.cpp` e l'RTL vero in ModelSim — poi confronta i 2048 byte di VRAM.

**71 casi su 71 identici byte per byte**: 11 scelti a mano più 60 casuali su
comando, parametri, ROM e numero di frame.

Il banco si valida da sé prima di credergli: il comando `0x8000` è ignorato dal
chip, quindi lì la VRAM in uscita deve essere **identica** a quella in ingresso.
Se quell'invariante non torna, il banco è rotto e gli altri risultati non si
guardano.

Ha trovato tre difetti che leggendo non si vedevano:

1. `rom[0x13]` campionato **un ciclo troppo presto** — l'indirizzo scritto a
   fine ciclo è stabile solo al successivo, quindi il dato arriva due cicli
   dopo, non uno.
2. L'indice della tabella del comando `0x0200`: MAME maschera con `0x87`
   **prima**, quindi di `& 0xf` restano solo i bit 2-0, non 3-0.
3. La lettura viva della VRAM invece della fotografia (vedi sopra).

Nessuno dei tre sarebbe emerso da una prova a schermo: due danno caratteri
sbagliati solo in casi particolari, il terzo solo con certe destinazioni.
