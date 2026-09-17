# Note per il driver MAME su `youmab` / `youmab2`

Due osservazioni sul driver `nichibutsu/galivan.cpp`, raccolte lavorando al core
FPGA e messe per iscritto nella speranza che possano essere utili. Nessuna delle
due riguarda una protezione mancante: **entrambe si spiegano col disassemblato
delle ROM del bootleg e col confronto con l'originale giapponese `youma`**, che
MAME fa girare bene.

Tutti gli indirizzi qui sotto sono verificati, non dedotti. Le ROM sono
`electric1.3u` (fissa `0x0000-0x7FFF`), `electric2.3t` (banco extra a
`0x8000-0xBFFF`, 2 banchi da 16 KB) e `electric3.3r` (banco a `0xC000-0xDFFF`,
4 banchi da 8 KB).

---

## 1. `MACHINE_NOT_WORKING` con la motivazione "player is invincible"

### Il fatto

L'invincibilita' **non e' un difetto di emulazione**: e' l'effetto del valore di
default della porta DIP.

A `$189B` il gioco impasta i due DSW in una sola parola di RAM:

```
189B  IN A,($85)          ; DSW2
189D  AND $F0             ; nibble alto
189F  LD C,A
18A0  IN A,($84)          ; DSW1
18A2  RRCA / RRCA / RRCA / RRCA
18A6  AND $0F
18A8  OR C
18A9  CPL                 ; complementato
18AA  LD ($E442),A        ; $E442 = ~((DSW2 & 0xF0) | (DSW1 >> 4))
```

e a `$47C4`, che e' il gestore del colpo al giocatore, la interroga:

```
47C4  POP HL
47C5  LD A,($E442)
47C8  BIT 7,A
47CA  JP Z,$47D3          ; bit 7 = 0  -> prosegue e applica il danno
47CD  LD A,($E464)
47D0  CP $10
47D2  RET Z
47D3  LD A,$38
47D5  LD ($E4EE),A
47D8  LD (IX+15),A        ; 0x38 frame di animazione "colpito"
```

Il bit 7 di `$E442` e' il **complemento** del bit 7 di DSW2, che nella tabella
dei DIP e' il bit alto di `Allow_Continue`:

| `Allow Continue` | valore | DSW2 bit 7 | `$E442` bit 7 | esito osservato sull'hardware |
|---|---|---|---|---|
| 99 Times | `0x00` | 0 | 1 | **il giocatore non muore** |
| 5 Times  | `0x40` | 0 | 1 | **il giocatore non muore** — ed e' il default |
| 3 Times  | `0x80` | 1 | 0 | muore normalmente |
| No       | `0xC0` | 1 | 0 | muore normalmente |

Il driver dichiara:

```cpp
PORT_DIPNAME( 0xc0, 0x40, DEF_STR( Allow_Continue ) )   PORT_DIPLOCATION("SW2:7,8")
```

cioe' default `0x40` = "5 Times", che ha il bit 7 a zero. **Con quel default il
gioco salta il danno.** E' esattamente cio' che l'annotazione descrive.

### Perche' il comportamento e' del gioco, non del bootleg

Il codice e' **di Nichibutsu, non dei bootlegger**. Confronto byte a byte fra
`electric1.3u` e `ync-1.bin` (la ROM del set `youma`, funzionante):

| Blocco | Indirizzo | Esito |
|---|---|---|
| lettore DSW -> `$E442` | `$189B`, 32 byte | **identico** |
| gate del danno | `$47C4`, 24 byte | **identico** |

Le due ROM differiscono in tutto **57 byte**, in quattro blocchi
(`$0C4A`, `$0D6D-$0DA7`, `$181A-$183B`, `$1838`->`$4577`), nessuno dei quali
tocca questi due punti.

Quindi il comportamento vale anche su `youma` e `ninjemak`: e' del gioco.

### Una possibile modifica

Per questa ragione il `MACHINE_NOT_WORKING` di `youmab`/`youmab2` potrebbe
diventare una nota che spiega il DIP. Se si preferisce che il set sia giocabile
con le impostazioni di fabbrica, il default di `Allow_Continue` potrebbe passare
da `0x40` a `0x80`.

---

## 2. Il layer testo: l'interfaccia comincia 18 celle piu' avanti

### Il fatto

`ninjemak_state::get_tx_tile_info` contiene:

```cpp
if (index < 0x12) index = 0x12;
```

Quella regola esiste perche' sulla Ninja Emaki le prime 18 celle della VRAM
testo **non sono caratteri**: sono i parametri del chip **NB1414M4** (comando,
input, DSW, crediti, scroll). Giusto li'.

Ma il machine_config del bootleg fa:

```cpp
void youmab_state::youmab(machine_config &config)
{
    ninjemak(config);
    ...
    config.device_remove("nb1414m4");     // <<< il chip NON c'e'
}
```

**Tolto il chip, quelle 18 celle non sono parametri di nessuno**: sono
caratteri normali, e il codice dei bootlegger — che rimpiazza il blitter via
software — ci scrive sopra la propria interfaccia. Conteggio sul disassemblato
delle tre ROM del bootleg: **21 riferimenti** a `$D800`-`$D80F`, fra cui
`$D42A`, `$D630`, `$D63B` (ROM bancata) e `$8514`, `$8B19` (banco extra).

`youmab_state` eredita `get_tx_tile_info` da `ninjemak_state`, quindi la regola
del blitter viene applicata a una scheda che il blitter non ce l'ha, e la parte
iniziale dell'interfaccia sparisce.

Allo stesso modo:

```cpp
map(0xd800, 0xd81f).nopw(); // scrolling isn't here..
```

ignora proprio le scritture verso quelle celle, e il commento lascia la
questione aperta.

### Riscontro

Su core FPGA indipendente, con la stessa ROM: applicando le due regole
l'interfaccia comincia 18 celle piu' avanti; **rimuovendole per il solo set
bootleg, l'interfaccia torna al suo posto**. Nessun'altra modifica.

### Una possibile modifica

Per i due set bootleg si potrebbe non applicare la sostituzione `index < 0x12` e
non scartare le scritture a `0xD800-0xD81F`: per esempio con un
`get_tx_tile_info` proprio di `youmab_state`, o con un flag nella classe base
che disattivi la regola quando il NB1414M4 non e' presente.

---

## 3. Nota sulla protezione dei bootleg

La cosiddetta protezione dei bootleg e' **codice morto**. La patch dei
bootlegger a `$1838` devia su `$4577`:

```
4577  LD A,$24
4579  LD ($FFF6),A        ; il flag della protezione, preimpostato
457C  IN A,($84) ; AND $0F ; JP $183C   ; poi fa cio' che faceva l'originale
```

e sia la misura di tempo sulla porta `0x8A`:

```
883C  LD A,($FFF6) ; CP $24 ; JR NC,$8890   ; flag >= 0x24 -> salta tutto il test
```

sia la lettura della porta `0x00`:

```
DC01  LD A,($FFF6) ; OR A ; JR NZ,$DC2A
DC2A  LD HL,$FFF6 ; LD A,(HL) ; CP $23 ; JR NC,$DC1A   ; calcola dal flag, non dalla porta
```

vengono **saltate**, perche' il flag vale gia' `0x24`. Le porte `0x00`, `0x01`,
`0x88`, `0x8A` non vengono mai interrogate durante il gioco: qualunque valore
restituiscano e' irrilevante. `machine().rand()` su `0x8A` non fa danno, ma non
serve nemmeno.

Il vero scopo del codice aggiunto dai bootlegger e' un altro: **rimpiazzare via
software il blitter NB1414M4** che hanno tolto dalla scheda. I nove punti in cui
l'originale scriveva un comando al chip sono stati sostituiti da altrettante
chiamate a un dispatcher:

```
        ORIGINALE                        BOOTLEG
D427    LD HL,$0602                      LD A,$04
D42A    LD ($D800),HL                    JP $DB2C
```

`$DB2C` inserisce il banco extra (`OUT ($82),$FF`), chiama `$DC01`, che salta a
`$DB39` = `RST $30` — un dispatcher a tabella in linea, indicizzato dal
parametro del chiamante — e la tabella a `$DB3A` punta tutta dentro
`0x8000-0xBFFF`, cioe' nel banco appena inserito.

---

## 4. Come verificare

- ROM: `youmab` e `youmab2`, che stanno nello zip merged di `ninjemak`.
- Punto 1: avviare il set, mettere `Allow Continue` su "3 Times" dal menu dei
  DIP e farsi colpire. Il giocatore muore. Rimettendo "5 Times" non muore piu'.
- Punto 2: confrontare la posizione dell'interfaccia con quella di `youma`.
