# `ninjemat` — Ninja Emaki su licenza Tecfri

Il quattordicesimo e ultimo set di `galivan.cpp`. In MAME e' marcato
`MACHINE_NOT_WORKING | MACHINE_UNEMULATED_PROTECTION`; nel driver compare nel
`ROM_START` (riga 1628) e nella riga `GAME()` (riga 1919), senza ancora note sul
motivo.

Quello che segue e' ricavato dal disassemblato delle sue ROM, confrontate byte
per byte con quelle di `ninjemak`, partendo dal driver MAME. In MAME 0.289 il
set non e' ancora giocabile, e queste note potrebbero aiutare a renderlo tale.

---

## 1. Cos'e' la scheda

Il programma e' quello di **Ninja Emaki ricompilato per un decodificatore di I/O
in stile Galivan**. La routine di inizializzazione e' identica a quella di
`ninjemak` con le sole porte cambiate:

```
ninjemak $1739   LD A,$18 ; OUT ($80),A ; OUT ($86),A ; LD A,$3F ; OUT ($85),A
ninjemat $16C5   LD A,$18 ; OUT ($40),A ; OUT ($46),A ; LD A,$3F ; OUT ($45),A
```

| | `ninjemat` | come lo so |
|---|---|---|
| Input | `0x00` P1, `0x01` P2, `0x02` SYSTEM, `0x03` DSW1, `0x04` DSW2 | traccia di flusso dal reset |
| Uscite | `0x40` gfxbank, `0x41-0x42` scrollx + layer enable, `0x43-0x44` scrolly, `0x45` suono, `0x46` morta, `0x47` ack IRQ | idem |
| Scroll | registri hardware, non il blitter | `$BF20`: `OUT ($41)`, `OUT ($42)`, `OUT ($43)`, `OUT ($44)` |
| Layer | `$E43C` bit 4 -> porta 0x42 bit 6 = sfondo spento; bit 3 -> bit 7 = testo spento | `$18A2` |
| Sprite | 128, spriteram da 512 byte | i suoi riferimenti a `$E100-$E1FF` sono gli stessi di `ninjemak`; su Galivan li' ci sono variabili sparse |
| Chars | 32 KB = 1024 tile reali | la seconda meta' ha 11089 byte non nulli |
| Testo | `code = vram \| (attr&3)<<8`, `color = (attr&0x1c)>>2` | vedi §3 |
| Tasti | **due**, non tre | maschera gli input solo con `$30`; nessuna maschera tocca il bit 6 o 7 |
| DIP | tabella `galivan`, la stessa del driver | verificata voce per voce a `$17C1` e `$181C` |

---

## 2. Il blitter NB1414M4 non c'e', e non manca nessuna ROM per quello

Le nove chiamate al chip sono state **disattivate cambiando un byte ciascuna**:
l'opcode `21` (`LD HL,<comando>`) e' diventato `C9` (`RET`).

```
ninjemak b3 $D5DA:  ... 18 B6 [21] 80 00  22 00 D8 3A 64 E4 32 0F D8 C9
ninjemat b1 $D390:  ... 18 B6 [C9] 80 00  22 00 D8 3A 64 E4 32 0F D8 C9
```

Al loro posto c'e' un **interprete di testo software** a `$1900`:

```
1900  LD E,(HL) ; INC HL
1902  LD D,(HL) ; INC HL      ; DE = indirizzo in VRAM
1904  LD C,(HL) ; INC HL      ; C  = attributo
1906  LD A,(HL)
1907  CP $FF ; RET Z          ; $FF = fine
190A  CP $FE ; JP Z,$191A     ; $FE = ripeti B volte
190F  LD (DE),A               ; il codice del carattere
1910  SET 2,D                 ; +0x0400
1912  LD A,C ; LD (DE),A      ; l'attributo
1914  RES 2,D ; INC DE ; INC HL ; JR $1906
```

con la tabella delle stringhe a `$1947`: `INSERT COIN`, `PUSH START BUTTON`,
`CREDIT`, `HI<SCORE`, `ONE PLAYER ONLY`, `GAME OVER`. Su `ninjemak` quelle
stringhe **esistono soltanto dentro `ninjemak.5`**, il data ROM del chip. E'
la stessa architettura del bootleg `youmab`, fatta pero' ufficialmente.

Per questo il dump ha sedici ROM contro le diciassette di `ninjemak`: la
mancante e' quella del chip, e la scheda il chip non ce l'ha.

---

## 3. La VRAM del testo risponde a due indirizzi

Il bit **A12 non e' decodificato**: `$C800-$CFFF` e `$D800-$DFFF` sono la stessa
memoria. La prova e' che il programma scrive la stessa riga da due punti
diversi:

```
BE47  LD HL,$1962 ; CALL $1900      ; "        CREDIT  " -> $C869  (indice 0x69)
BE59  LD ($D878),A                  ; decine dei crediti -> indice 0x78
BE6B  LD ($D879),A                  ; unita'             -> indice 0x79
BE70  LD A,$FB ; LD ($DC78),A ; LD ($DC79),A   ; il loro attributo
```

La stringa e' lunga 17 celle e comincia a 0x69, quindi finisce a 0x79: le due
cifre vanno sulle sue ultime due celle. Perche' il conto torni, `$C8xx` e
`$D8xx` devono essere lo stesso banco di VRAM.

**Il formato del testo e' quello di Ninja Emaki**, e anche questo e' dimostrato
invece che dedotto: il NB1414M4 di `ninjemak` scrive nella VRAM attributo `$F7`
per le stringhe della GUI e `$FB` per le cifre dei crediti (data ROM
`ninjemak.5`, offset `0x13` e `0x47`), e `ninjemat` — per le stesse identiche
scritte — scrive `$F7` e `$FB` da software. Stessi byte per le stesse stringhe.
L'init conferma: pulisce lo schermo con carattere `$20` e attributo `$7B`, e la
tile `0x320` e' l'unica uniforme (`$FF` = pen trasparente) — con la lettura di
Galivan sarebbe la `0x120`, che non e' vuota.

---

## 4. Lo sfondo e' quello di Galivan, e si dimostra al byte

`ninjemak` tiene la mappa di sfondo come **512x32 SCAN_COLS**, `ninjemat` come
**128x128 SCAN_ROWS**. Non e' un'interpretazione: e' la stessa mappa trasposta.

```
ninjemat[R*128 + C] == ninjemak[((R>>5)*128 + C)*32 + (R&31)]
                          dati 100,0%   attributi 98,7%   su tutte le 16384 celle
```

Cento per cento sul mezzo che conta, la meta' dati. Non e' una trasposizione
semplice: e' una **piega**. La striscia lunga di `ninjemak` — 512 colonne per 32
righe, cioe' 8192 x 512 pixel — e' tagliata in quattro pezzi da 128 colonne e
impilata in una mappa quadrata 128 x 128, cioe' 2048 x 2048 pixel, che e' quanto
la tilemap di Galivan sa indirizzare.

La conferma sta nello scroll, e non e' un dettaglio: a `$BF55` lo scroll Y si
porta dentro **due bit presi da `$E43E`**, che e' la stessa variabile dello
scroll X. E' il riporto della piega — quando il livello supera i 2048 pixel in
orizzontale, la X torna a zero e la Y salta di un quarto di mappa. Nessun altro
set della famiglia fa una cosa del genere.

Questo spiega anche perche' lo sfondo del set non si vede ancora correttamente:
letta col layout di Ninja Emaki, una mappa ripiegata esce a colonne alternate.

Nota che ne discende, e che conta per il §7: la **mappa delle collisioni non va
ripiegata**. La routine a `$22C6` la indicizza con `(HL & 0x1FF8) * 2`, cioe'
con la coordinata lunga NON ripiegata, la stessa nei due set — la piega vive
solo nel disegno. Per questo la tabella di `ninjemak` ci va dentro cosi' com'e'.

Conferma indipendente dallo scroll: `$BF20` manda alla porta `0x42` solo il
nibble basso, e `galivan_state::screen_update` maschera con `& 0x07` — undici
bit, cioe' 2048 pixel, cioe' **128 tile**.

Il **colore** dello sfondo resta pero' in formato Ninja Emaki
(`((attr&0x60)>>3) | ((attr&0x0c)>>2)`): nel suo attributo il bit 2 e' usato nel
61,5% delle celle e la formula di Galivan lo ignora, mentre il bit 4 e' costante
e Galivan lo userebbe come bit di colore.

---

## 5. Il banco e' a quattro vie, coi due bit scambiati

`ninjemat` scrive la porta `0x40` durante il gioco da un solo punto, `$1887`:

```
1887  PUSH BC ; LD C,A
1889  LD A,($E43C) ; AND $2F
188E  BIT 7,C ; JP Z,$1897
1893  SET 6,A ; SET 4,A
1897  BIT 6,C ; JP Z,$189E
189C  SET 7,A
189E  OUT ($40),A
```

Quella routine mette il **bit 6** dove `ninjemak` mette il bit 7. I ventotto
chiamanti passano quattro soli valori, e combaciano uno a uno con i punti
corrispondenti di `ninjemak` — due sono perfino allo stesso indirizzo (`$0A9B`,
`$0B04`):

| chiamante | `ninjemat` -> bit (7,6) | `ninjemak` | banco | contenuto |
|---|---|---|---|---|
| collisione `$22E0` | `$00` -> (0,0) | `AND $3F` | **0** | mappa collisioni |
| collisione `$22E0` | `$40` -> (1,0) | `OR $40` | **1** | mappa collisioni |
| `$0976` | `$80` -> (0,1) | `OR $80` | **2** | codice |
| interrupt `$0DB3` | `$C0` -> (1,1) | `OR $C0` | **3** | codice |

Quindi **numero di banco = `{porta40 bit 6, porta40 bit 7}`**, col bit 6 alto.

Il contenuto conferma la tabella. Su `ninjemak` i quattro banchi di
`ninjemak.3` sono:

| banco | valori distinti | i piu' frequenti | cos'e' |
|---|---|---|---|
| 0 | 186 | `$00` x4336, `$AA` x793 | dati |
| 1 | 48 | `$00` x4462, `$AA` x1026 | dati |
| 2 | 248 | `$DD` x569, `$FD` x353 | codice |
| 3 | 256 | `$DD` x366, `$FF` x303 | codice |

e la ROM bancata di `ninjemat`, `8.e16`, e' **i banchi 2 e 3** di `ninjemak`:
85% e 40% di byte uguali, e a `$CD00` in banco 3 c'e' la stessa routine che
`ninjemak` ha a `$CF47`, istruzione per istruzione.

---

## 6. Al dump mancano 16 KB, e sono la mappa delle collisioni

La routine a `$22C6` legge il tipo di terreno dalla finestra bancata:

```
22D5  ADD HL,HL
22D6  LD C,$00
22D8  BIT 5,H ; JP Z,$22DF
22DD  LD C,$40
22DF  LD A,C ; CALL $1887      ; banco 0 oppure 1
22E7  LD A,H ; AND $1F ; LD H,A
22EB  LD BC,$C000 ; ADD HL,BC  ; legge a 0xC000-0xDFFF
```

I suoi dieci chiamanti sono gli stessi di `ninjemak`, due allo stesso indirizzo:
la routine e' viva. Ma i banchi 0 e 1 di `ninjemat` **non esistono**: la sua ROM
bancata e' 16 KB e sono i banchi 2 e 3.

Conto dei byte:

```
ninjemak   32 + 16 + 32 = 80 KB     ROM_REGION 0x18000, 16 KB vuoti
ninjemat   32 + 16 + 16 = 64 KB     ROM_REGION 0x18000, 32 KB VUOTI
```

Quei 16 KB in piu' che restano vuoti su `ninjemat` sono esattamente i banchi 0 e
1. Li ho cercati con la loro firma (poche decine di valori distinti, meta' byte
a `$00`, molti `$AA`) in **tutte e sedici** le ROM del set: non ci sono. Gli
unici blocchi a bassa entropia sono grafica (`7.c7` e `6.c3`).

**Il dump di `ninjemat` e' incompleto**, ed e' con ogni probabilita' il motivo
del `MACHINE_NOT_WORKING`. Senza quei 16 KB il gioco
legge il proprio codice come mappa del terreno: il personaggio sbatte contro
ostacoli che non esistono, l'attract si inchioda, e morendo sul terreno la
macchina a stati finisce fuori strada.

Da notare: col banco a un bit solo — cioe' leggendo la porta `0x40` come fa
Galivan — i due percorsi di **codice** cadono giusti per caso, ed e' per questo
che il gioco comunque parte e si gioca. Sbagliano solo le due letture della
collisione.

---

## 6bis. L'attract, e cosa dice il codice

Riferito dall'utente: col banco a quattro vie la demo non si inchioda piu', ma
il personaggio "cammina dove vuole". Tre fatti dal disassemblato.

**La demo non e' una registrazione.** In nessuno dei due set esiste codice che
scriva valori finti nelle celle di input `$E457-$E45A`: l'unico scrittore e' il
lettore delle porte (`$1139` su `ninjemat`, `$11A8` su `ninjemak`). Il
personaggio della demo e' mosso dalla logica degli oggetti, non da un nastro, e
non esiste un percorso giusto registrato con cui confrontarlo.

**Tutto quello da cui dipende e' uguale nei due set.** Le routine degli oggetti
nei banchi stanno agli stessi indirizzi — `$C4AC`, `$C544`, `$C57A`, `$C816`,
`$DAEB` combaciano al byte — i livelli sono gli stessi (§4) e la mappa delle
collisioni e' indicizzata con la coordinata non ripiegata (§4, nota finale).

**Una differenza vera c'e', ed e' nella ROM.** `ninjemak` ha a `$19F9-$1A16` un
blocco che compone i parametri ricavati dai DIP e li mette nella struttura di
gioco:

```
19F9  LD A,($E445) ; RRCA ; AND $80 ; LD E,A
1A00  LD A,($E444) ; RRCA ; RRCA ; AND $40
1A07  OR C ; OR B ; OR E
1A0A  LD (IY+7),A                      ; difficolta' e opzioni
1A0D  LD A,($E44E) ; LD (IY+9),A      ; soglia della vita bonus
1A13  LD A,($E452) ; LD (IY+0),A
```

`ninjemat` non ha niente di equivalente, e combacia con quello che si vede nel
suo lettore dei DIP: dodici `NOP` a `$17C7` e altri dodici a `$1822`, esattamente
dove `ninjemak` impasta le due parole dei DIP. Chi ha fatto la conversione ha
tolto pezzi della gestione delle impostazioni, e quei parametri nella struttura
non vengono mai caricati.

Un gioco che parte coi parametri di difficolta' non caricati si comporta
diversamente dall'originale, demo compresa. Non e' del core: e' nei byte della
ROM, e si vede dove.

Una precisazione che cambia le aspettative: `ninjemat` **non e' un bootleg**, e'
una licenza ufficiale Nichibutsu a Tecfri. Ma chi l'ha adattata ha lavorato come
un bootlegger: blitter disattivato a colpi di `21`->`C9`, testo riscritto a mano,
gestione dei DIP sforbiciata a `NOP`, e una ROM da 16 KB in meno.

---

## 7. La scelta fatta qui, e perche'

Nell'MRA i banchi 0 e 1 sono presi da **`ninjemak.3`, primi 16 KB**:

```xml
<!-- banchi 0-1 = mappa collisioni col terreno. NON dumpata per ninjemat -->
<part name="ninjemak.3" crc="68c92bf6" offset="0x0" length="0x4000"/>
<!-- banchi 2-3 = codice (8.e16) -->
<part name="ninjemat/8.e16" crc="8c5782da"/>
```

E' una ROM che in quel set **non c'e'**, quindi la scelta va dichiarata. Le
ragioni per cui e' l'unico dato non inventato:

1. **I livelli sono gli stessi byte per byte.** La mappa di sfondo di `ninjemat`
   e' quella di `ninjemak` trasposta, verificata al 100% su 4096 posizioni (§4).
   Stessi livelli, quindi stessa mappa delle collisioni.
2. **La routine di collisione e' identica nelle due**, indice compreso: stesse
   istruzioni, stesso `AND $F8`, stesso `AND $1F`, stesso `CP $05`, stesso
   `LD BC,$C000`. Cambia solo come viene scritta la porta del banco. Quindi la
   tabella non e' ne' trasposta ne' riordinata: si usa cosi' com'e'.
3. **L'alternativa e' peggiore.** Lasciare i banchi 0 e 1 vuoti significa dare
   al gioco zeri al posto del terreno, che e' un dato inventato tanto quanto,
   ma senza nessuna base.

Chi preferisce la scheda esattamente com'e' dumpata puo' togliere quella riga
dall'MRA: il core non cambia, legge semplicemente zeri.

---

## 8. Note che potrebbero servire al driver MAME

1. **`8.e16`** — la ROM corrisponde ai banchi **2 e 3**, quindi starebbe a
   `0x14000`; a `0x10000-0x13FFF` corrisponde la parte non ancora dumpata.
2. **Il banco** e' a due bit, scambiati rispetto a Ninja Emaki: `{bit6, bit7}`
   della porta `0x40`. `galivan_state::gfxbank_w` oggi ne usa uno.
3. **La configurazione video.** Il set usa `ninjemak_state` insieme al
   `machine_config` di Galivan. Dalle ROM risulta una combinazione diversa:
   mappa di sfondo 128x128 SCAN_ROWS come Galivan, decode di testo, sprite e
   palette come Ninja Emaki, e nessun clamp delle 18 celle, perche' il chip non
   c'e'.
4. **L'alias della VRAM testo** a `$C800-$CFFF`: e' li' che l'interprete
   software scrive buona parte del testo.
5. **I flag.** `MACHINE_UNEMULATED_PROTECTION` accomuna i sei set della famiglia
   e si riferisce al NB1414M4, che questa scheda non monta. Il
   `MACHINE_NOT_WORKING` e' coerente con quanto trovato al §6: il dump e'
   incompleto.

---

## 9. Come verificare

- Sfondo trasposto: confrontare `ninjemat/5.c1` con `ninjemak.7` alla formula
  `mat[r*128+c] == mak[c*32+r]`.
- Banchi: profilare i quattro banchi da 8 KB di `ninjemak.3` contando i valori
  distinti, e confrontare `8.e16` con ciascuno.
- Chiamanti del banco: cercare `CALL $1887` nella ROM fissa di `ninjemat` e
  `OUT ($80),A` in quella di `ninjemak`.
- Attributi del testo: leggere `ninjemak.5` agli offset `0x13` e `0x47`.
