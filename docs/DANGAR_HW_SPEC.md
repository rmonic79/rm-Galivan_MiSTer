> **ATTENZIONE — documento NON VERIFICATO.**
> Prodotto da subagent (estrazione + verifica avversariale) il 2026-09-06.
> Non e' stato ricontrollato riga per riga contro `reference/galivan.cpp`.
> Non usarlo come fonte per scrivere RTL: serve solo a sapere dove guardare
> nel driver. I fatti confermati stanno nei commenti di `rtl/dangar/*.sv`.
>
> **Stato della verifica al 2026-09-14** — controllate tutte e **481** le
> citazioni al driver:
> - **346** provate meccanicamente: la riga citata contiene davvero il simbolo
>   o il valore esadecimale che la frase le attribuisce;
> - **157** lette a mano contro il sorgente, affermazione per affermazione;
> - **1 errore trovato e corretto** (l'NB1414M4 e' istanziato a 1259, non 1255).
>
> Questo chiude il livello delle CITAZIONI: ogni riferimento punta dove dice.
> Le 157 lette a mano sono verificate anche nella sostanza; per le altre 346
> resta provato solo il puntamento, non l'interpretazione. L'avvertenza qui
> sopra vale ancora per quelle.

# Ufo Robo Dangar (4/09/1987) — Specifica di implementazione per core MiSTer

Fonte unica: `reference/galivan.cpp` (MAME, 1923 righe). Ogni riga di specifica porta la
citazione `galivan.cpp:<riga>`. Cio che non e citato non e nel sorgente.

**Set bersaglio**: `GAME( 1986, dangar, 0, galivan, dangar, galivan_state, empty_init, ROT270, "Nichibutsu", "Ufo Robo Dangar (4/09/1987)", MACHINE_SUPPORTS_SAVE ) // GV-1412-I and GV-1412-II pcbs` — `galivan.cpp:1912`.

Quindi, e solo questo:
- machine_config `galivan_state::galivan()` = `common(config)` + main_map/io_map/screen_update/gfx_galivan/PALETTE (`galivan.cpp:1229-1241`, `galivan.cpp:1166-1227`);
- classe `galivan_state`, nessun device di protezione (`galivan.cpp:155-228`);
- input ports `dangar` = `PORT_INCLUDE(galivan)` + 5 `PORT_MODIFY` (`galivan.cpp:962-992`);
- gfxdecode `gfx_galivan` (`galivan.cpp:1100-1104`).

**Rami da IGNORARE** (stesso file, comportamento diverso): `ninjemak_state` (main_map `galivan.cpp:737-746`, io_map `galivan.cpp:778-789`, gfxbank_w `galivan.cpp:557-588`, get_bg_tile_info `galivan.cpp:478-486`, video_start `galivan.cpp:521-525`, screen_update `galivan.cpp:685-698`, palette `galivan.cpp:405-447`), `dangarj_state` (`galivan.cpp:765-770`, `galivan.cpp:1243-1249`), `youmab_state` (`galivan.cpp:791-796`), NB1412M2 (`galivan.cpp:1248`), NB1414M4 (`galivan.cpp:1259`), i bootleg. Per `dangar` non c'e' nessuna protezione da emulare e le porte 0x80-0x87 non sono decodificate (`galivan.cpp:748-763`).

`dangar` e marcato solo `MACHINE_SUPPORTS_SAVE` (`galivan.cpp:1912`): niente IMPERFECT_GRAPHICS/SOUND, quindi quanto descritto qui e il comportamento che MAME considera corretto.

---

## 1. TRAPPOLE (in ordine di gravita: le prime impediscono il boot)

| # | Trappola | Comportamento corretto | Citazione |
|---|---|---|---|
| T1 | Lettura I/O 0xC0 deve valere esattamente **0x58** | `io_port_c0_r()` ha corpo `return (0x58);` con commento *"causes a reset in dangar if value differs."*. Nessun ingresso fisico e collegato a quella porta. Restituire 0xFF o 0x00 manda dangar in reset loop: il core non parte. | `galivan.cpp:713-717`, `galivan.cpp:762` |
| T2 | IRQ main = livello **ASSERITO**, non impulso | `set_vblank_int("screen", irq0_line_assert)`: INT resta attivo finche non si scrive sulla porta I/O 0x47. La lambda su 0x47 ignora il dato scritto e fa solo `set_input_line(0, CLEAR_LINE)`. Impulso auto-cancellante o ack mancante = CPU in loop di interrupt. | `galivan.cpp:1170`, `galivan.cpp:761` |
| T3 | La regione `maincpu` ha un **buco di 16 KB** | `8.1b` @0x00000 (0x8000), `9.3b` @0x08000 (0x4000), `10.4b` @**0x10000** (0x4000); 0x0C000-0x0FFFF non e caricato. Il banking parte da `&rombase[0x10000]`. Concatenare le tre ROM di seguito sposta i banchi di 16 KB: crash appena il gioco commuta banco. | `galivan.cpp:1396-1399`, `galivan.cpp:1117-1119` |
| T4 | 0xD800-0xDFFF: lettura diversa dalla scrittura | `map(0xc000,0xdfff).bankr(m_rombank)` copre tutta la finestra in LETTURA; `map(0xd800,0xdfff).w(videoram_w)` installa SOLO la scrittura. La char RAM e write-only: leggere 0xD800-0xDFFF restituisce gli offset 0x1800-0x1FFF del banco ROM selezionato. | `galivan.cpp:730-731`, `galivan.cpp:1118` |
| T5 | Decodifica I/O su **8 bit soli** | `map.global_mask(0xff)` sia sulla io_map main sia su quella sonora: solo A0-A7. Lo Z80 mette B (o A) su A8-A15 durante IN/OUT: decodificare 16 bit fa sparire scritture di scroll e sound in modo intermittente. | `galivan.cpp:750`, `galivan.cpp:862` |
| T6 | Il sound latch **non** contiene il byte scritto | `sound_command_w` fa `m_soundlatch->write(((data & 0x7f) << 1) + 1)` (nel sorgente l'OR con 1): bit 7 scartato, bit 6-0 shiftati a sinistra di 1, bit 0 forzato a 1. Il valore nel latch e sempre dispari (0x01-0xFF). | `galivan.cpp:702-705`, `galivan.cpp:759` |
| T7 | La scrittura del latch **non genera nessun interrupt** | `GENERIC_LATCH_8(config, m_soundlatch)` senza data_pending_callback: il sound Z80 ha solo l'IRQ periodico a 7812.5 Hz e fa polling. Aggiungere NMI/IRQ sul latch rompe l'audio. | `galivan.cpp:1188`, `galivan.cpp:1175` |
| T8 | Porta sound 0x04 in lettura: side-effect + ritorno fisso 0 | `soundlatch_clear_r()` = `m_soundlatch->clear_w(); return 0;`. Il comando si legge alla porta **0x06**. | `galivan.cpp:707-711`, `galivan.cpp:866-867` |
| T9 | La tilemap del testo e scandita per **COLONNE** | Testo `TILEMAP_SCAN_COLS, 8, 8, 32, 32`, background `TILEMAP_SCAN_ROWS, 16, 16, 128, 128`. Indice testo = colonna*32 + riga. Row-major = schermo trasposto. | `galivan.cpp:513-514` |
| T10 | Il registro dei layer e impacchettato nello scroll X alto | `scrollx_w`: `if (offset == 1) { m_layers = data & 0xe0; }` e poi SEMPRE `m_scrollx[offset] = data`. Porta 0x42 = bit 7-5 layer + bit 2-0 scroll X alto; la porta 0x41 non tocca i layer. Polarita INVERTITA: bit a 1 = layer spento. | `galivan.cpp:593-600`, `galivan.cpp:655`, `galivan.cpp:658-680` |
| T11 | Il background **non ha RAM**: la mappa e in ROM | `get_bg_tile_info` legge solo `m_bgrom` (regione `bgtiles`): codice a `m_bgrom[idx]`, attributo a `m_bgrom[idx + 0x4000]`. Ordine di caricamento invertito rispetto alle etichette: `7.19d` @0x0000 = codici, `6.17d` @0x4000 = attributi. | `galivan.cpp:457-465`, `galivan.cpp:1418-1420` |
| T12 | Pen trasparente = **15**, non 0 | `m_tx_tilemap->set_transparent_pen(15)` e sprite con `transpen(..., 15)`. Il test e sul nibble grezzo della ROM grafica, PRIMA di qualunque lookup di palette. Il pen 0 e opaco. Il background non ha pen trasparente. | `galivan.cpp:516`, `galivan.cpp:648`, `galivan.cpp:661` |
| T13 | Palette: pen 0-7 e pen 8-15 usano bit di colore **diversi** | Char e tile: `ctabentry = base + (i & 0x0f) + ((i >> ((i & 0x08) ? 2 : 0)) & 0x30)` con i = color*16 + pen. Bank = color[1:0] per i pen 0-7, color[3:2] per i pen 8-15. Il color code a 4 bit NON e un indice di banco unico. | `galivan.cpp:375-390` |
| T14 | Sprite RAM bufferizzata, copia automatica a inizio VBLANK | `BUFFERED_SPRITERAM8` + `screen_vblank().set(..., vblank_copy_rising)`; `draw_sprites` legge `m_spriteram->buffer()`, mai la RAM viva. Nessuna porta di trigger DMA. | `galivan.cpp:1178`, `galivan.cpp:1182`, `galivan.cpp:618` |
| T15 | Coordinate sprite: X con bias -0x80, Y complementata a 240 | `sx = (spriteram[offs+3] - 0x80) + 256 * (attr & 0x01)`, `sy = 240 - spriteram[offs]`. Entrambi `int` con segno, mai mascherati (sx in [-128,+383], sy in [-15,+240]); l'unico filtro e la cliprect. | `galivan.cpp:631-632` |
| T16 | L'area visibile parte a **y = 16** | `set_raw(..., 263, 2*8, 30*8)`: y visibile 16..239. Tilemap e sprite sono disegnati in coordinate raster senza alcun offset. Del tx tilemap 32x32 si vedono solo le righe di tile 2..29; con sy = 240-Y, uno sprite con Y=0 (sy=240) e uno con Y=240 (sy=0) sono entrambi fuori schermo. | `galivan.cpp:1181`, `galivan.cpp:653-682` |
| T17 | Il bit 2 dell'attributo sprite ha **doppio uso** | `color = (attr & 0x3c) >> 2` (include attr[2]) e insieme `code = spriteram[offs+1] + ((attr & 0x06) << 7)` (attr[2] = code[9]). Va cablato su entrambe le destinazioni. | `galivan.cpp:627`, `galivan.cpp:642` |
| T18 | Layout sprite intrecciato fra le due meta della regione | `spritelayout` con `RGN_FRAC(1,2)` e xoffs `{1*4, 0*4, F+1*4, F+0*4, 3*4, 2*4, F+3*4, F+2*4, ...}`: ogni riga prende 2 pixel dalla meta A, 2 dalla meta B, alternati. ROM caricate a numerazione invertita: `12.f4` @0x0000 = meta A, `11.f1` @0x8000 = meta B. | `galivan.cpp:1087-1098`, `galivan.cpp:1414-1416` |
| T19 | `gfxbank_w` (porta 0x40) **non banca nessuna grafica** | Corpo integrale: bit 0/1 coin counter, bit 2 `flip_screen_set`, bit 7 banco ROM CPU. Bit 3,4,5,6 mai letti. Il background-disable su bit 4 e il bank a 2 bit su 6-7 appartengono a `ninjemak_state::gfxbank_w`. | `galivan.cpp:542-555`, `galivan.cpp:557-588` |
| T20 | La `category` del layer testo e un **no-op** | `tileinfo.category = attr & 8 ? 0 : 1` (logica invertita), ma le due categorie sono disegnate consecutivamente con la stessa priorita in entrambi i rami. Il bit 3 resta solo il bit 0 del color code `(attr & 0x78) >> 3`. | `galivan.cpp:473-475`, `galivan.cpp:667-668`, `galivan.cpp:677-678` |
| T21 | `bitmap.fill(0)` non e nero | Con background spento si riempie con l'indice pen 0, che tramite la tabella dei char (ctabentry(0)=0) e il colore indiretto 0 delle PROM. Non forzare 24'h000000. | `galivan.cpp:658-659`, `galivan.cpp:377`, `galivan.cpp:362-366` |
| T22 | Il DIP "Flip Screen" non ribalta niente da solo | DSW2 bit 0x20 e solo un dato letto dalla CPU sulla porta 0x04; l'unico `flip_screen_set` e il bit 2 della porta 0x40, scritto dal software. | `galivan.cpp:955-957`, `galivan.cpp:549`, `galivan.cpp:755` |
| T23 | I default dei DIP **non sono 0xFF** | DSW1 = 0xDF (Cabinet default 0x00 = Upright), DSW2 = 0x7F (Allow Continue default 0x40 = "5 Times"). Con 0xFF/0xFF il gioco parte in Cocktail e senza continue. | `galivan.cpp:931-933`, `galivan.cpp:987-991` |
| T24 | Costante di flip = **240** su entrambi gli assi | `if (flip) { sx = 240 - sx; sy = 240 - sy; flipx = !flipx; flipy = !flipy; }` — non 255, non 256, non 224. Con flip attivo sy = 240 - (240 - Y) = Y. | `galivan.cpp:633-639` |
| T25 | I DIP di `dangar` sono diversi da quelli di `galivan` | I `PORT_MODIFY` cambiano P1/P2 bit 0x80, SYSTEM 0x20, DSW1 0x40 e 0x80, DSW2 0x0c (Coin_B con valori diversi) e DSW2 0xc0 (Allow_Continue). | `galivan.cpp:962-992` |

---

## 2. CPU principale, mappa di memoria, banking

### 2.1 CPU
- Z80 istanziato come `Z80(config, m_maincpu, XTAL(12'000'000) / 2)` = **6.000000 MHz**; il sorgente marca il valore con `// 6 MHz?` (`galivan.cpp:1169`). E in `common()`, quindi vale per dangar via `galivan()` (`galivan.cpp:1231`).
- Stesso quarzo del pixel clock (`galivan.cpp:1181`): un solo dominio a 12 MHz genera CPU main e video. L'audio ha il proprio quarzo da 8 MHz (`galivan.cpp:1172`, `galivan.cpp:1222`).
- Nessun watchdog, nessuna NVRAM/EEPROM: `common()` istanzia solo Z80 x2, BUFFERED_SPRITERAM8, SCREEN, SPEAKER, GENERIC_LATCH_8, 3 FILTER_BIQUAD, YM3526 e 2 DAC_8BIT_R2R; `galivan()` aggiunge GFXDECODE e PALETTE (`galivan.cpp:1166-1227`, `galivan.cpp:1229-1241`).

### 2.2 Mappa di memoria (AS_PROGRAM) — `galivan_state::main_map`, 5 sole righe

| Intervallo | Accesso | Contenuto | Citazione |
|---|---|---|---|
| 0x0000-0xBFFF | R | ROM fissa 48 KB (`8.1b` + `9.3b`), nessun mirror | `galivan.cpp:728`, `galivan.cpp:1397-1398` |
| 0xC000-0xDFFF | **solo R** | ROM bancata 8 KB (`.bankr`, non `.bankrw`): le scritture in 0xC000-0xD7FF non hanno alcun handler e vanno perse | `galivan.cpp:730` |
| 0xD800-0xDFFF | **solo W** | char RAM 2 KB (`videoram_w`, share `m_videoram`); in lettura questa finestra resta ROM bancata | `galivan.cpp:731`, `galivan.cpp:183` |
| 0xE000-0xE0FF | R/W | sprite RAM 256 byte, share `"spriteram"` (64 sprite x 4 byte) | `galivan.cpp:733`, `galivan.cpp:316-318` |
| 0xE100-0xFFFF | R/W | RAM di lavoro 0x1F00 byte | `galivan.cpp:734` |

0xE000-0xFFFF forma un blocco contiguo di 8192 byte di RAM; il tap sprite e solo la finestra bassa da 0x100 (`galivan.cpp:733-734`).

### 2.3 ROM banking
- `machine_start`: `m_rombank->configure_entries(0, 2, &rombase[0x10000], 0x2000); m_rombank->set_entry(0);` — **2 banchi** da 8 KB a partire dall'offset 0x10000 della regione `maincpu` (`galivan.cpp:1117-1119`). I 4 banchi sono di ninjemak (`galivan.cpp:1131`).
- Selezione: bit 7 del dato scritto sulla porta I/O 0x40, `m_rombank->set_entry((data & 0x80) >> 7)` (`galivan.cpp:551-552`, `galivan.cpp:756`).
- Indirizzo ROM effettivo = `0x10000 + (bank << 13) + (A - 0xC000)` (derivato da `galivan.cpp:730`, `galivan.cpp:1118`).
- `set_entry(0)` sta solo in `machine_start`, **non** in `machine_reset` (`galivan.cpp:1119` vs `galivan.cpp:1148-1155`).

### 2.4 Reset
`galivan_state::machine_reset()`: `m_maincpu->reset(); m_layers = 0; m_scrollx[0] = m_scrollx[1] = 0; m_scrolly[0] = m_scrolly[1] = 0;` (`galivan.cpp:1148-1155`). Non tocca videoram, spriteram, buffer sprite, coin counter ne il banco ROM. Con `m_layers = 0`: background acceso, testo acceso, sprite disegnati PRIMA del testo (`galivan.cpp:658-680`).

---

## 3. Porte I/O della CPU principale (`galivan_state::io_map`, `galivan.cpp:748-763`)

`map.global_mask(0xff)` (`galivan.cpp:750`): si decodificano solo A0-A7. Gli spazi di lettura e
scrittura sono **disgiunti**: nessuna porta e insieme leggibile e scrivibile (`galivan.cpp:751-762`).
In ninjemak invece 0x80 e 0x85 sono contemporaneamente `portr` e `w` (`galivan.cpp:781`, `galivan.cpp:786`): non copiare quella struttura.

### 3.1 Letture

| Porta | Sorgente | Note | Citazione |
|---|---|---|---|
| 0x00 | P1 | 8 bit ACTIVE LOW | `galivan.cpp:751` |
| 0x01 | P2 | 8 bit ACTIVE LOW | `galivan.cpp:752` |
| 0x02 | SYSTEM | 8 bit ACTIVE LOW | `galivan.cpp:753` |
| 0x03 | DSW1 | valore dei dip, vedi 9.2 | `galivan.cpp:754` |
| 0x04 | DSW2 | valore dei dip, vedi 9.2 | `galivan.cpp:755` |
| 0xC0 | `io_port_c0_r` | **costante 0x58** | `galivan.cpp:713-717`, `galivan.cpp:762` |

Nessun'altra lettura e mappata. Non esiste alcun percorso di ritorno dal sound al main: nessun latch
di risposta, nessun bit di "sound busy" (`galivan.cpp:748-763`).

### 3.2 Scritture

| Porta | Handler | Effetto | Citazione |
|---|---|---|---|
| 0x40 | `gfxbank_w` | bit0 coin counter 0, bit1 coin counter 1, bit2 flip screen, bit7 banco ROM; bit 3-6 ignorati | `galivan.cpp:542-555`, `galivan.cpp:756` |
| 0x41 | `scrollx_w` off.0 | `m_scrollx[0] = data` (scroll X basso) | `galivan.cpp:593-599`, `galivan.cpp:757` |
| 0x42 | `scrollx_w` off.1 | `m_layers = data & 0xe0` **e** `m_scrollx[1] = data` (bit 2-0 = scroll X alto) | `galivan.cpp:593-599`, `galivan.cpp:757` |
| 0x43 | `scrolly_w` off.0 | `m_scrolly[0] = data`, nessun effetto collaterale | `galivan.cpp:603-605`, `galivan.cpp:758` |
| 0x44 | `scrolly_w` off.1 | `m_scrolly[1] = data`, di cui si usano solo i bit 2-0 | `galivan.cpp:603-605`, `galivan.cpp:656` |
| 0x45 | `sound_command_w` | latch = `((data & 0x7f) << 1) or 1` | `galivan.cpp:702-705`, `galivan.cpp:759` |
| 0x46 | — | **non mappata**: la riga `map(0x46,0x46).nopw();` e commentata | `galivan.cpp:760` |
| 0x47 | lambda | `set_input_line(0, CLEAR_LINE)`, il dato scritto e ignorato | `galivan.cpp:761` |

### 3.3 Bit della porta 0x40 (`gfxbank_w`)

| Bit | Significato | Citazione |
|---|---|---|
| 0 | coin counter 0 (`coin_counter_w(0, data & 1)`) | `galivan.cpp:545` |
| 1 | coin counter 1 (`coin_counter_w(1, data & 2)`) | `galivan.cpp:546` |
| 2 | `flip_screen_set(data & 0x04)` | `galivan.cpp:548-549` |
| 3-6 | non letti dal corpo della funzione | `galivan.cpp:542-555` |
| 7 | banco ROM 0xC000-0xDFFF | `galivan.cpp:551-552` |

Nessun coin lockout in tutto il driver (`galivan.cpp:542-555`).

### 3.4 Bit della porta 0x42 (scroll X alto + layer)

| Bit | Significato | Citazione |
|---|---|---|
| 7 | 1 = layer testo SPENTO (`if ((m_layers & 0x80) == 0)` per disegnarlo) | `galivan.cpp:665`, `galivan.cpp:675` |
| 6 | 1 = background SPENTO, al suo posto `bitmap.fill(0, cliprect)` | `galivan.cpp:658-661` |
| 5 | 1 = ordine bg, testo, sprite (sprite sopra il testo); 0 = bg, sprite, testo | `galivan.cpp:663-680` |
| 4-3 | non usati da nulla (esclusi sia da `& 0xe0` sia da `& 0x07`) | `galivan.cpp:597`, `galivan.cpp:655` |
| 2-0 | bit 10-8 dello scroll X del background | `galivan.cpp:655` |

`m_layers` e riassegnato per intero a ogni scrittura su 0x42 (`m_layers = data & 0xe0`, non un OR):
non e possibile cambiare i layer senza riscrivere anche i bit alti dello scroll X (`galivan.cpp:597`, `galivan.cpp:213`).

---

## 4. Interrupt e timing video

### 4.1 Interrupt
| Sorgente | Destinazione | Tipo | Ack | Citazione |
|---|---|---|---|---|
| VBLANK dello screen | main Z80, linea 0 | `irq0_line_assert` (livello mantenuto) | scrittura su I/O 0x47 | `galivan.cpp:1170`, `galivan.cpp:761` |
| timer 8 MHz/2/512 = **7812.5 Hz** | audio Z80, linea 0 | `irq0_line_hold` (auto-clear all'INTA) | nessuna porta di ack | `galivan.cpp:1175` |

- In tutto il file le uniche azioni su linee di interrupt sono `galivan.cpp:723` (ninjemak, non usata da dangar), `galivan.cpp:761`, `galivan.cpp:1170`, `galivan.cpp:1175`. Nessun NMI, nessun reset hardware comandato dal gioco su nessuna delle due CPU (`galivan.cpp:1148-1155`, grep NMI = 0 occorrenze).
- Il YM3526 e istanziato **senza** `irq_handler`: i timer dell'OPL non interrompono la CPU sonora (`galivan.cpp:1222`).
- Le due temporizzazioni sono scorrelate: 7812.5 / 59.4106 = 131.5 IRQ audio per frame (derivazione da `galivan.cpp:1175`, `galivan.cpp:1181`).

### 4.2 Timing video
`m_screen->set_raw(XTAL(12'000'000) / 2, 384, 0, 32 * 8, 263, 2 * 8, 30 * 8)` (`galivan.cpp:1181`):

| Parametro | Valore | Citazione |
|---|---|---|
| pixel clock | 6.000000 MHz | `galivan.cpp:1181` |
| H total / H visibile | 384 / 0..255 (256 px), 128 px di blanking | `galivan.cpp:1181` |
| V total / V visibile | 263 / 16..239 (224 righe), 16 righe in testa + 23 in coda | `galivan.cpp:1181` |
| HSync | 6000000 / 384 = **15625.0 Hz** (derivato) | `galivan.cpp:1181` |
| VSync | 6000000 / (384*263) = **59.4106 Hz** (derivato) | `galivan.cpp:1181` |
| Orientamento | ROT270 (verticale, uscita 224x256) | `galivan.cpp:1912` |

Il fronte di salita del VBLANK e l'inizio della riga 240: in quell'istante viene asserito l'IRQ main
(`galivan.cpp:1170`) e viene copiata la lista sprite (`galivan.cpp:1182`).

Le misure "HSync 15.6242 kHz / VSync 59.40776 Hz" (`galivan.cpp:83-84`) appartengono al blocco note
Guru della board YN-1/YN-2 di Ninja Emaki (`galivan.cpp:29-30`, `galivan.cpp:39`, `galivan.cpp:89`),
non alla GV-1412 di dangar (`galivan.cpp:1912`): non coincidono con i valori derivati dal `set_raw` e
vanno usate solo come conferma indiretta.

### 4.3 Ordine di composizione (`screen_update`, `galivan.cpp:653-683`)
1. Se `m_layers & 0x40`: `bitmap.fill(0, cliprect)`; altrimenti `m_bg_tilemap->draw(..., 0, 0)` (`galivan.cpp:658-661`).
2. Se `m_layers & 0x20`: testo (cat 0 poi cat 1, solo se `(m_layers & 0x80) == 0`) e poi `draw_sprites` (`galivan.cpp:663-671`).
3. Altrimenti: `draw_sprites` e poi il testo alle stesse condizioni (`galivan.cpp:672-680`).

Il background e sempre il layer di fondo ed e sempre opaco. Gli sprite sono disegnati in **entrambi**
i rami: non esiste alcun bit di enable/disable degli sprite (`galivan.cpp:658-680`).
Non esiste priority bitmap: gli sprite usano `gfx->transpen` e non `pdrawgfx`, i tilemap sono
disegnati con priority 0; la priorita e solo l'ordine delle chiamate, tutto-o-niente per frame
(`galivan.cpp:644-648`, `galivan.cpp:661`).
Lo scroll e applicato una sola volta per frame, in testa a `screen_update`: nessun row-scroll,
nessun interrupt di raster (`galivan.cpp:653-656`).

---

## 5. Layer testo (char)

### 5.1 RAM e formato
- 2048 byte a 0xD800-0xDFFF, **write-only** per la CPU (vedi T4) (`galivan.cpp:730-731`).
- `videoram_w` e banale: `m_videoram[offset] = data; m_tx_tilemap->mark_tile_dirty(offset & 0x3ff);` — nessuna trasformazione del dato (`galivan.cpp:535-539`).
- Meta bassa 0xD800-0xDBFF = codici (8 bit bassi); meta alta 0xDC00-0xDFFF = attributi. L'attributo del tile N sta a `m_videoram[N + 0x400]` (`galivan.cpp:309-313`, `galivan.cpp:469`).

| Byte | Bit | Significato | Citazione |
|---|---|---|---|
| codice (0xD800+N) | 7-0 | bit 7-0 del codice carattere | `galivan.cpp:470` |
| attributo (0xDC00+N) | 0 | bit 8 del codice carattere | `galivan.cpp:470` |
| attributo | 6-3 | color code a 4 bit `(attr & 0x78) >> 3` | `galivan.cpp:473` |
| attributo | 3 | **anche** category: `attr & 8 ? 0 : 1` (no-op, vedi T20) | `galivan.cpp:475` |
| attributo | 7, 2, 1 | mai letti dal codice; il commento di mappa li marca `?` | `galivan.cpp:310-312`, `galivan.cpp:469-475` |

Codice carattere a **9 bit** (0-511), coerente con la regione `chars` da 0x4000 byte / 32 byte per
carattere (`galivan.cpp:470`, `galivan.cpp:1405-1406`). Il codice a 10 bit `((attr & 0x03) << 8)` e di
ninjemak (`galivan.cpp:496`).

### 5.2 Tilemap
- `TILEMAP_SCAN_COLS, 8, 8, 32, 32` con `set_transparent_pen(15)` (`galivan.cpp:514-516`).
- Indirizzamento: `addr_code = (X[7:3] << 5) or Y[7:3]` cioe colonna*32 + riga; `addr_attr = addr_code + 0x400` (derivato da `galivan.cpp:514`, `galivan.cpp:469`).
- Nessuno scroll: su `m_tx_tilemap` non esiste alcuna chiamata `set_scroll*` in tutto il file (`galivan.cpp:653-683`).
- Nessun flip per-tile: il 4o argomento di `tileinfo.set` e la costante 0 (`galivan.cpp:471-474`). L'unico ribaltamento e il flip screen globale (`galivan.cpp:549`).
- Con l'area visibile y 16..239 sono visibili solo le righe di tile 2..29 (derivato da `galivan.cpp:514`, `galivan.cpp:1181`).
- La char RAM non viene mai inizializzata ne cancellata dal driver: il contenuto all'accensione e indeterminato ed e il programma a riempirla (`galivan.cpp:1148-1155`, `galivan.cpp:542-555`).

### 5.3 Grafica
- `GFXDECODE_ENTRY( "chars", 0, gfx_8x8x4_packed_lsb, 0, 16 )` — gfx element 0, base colore 0, 16 color code (`galivan.cpp:1101`), coerente con `tileinfo.set(0, ...)` (`galivan.cpp:471`).
- Regione `chars` = 0x4000 byte, unica EPROM `5.13d` (`galivan.cpp:1405-1406`). 0x4000 / 512 caratteri = **32 byte per carattere**, 4 bpp packed, 4 byte per riga, 2 pixel per byte (derivazione aritmetica).
- **`gfx_8x8x4_packed_lsb` non e definito in galivan.cpp**: e un layout standard MAME solo referenziato (`galivan.cpp:1101`). L'ordine esatto di nibble e piani va preso da `emupal.h`: vedi DOMANDE APERTE.

---

## 6. Layer background

### 6.1 Mappa (in ROM, non in RAM)
`get_bg_tile_info` (`galivan.cpp:457-465`):
```
attr = m_bgrom[tile_index + 0x4000];
code = m_bgrom[tile_index] | ((attr & 0x03) << 8);
tileinfo.set(1, code, (attr & 0x78) >> 3, 0);
```
`m_bgrom` e `required_region_ptr` sulla regione `bgtiles` (`galivan.cpp:171`, `galivan.cpp:193`);
nella main_map non esiste alcuna finestra su quella regione (`galivan.cpp:726-735`).

| Byte | Bit | Significato | Citazione |
|---|---|---|---|
| codice (bgrom[N]) | 7-0 | bit 7-0 del codice tile | `galivan.cpp:460` |
| attributo (bgrom[N+0x4000]) | 1-0 | bit 9-8 del codice tile | `galivan.cpp:460` |
| attributo | 6-3 | color code a 4 bit | `galivan.cpp:463` |
| attributo | 7, 2 | mai usati; marcati `?` nel commento di formato | `galivan.cpp:326-330`, `galivan.cpp:457-465` |

Codice tile a **10 bit** (0-1023), coerente con la regione `tiles` da 0x20000 byte / 128 byte per tile
(`galivan.cpp:460`, `galivan.cpp:1408-1412`). Nessun bit di flip per tile: il 4o argomento di
`tileinfo.set` e 0 (`galivan.cpp:461-464`). Nessun banco grafico (`galivan.cpp:542-555`).

### 6.2 Tilemap e scroll
- `TILEMAP_SCAN_ROWS, 16, 16, 128, 128` = 2048x2048 pixel, 16384 voci = esattamente i 2x16 KB della regione `bgtiles` (`galivan.cpp:513`, `galivan.cpp:1418`).
- `tile_index = (worldY >> 4) * 128 + (worldX >> 4)`; indirizzo codice = `tile_index`, indirizzo attributo = `tile_index + 0x4000` (derivato da `galivan.cpp:513`, `galivan.cpp:459-460`).
- Scroll: `set_scrollx(0, m_scrollx[0] + 256 * (m_scrollx[1] & 0x07))`, `set_scrolly(0, m_scrolly[0] + 256 * (m_scrolly[1] & 0x07))` — **11 bit per asse** (0-2047), copertura esatta della mappa (`galivan.cpp:655-656`).
- `m_scrollx[1]` conserva comunque il byte intero, layer bit inclusi (`galivan.cpp:599`).
- Il bg tilemap non ha pen trasparente (nessun `set_transparent_pen`) ed e disegnato con flags 0 e priority 0 (`galivan.cpp:513`, `galivan.cpp:661`).
- Il bg tilemap non riceve mai `mark_tile_dirty`: l'unica chiamata del file e sul tx (`galivan.cpp:538`).

### 6.3 Grafica
`GFXDECODE_ENTRY( "tiles", 0, gfx_16x16x4_packed_lsb, 16*16, 16 )` — gfx element 1, base colore 256,
16 color code (`galivan.cpp:1102`). Regione `tiles` = 0x20000 = 1024 tile da 128 byte
(`galivan.cpp:1408-1412`). Anche qui il layout `gfx_16x16x4_packed_lsb` **non e definito in questo
file** (`galivan.cpp:1102`).

---

## 7. Sprite

### 7.1 Lista e buffering
- 64 sprite da 4 byte a 0xE000-0xE0FF; `length = m_spriteram->bytes()` = 0x100, loop `offs += 4` (`galivan.cpp:618-624`, `galivan.cpp:733`, `galivan.cpp:316`).
- Doppio buffer hardware: copia sul fronte di salita del VBLANK (riga 240), il renderer legge solo `m_spriteram->buffer()` (`galivan.cpp:1178`, `galivan.cpp:1182`, `galivan.cpp:618`).
- La CPU legge e scrive la RAM viva a 0xE000-0xE0FF: quello che rilegge puo differire da quello in uso sullo schermo nel frame corrente (`galivan.cpp:733`, `galivan.cpp:618`).
- Tutti e 64 gli sprite sono disegnati ogni frame: nessun terminatore di lista, nessun limite per scanline, nessun ordinamento. L'unico filtro e la cliprect (`galivan.cpp:624-649`).
- Priorita interna: offs crescente, quindi **l'indice piu alto sta sopra** (`galivan.cpp:624-648`).
- Nessun bit di disabilitazione per-sprite: gli 8 bit dell'attributo sono tutti usati (`galivan.cpp:626-642`).
- La spriteram e il buffer non sono azzerati al reset (`galivan.cpp:1148-1155`).

### 7.2 Formato dell'entry (4 byte)

| Byte | Bit | Significato | Citazione |
|---|---|---|---|
| +0 | 7-0 | Y grezzo; `sy = 240 - Y` | `galivan.cpp:632` |
| +1 | 7-0 | bit 7-0 del codice sprite | `galivan.cpp:642` |
| +2 | 0 | bit 8 di X (`+256`) | `galivan.cpp:631` |
| +2 | 1 | bit 8 del codice sprite | `galivan.cpp:642` |
| +2 | 2 | bit 9 del codice sprite **e** bit 0 del color code | `galivan.cpp:627`, `galivan.cpp:642` |
| +2 | 5-3 | bit 3-1 del color code | `galivan.cpp:627` |
| +2 | 6 | flip X | `galivan.cpp:628` |
| +2 | 7 | flip Y | `galivan.cpp:629` |
| +3 | 7-0 | X basso; `sx = (X - 0x80) + 256 * attr[0]` | `galivan.cpp:631` |

Nessun bit di priorita per-sprite, nessun bit di dimensione, nessuno zoom (`galivan.cpp:626-629`, `galivan.cpp:642`).

### 7.3 Disegno
```
color = (attr & 0x3c) >> 2;                       // galivan.cpp:627
code  = spriteram[offs+1] + ((attr & 0x06) << 7); // galivan.cpp:642, 10 bit
gfx->transpen(bitmap, cliprect, code,
              color + 16 * (m_sprpalbank[code >> 2] & 0x0f),
              flipx, flipy, sx, sy, 15);          // galivan.cpp:644-648
```
- gfx element 2 (`m_gfxdecode->gfx(2)`, `galivan.cpp:621`), base colore 512, **256 color code** (`galivan.cpp:1103`). Il color code passato vale al massimo 15 + 16*15 = 255: nessun wrap (`galivan.cpp:627`, `galivan.cpp:646`).
- L'indice della PROM di banco e `code >> 2` sul codice a **10 bit non troncato** = `{attr[2], attr[1], byte1[7:2]}`, massimo 0xFF: copre esattamente i 256 byte della PROM (`galivan.cpp:646`, `galivan.cpp:1428`). Un banco ogni 4 tile consecutive.
- Flip screen: `sx = 240 - sx; sy = 240 - sy; flipx = !flipx; flipy = !flipy` (`galivan.cpp:633-639`). Derivazione: per uno sprite 16x16 su visibile x 0..255 e y 16..239, 240 e il valore esatto di specchiatura su entrambi gli assi.

### 7.4 Layout ROM sprite (`spritelayout`, `galivan.cpp:1087-1098`)
- 16x16, `RGN_FRAC(1,2)`, 4 bitplane `{0,1,2,3}`, `charincrement = 64*8` = 64 byte per meta, quindi 128 byte per sprite.
- yoffs a passo 32 bit = 4 byte per riga dentro ciascuna meta (`galivan.cpp:1095-1096`).
- xoffs `{ 1*4, 0*4, F+1*4, F+0*4, 3*4, 2*4, F+3*4, F+2*4, 5*4, 4*4, F+5*4, F+4*4, 7*4, 6*4, F+7*4, F+6*4 }` con F = RGN_FRAC(1,2) (`galivan.cpp:1093-1094`). Regola, per n = 0..3: x=4n+0 -> nibble basso del byte n della meta A; x=4n+1 -> nibble alto del byte n della meta A; x=4n+2 -> nibble basso del byte n della meta B; x=4n+3 -> nibble alto del byte n della meta B.
- Indirizzo byte = `base_meta + 64*tile + 4*riga + n` (derivato da `galivan.cpp:1093-1097`).
- Regione `sprites` = 0x10000: `12.f4` @0x0000 = meta A, `11.f1` @0x8000 = meta B, F = 0x8000, **512 tile** (`galivan.cpp:1414-1416`, `galivan.cpp:1090`).
- Il codice sprite e a 10 bit ma esistono solo 512 tile: la selezione della tile usa `code[8:0]`; `code[9]` non cambia la grafica ma cambia l'indirizzo della PROM di banco (`galivan.cpp:642`, `galivan.cpp:646`).
- Lo stesso `spritelayout` e usato anche da `gfx_ninjemak` (`galivan.cpp:1109`): cambia solo la base colore.

---

## 8. Palette (PROM, doppia indirezione)

`PALETTE(config, m_palette, FUNC(galivan_state::palette), 16*16+16*16+256*16, 256)` = 4608 pen e
**256 colori indiretti** (`galivan.cpp:1240`). Nessuna palette RAM esiste nello spazio della CPU: i
colori sono fissi nelle PROM (`galivan.cpp:726-735`, `galivan.cpp:355-367`).

### 8.1 CLUT a 256 voci
`r = pal4bit(prom[i+0x000]); g = pal4bit(prom[i+0x100]); b = pal4bit(prom[i+0x200]);` per i = 0..0xFF
(`galivan.cpp:360-366`). Tre PROM 82S129 da 256x4 bit; RGB444 espanso a 8 bit per replicazione del
nibble (comportamento di `pal4bit`, definito in `emupal.h`, non in questo file).

### 8.2 Mappatura pen -> ctabentry

| Layer | Pen index | Formula | Range ctabentry | Citazione |
|---|---|---|---|---|
| char | 0x000-0x0FF | `(i & 0x0f) + ((i >> ((i & 0x08) ? 2 : 0)) & 0x30)` | 0x00-0x3F | `galivan.cpp:375-379` |
| background | 0x100-0x1FF | `0xc0 + (i & 0x0f) + ((i >> ((i & 0x08) ? 2 : 0)) & 0x30)` | 0xC0-0xFF | `galivan.cpp:385-389` |
| sprite | 0x200-0x11FF | `0x80 + ((i << ((i & 0x80) ? 2 : 4)) & 0x30) + (color_prom[i >> 4] & 0x0f)` | 0x80-0xBF | `galivan.cpp:396-401` |

L'intervallo 0x40-0x7F della CLUT non e raggiungibile da nessun layer (derivato da `galivan.cpp:377`,
`galivan.cpp:387`, `galivan.cpp:398`): utile come sanity check in simulazione.

### 8.3 Formule runtime per il core (nessuna tabella da 4096 voci)
- **Char** (base 0x00) e **background** (base 0xC0), con `color` = `(attr & 0x78) >> 3` e `pen` a 4 bit:
  `bank = pen[3] ? color[3:2] : color[1:0]`;
  `ctabentry = base + (bank << 4) + pen`
  (derivato da `galivan.cpp:377`, `galivan.cpp:387`, `galivan.cpp:372-374`, `galivan.cpp:382-384`).
- **Sprite**, con `color_attr` = `(attr & 0x3c) >> 2`, `palbank` = `m_sprpalbank[code >> 2] & 0x0f`:
  `lut_addr[7:0] = { color_attr[3:0], pen[3:0] }`;
  `bank2 = pen[3] ? palbank[3:2] : palbank[1:0]`;
  `ctabentry = 0x80 + (bank2 << 4) + (sprite_lut[lut_addr] & 0x0f)`
  (derivato invertendo `i_swapped = ((i & 0x0f) << 8) + ((i & 0xff0) >> 4)`, `galivan.cpp:399-401`, con `galivan.cpp:398`, `galivan.cpp:646`, `galivan.cpp:1103`).
- Verifica della decodifica: da `i_swapped = color_code*16 + pen` e `color_code = color_attr + 16*palbank` segue `i = {color_attr, pen, palbank}`, quindi `i >> 4 = {color_attr, pen}` e `i & 0x80 = pen[3]` (`galivan.cpp:396-401`).
- Il commento del sorgente dichiara esplicitamente il doppio banco: *"The PROM selects the bank separately for pens 0-7 and 8-15 (like for tiles)"* (`galivan.cpp:392-395`).
- Il pen 15 non e mai visibile (transparent pen per testo e sprite), quindi le 16 voci della LUT sprite con nibble basso 0xF sono di fatto inutilizzate (`galivan.cpp:516`, `galivan.cpp:648`, `galivan.cpp:398`).

### 8.4 Le cinque PROM

| File | Regione / offset | Ruolo | Citazione |
|---|---|---|---|
| `82s129.9f` | `proms` @0x000 | rosso (4 bit) | `galivan.cpp:1423` |
| `82s129.10f` | `proms` @0x100 | verde (4 bit) | `galivan.cpp:1424` |
| `82s129.11f` | `proms` @0x200 | blu (4 bit) | `galivan.cpp:1425` |
| `82s129.2d` | `proms` @0x300 | sprite look-up table, indirizzata da `{color_attr, pen}`, 4 bit usati | `galivan.cpp:1426`, `galivan.cpp:370`, `galivan.cpp:398` |
| `82s129.7f` | `sprpalbank_prom` @0x000 (regione separata da 0x100) | sprite palette bank, indirizzata da `code >> 2`, 4 bit usati | `galivan.cpp:1428-1429`, `galivan.cpp:646` |

Le due PROM sprite hanno ruoli diversi e non vanno confuse: `2d` entra nella tabella colore, `7f`
entra nel calcolo del color code a runtime (`galivan.cpp:398` vs `galivan.cpp:646`). Il nibble alto
di tutte e cinque va mascherato (`galivan.cpp:362-364`, `galivan.cpp:398`, `galivan.cpp:646`).

---

## 9. Ingressi e DIP

Tutta la sezione ingressi di dangar e `PORT_INCLUDE(galivan)` piu 5 `PORT_MODIFY`
(`galivan.cpp:962-992`).

### 9.1 P1 (0x00), P2 (0x01), SYSTEM (0x02) — tutti `IP_ACTIVE_LOW`

| Bit | P1 / P2 | SYSTEM | Citazione |
|---|---|---|---|
| 0 | JOY UP (8-way) | START1 | `galivan.cpp:879`, `galivan.cpp:899` |
| 1 | JOY DOWN | START2 | `galivan.cpp:880`, `galivan.cpp:900` |
| 2 | JOY LEFT | COIN1 | `galivan.cpp:881`, `galivan.cpp:901` |
| 3 | JOY RIGHT | COIN2 | `galivan.cpp:882`, `galivan.cpp:902` |
| 4 | BUTTON1 | SERVICE1 | `galivan.cpp:883`, `galivan.cpp:903` |
| 5 | BUTTON2 | `PORT_SERVICE` (toggle in dangar) | `galivan.cpp:884`, `galivan.cpp:971-972` |
| 6 | UNKNOWN | UNKNOWN | `galivan.cpp:885`, `galivan.cpp:905` |
| 7 | UNKNOWN in dangar (BUTTON3 in galivan) | UNKNOWN | `galivan.cpp:965-969`, `galivan.cpp:906` |

A riposo queste tre porte devono leggere **0xFF**. `dangar` ha solo 2 pulsanti per giocatore
(`galivan.cpp:965-969`). Nessun `IPT_TILT` in tutto il file (`galivan.cpp:898-906`).
In `galivan` il service era `PORT_SERVICE_NO_TOGGLE` (`galivan.cpp:904`), in `dangar` e
`PORT_SERVICE` cioe un interruttore mantenuto (`galivan.cpp:972`).

### 9.2 DSW1 (porta 0x03) — valori letti dalla CPU

| Bit | SW | Funzione | Valori | Citazione |
|---|---|---|---|---|
| 1-0 | SW1:1,2 | Lives | 0x03=3, 0x02=4, 0x01=5, 0x00=6 | `galivan.cpp:909-913` |
| 3-2 | SW1:3,4 | Bonus Life | 0x0c=20k/60k, 0x08=50k/60k, 0x04=20k/90k, 0x00=50k/90k | `galivan.cpp:923-927` |
| 4 | SW1:5 | Demo Sounds | 0x10=On, 0x00=Off | `galivan.cpp:928-930` |
| 5 | SW1:6 | Cabinet | 0x00=Upright (**default**), 0x20=Cocktail | `galivan.cpp:931-933` |
| 6 | SW1:7 | sconosciuto in dangar (default 0x40) | `PORT_DIPUNKNOWN_DIPLOC` | `galivan.cpp:975` |
| 7 | SW1:8 | Alternate Enemies | 0x80=Off, 0x00=On | `galivan.cpp:976-978` |

**Default DSW1 = 0xDF.**

### 9.3 DSW2 (porta 0x04)

| Bit | SW | Funzione | Valori | Citazione |
|---|---|---|---|---|
| 1-0 | SW2:1,2 | Coin A | 0x01=2C/1C, 0x03=1C/1C, 0x02=1C/2C, 0x00=Free Play | `galivan.cpp:942-946` |
| 3-2 | SW2:3,4 | Coin B (**rimappato in dangar**) | 0x04=2C/1C, 0x0c=1C/1C, 0x00=2C/3C, 0x08=1C/2C | `galivan.cpp:981-985` |
| 4 | SW2:5 | Difficulty | 0x10=Easy, 0x00=Hard | `galivan.cpp:952-954` |
| 5 | SW2:6 | Flip Screen | 0x20=Off, 0x00=On (letto dal software, vedi T22) | `galivan.cpp:955-957` |
| 7-6 | SW2:7,8 | Allow Continue (**solo in dangar**) | 0xc0=No, 0x80=3 volte, 0x40=5 volte (**default**), 0x00=99 volte | `galivan.cpp:987-991` |

**Default DSW2 = 0x7F.** In galivan i bit 7-6 erano `PORT_DIPUNUSED` (`galivan.cpp:958-959`).

Nota: i banchi DSW non sono dichiarati con `IP_ACTIVE_LOW`; il valore di ogni `PORT_DIPSETTING` e
direttamente il byte che la CPU deve leggere (`galivan.cpp:908-959`, `galivan.cpp:974-991`).
Solo il set `dangar` usa questo blocco di ingressi: `dangara`, `dangarj` e `dangarb` usano `dangar2`
(`galivan.cpp:1912-1916`).

---

## 10. Audio

Tutta la sezione audio e in `common()` e non e toccata da `galivan()`: e identica per dangar
(`galivan.cpp:1166-1227`, `galivan.cpp:1229-1241`).

### 10.1 CPU sonora
- Z80 `XTAL(8'000'000) / 2` = **4.000000 MHz**, commento `// 4 MHz?` (`galivan.cpp:1172`).
- `sound_map`: `map(0x0000,0xbfff).rom(); map(0xc000,0xc7ff).ram();` — 48 KB ROM + **2 KB RAM**; 0xC800-0xFFFF non mappato, nessun mirror dichiarato (`galivan.cpp:854-858`).
- Istanziata come variabile locale con tag `"audiocpu"`, senza `required_device`: nulla nel driver puo resettarla o interromperla oltre al reset globale (`galivan.cpp:1172`).

### 10.2 `sound_io_map` (`galivan.cpp:860-868`) — `global_mask(0xff)`

| Porta | Direzione | Funzione | Citazione |
|---|---|---|---|
| 0x00-0x01 | **solo W** | YM3526 (`ym3526_device::write`) | `galivan.cpp:863` |
| 0x02 | solo W | DAC1 (`dac_byte_interface::data_w`) | `galivan.cpp:864` |
| 0x03 | solo W | DAC2 | `galivan.cpp:865` |
| 0x04 | **solo R** | `soundlatch_clear_r`: azzera il latch e ritorna sempre 0 | `galivan.cpp:866`, `galivan.cpp:707-711` |
| 0x06 | solo R | lettura del latch (nessun effetto sul valore) | `galivan.cpp:867` |

0x05 e 0x07-0xFF non sono mappati; le letture di 0x00-0x03 e le scritture di 0x04/0x06 cadono su
spazio non mappato (`galivan.cpp:860-868`). Non esiste alcuna lettura dello status del YM3526
(`galivan.cpp:863`): combinato con l'assenza di IRQ dall'OPL (`galivan.cpp:1222`), il programma
sonoro non puo usare ne status ne timer del chip.

### 10.3 Catena audio
- Uscita **mono**: `SPEAKER(config, "speaker").front_center()` (`galivan.cpp:1186`).
- YM3526 (OPL) a `XTAL(8'000'000)/2` = 4.000 MHz, route verso `m_ymfilter` con volume **0.4922** (`galivan.cpp:1222`).
- `DAC_8BIT_R2R "dac1"` -> `m_dacfilter1` volume **0.2095**; `"dac2"` -> `m_dacfilter2` volume **0.2983**; hardware = SIP R2R con latch 74HC374P (`galivan.cpp:1225-1226`). Il latch mantiene l'ultimo byte scritto fino alla scrittura successiva.
- Ogni filtro entra nello speaker con guadagno 1.0: la catena e sorgente -> volume -> biquad -> speaker (`galivan.cpp:1212`, `galivan.cpp:1216`, `galivan.cpp:1220`).
- Filtri Sallen-Key passa-basso a guadagno unitario:
  - YM: `opamp_sk_lowpass_setup(RES_K(4.7), RES_K(4.7), RES_M(999.99), RES_R(0.001), CAP_N(3.3), CAP_N(1.0))` (R15, R14, aperto, corto, C9, C11) (`galivan.cpp:1210-1211`);
  - DAC1 e DAC2 identici: `opamp_sk_lowpass_setup(RES_K(10), RES_K(10), RES_M(999.99), RES_R(0.001), CAP_N(10), CAP_N(4.7))` (`galivan.cpp:1214-1215`, `galivan.cpp:1218-1219`).
- Motivazione dei pesi, dal commento del sorgente: resistenze di somma Yamaha 1 kohm = 0.6597, DAC1 4.7 kohm = 0.1404, DAC2 3.3 kohm = 0.1999; il YM3014 esce 1.25-3.75 V (Vpp 2.5 V) contro 0-5 V (Vpp ~5.0 V) dei R2R, da cui il fattore 0.5 sul ramo FM e la normalizzazione per 1/0.67015 = 1.492203, con valori finali ym 0.492203, dac1 0.209505, dac2 0.298291 (`galivan.cpp:1190-1208`).
- Nel core: mix = 0.4922*YM + 0.2095*DAC1 + 0.2983*DAC2 su un unico canale, duplicato su L/R (`galivan.cpp:1222`, `galivan.cpp:1225-1226`, `galivan.cpp:1186`).

### 10.4 Comunicazione main -> sound
- Unidirezionale: la main CPU scrive su I/O 0x45 (`galivan.cpp:759`), il valore latchato e `((data & 0x7f) << 1) or 1` (`galivan.cpp:702-705`).
- La sound CPU legge il comando su 0x06 e lo consuma leggendo 0x04 (`galivan.cpp:866-867`, `galivan.cpp:707-711`).
- Nessun interrupt generato dal latch (`galivan.cpp:1188`), nessun handshake di ritorno (`galivan.cpp:748-763`).

---

## 11. Caricamento ROM (per la MRA) — `ROM_START( dangar )`, `galivan.cpp:1395-1430`

| Regione | Dim. | File | Offset | Citazione |
|---|---|---|---|---|
| `maincpu` | 0x14000 | `8.1b` | 0x00000 (0x8000) | `galivan.cpp:1397` |
| | | `9.3b` | 0x08000 (0x4000) | `galivan.cpp:1398` |
| | | `10.4b` | **0x10000** (0x4000) — i due banchi da 8 KB | `galivan.cpp:1399` |
| | | *(buco)* | 0x0C000-0x0FFFF non caricato | `galivan.cpp:1396-1399` |
| `audiocpu` | 0x10000 | `13.b14` | 0x00000 (0x4000) | `galivan.cpp:1402` |
| | | `14.b15` | 0x04000 (0x8000) — totale 0xC000 contigui | `galivan.cpp:1403` |
| `chars` | 0x04000 | `5.13d` | 0x00000 (0x4000) | `galivan.cpp:1406` |
| `tiles` | 0x20000 | `1.14f`, `2.15f`, `3.17f`, `4.19f` | 0x00000 / 0x08000 / 0x10000 / 0x18000 (0x8000 ciascuna) | `galivan.cpp:1409-1412` |
| `sprites` | 0x10000 | `12.f4` | 0x00000 (0x8000) = meta A | `galivan.cpp:1415` |
| | | `11.f1` | 0x08000 (0x8000) = meta B | `galivan.cpp:1416` |
| `bgtiles` | 0x08000 | `7.19d` | 0x00000 (0x4000) = codici mappa | `galivan.cpp:1419` |
| | | `6.17d` | 0x04000 (0x4000) = attributi mappa | `galivan.cpp:1420` |
| `proms` | 0x00400 | `82s129.9f` / `.10f` / `.11f` / `.2d` | 0x000 / 0x100 / 0x200 / 0x300 | `galivan.cpp:1423-1426` |
| `sprpalbank_prom` | 0x00100 | `82s129.7f` | 0x000 | `galivan.cpp:1429` |

Due regioni hanno ordine di caricamento **invertito** rispetto alla numerazione delle etichette:
`bgtiles` (7 prima di 6) e `sprites` (12 prima di 11) (`galivan.cpp:1415-1416`, `galivan.cpp:1419-1420`).
Il set fratello `dangara` ha ROM audio con gli stessi CRC ma etichette diverse (`galivan.cpp:1438-1440`);
le ROM audio di `galivan` sono invece dati diversi (`galivan.cpp:1290-1292`): niente cross-loading.

---

## 12. Hardware fisico non modellato e note PCB fuorvianti

- Le note "Hardware info by Guru" in testa al file (`galivan.cpp:29-30`) descrivono le board **YN-1(1510) / YN-2(1510) di Ninja Emaki / Youma Ninpou Chou** (`galivan.cpp:39`, `galivan.cpp:89`), non la GV-1412-I/II di dangar (`galivan.cpp:1912`). Prova: le PROM colore Guru sono MB7114 in 6E/7E/8E (`galivan.cpp:80-82`) mentre dangar ha 82S129 in 9f/10f/11f (`galivan.cpp:1423-1425`); Guru elenca 4 EPROM sprite (`galivan.cpp:124-127`) mentre dangar ne ha 2 (`galivan.cpp:1415-1416`); Guru da la ROM caratteri da 32 kB (`galivan.cpp:72`) mentre dangar ne ha una da 16 kB (`galivan.cpp:1406`).
- Da quelle note restano indicativi: TMM2015 2 kB come character RAM (`galivan.cpp:65`), HM6264 8 kB come main program RAM (`galivan.cpp:66`), 6116 2 kB come sound program RAM (`galivan.cpp:120`), 2148 1 kB x4 come sprite RAM (`galivan.cpp:119`), MB7114 256x4 sprite palette bank in 7F e look-up table in 2D (`galivan.cpp:128-129`), Z80B 6.000 MHz [12/2] (`galivan.cpp:64`), Z80A 4.000 MHz [8/2] (`galivan.cpp:114`), YM3526 4.000 MHz [8/2] (`galivan.cpp:115`), YM3014 1.000 MHz (`galivan.cpp:116`), MB3730 finale di potenza e due MB3614 quad op-amp (`galivan.cpp:117-118`, `galivan.cpp:93-94`).
- L'OSC da 22 MHz della bottom board (`galivan.cpp:111`) non e usato da nessun device: gli unici quarzi istanziati sono 12 MHz e 8 MHz (`galivan.cpp:1169`, `galivan.cpp:1172`, `galivan.cpp:1175`, `galivan.cpp:1181`, `galivan.cpp:1222`).
- Chip presenti nel disegno ma assenti dal machine_config: PAL.10F (`galivan.cpp:50`), PAL.1B (`galivan.cpp:61`), PAL.12F (`galivan.cpp:96`), Nichibutsu 1411M1 (`galivan.cpp:103`, `galivan.cpp:121`).

---

## 13. DOMANDE APERTE

Tutto quanto sta sopra e derivato dal sorgente. Quanto segue **non e deciso da `galivan.cpp`** e va
risolto su hardware o in simulazione. E diviso in due gruppi.

### 13.A Fatti che stanno FUORI da questo file (necessari per compilare, da recuperare altrove)

1. **Layout dei caratteri e dei tile.** `gfx_8x8x4_packed_lsb` e `gfx_16x16x4_packed_lsb` sono solo referenziati (`galivan.cpp:1101-1102`); non esistono in questo file. Dal file si deducono solo 32 byte per char e 128 byte per tile (dalle dimensioni delle regioni, `galivan.cpp:1405`, `galivan.cpp:1408`, e dai bit di codice, `galivan.cpp:470`, `galivan.cpp:460`). **L'ordine dei due nibble dentro il byte e l'ordine dei 4 piani vanno letti da `emupal.h` di MAME.** Lo `spritelayout` esplicito (`galivan.cpp:1087-1098`) NON e una guida valida: ha uno swap di nibble a coppie e l'intreccio fra le due meta della regione.
2. **Flip screen dei due tilemap.** L'unico punto del file e `flip_screen_set(data & 0x04)` (`galivan.cpp:549`); l'unico uso visibile del flag e negli sprite (`galivan.cpp:620`, `galivan.cpp:633-639`). Il ribaltamento dei tilemap avviene dentro `driver_device::flip_screen_set` di MAME, fuori da questo file: offset e allineamento esatti del tx 32x32 e del bg in modalita flip vanno verificati altrove.
3. **Semantica di `transpen`, `pal4bit`, dei mapper `TILEMAP_SCAN_*`, del wrap `code % elements()` e di `generic_latch_8_device`** (valore restituito da 0x06 dopo un `clear_w`, quindi il valore di reset del latch nel core): tutte definite negli header MAME (`galivan.cpp:134`, `galivan.cpp:140-144`), non qui.
4. **Formato dei DAC.** `DAC_8BIT_R2R` (`galivan.cpp:1225-1226`): che i campioni siano unsigned e desunto dal nome del device e dal commento *"The R2R dacs are full range, min of 0v and max of (almost) 5v"* (`galivan.cpp:1200`), non da una dichiarazione esplicita. Va confermato in `sound/dac.h` (unsigned vs twos-complement) prima di scegliere l'offset di mix.
5. **Modo di interrupt dello Z80.** Ne `common()` ne `galivan()` configurano IM, vettore o daisy chain per nessuna delle due CPU (`galivan.cpp:1166-1227`): quale IM usino i programmi e quale byte finisca sul bus durante l'INTA va letto dalle ROM.

### 13.B Punti che MAME stessa marca come incerti

1. **Bit 9 del codice sprite (impatto ALTO, decidere prima di scrivere il core).** La riga attiva e `code = spriteram[offs+1] + ((attr & 0x06) << 7)` con commento `// for ninjemak, not sure ?`; la riga sopra, commentata, e la variante a 9 bit `((attr & 0x02) << 7)` (`galivan.cpp:641-642`). Il commento di formato in testa al file documenta bit 1 = `sprite(hi)` e bit 5-2 = color, cioe la variante a 9 bit (`galivan.cpp:321-322`). Per dangar la grafica ha solo 512 tile, quindi il bit 9 non cambia la tile, **ma cambia `code >> 2` e quindi usa la meta alta della PROM `sprpalbank`** (`galivan.cpp:646`): la scelta cambia i colori degli sprite. Ulteriore contraddizione interna: il commento a `galivan.cpp:394` dice che il banco dipende dai *"top 7 bits of the sprite code"*, coerente solo con la variante a 9 bit.
2. **Abilitazione dei layer.** TODO *"Find out how layers are enabled\disabled"* (`galivan.cpp:21`). La semantica dei bit 7/6/5 di `m_layers` e un commento non verificato (`galivan.cpp:334-339`), e del bit 5 il commento dice che e attivo *"only on title screen, not for scores or push start nor game"* (`galivan.cpp:337-339`).
3. **Bit 4 e 3 della porta 0x42**: non sono ne scroll (`& 0x07`, `galivan.cpp:655`) ne layer (`& 0xe0`, `galivan.cpp:597`). Funzione ignota.
4. **Bit 3, 4, 5, 6 della porta 0x40**: mai letti per dangar (`galivan.cpp:542-555`), nessun commento che li descriva. Il TODO *"bit 3 of gfxbank_w, there currently is a kludge to clear text RAM but it should really copy stuff from the extra ROM"* (`galivan.cpp:24-25`) e obsoleto: nel corpo di `galivan_state::gfxbank_w` non esiste alcun kludge, e il bit 3 e commentato `// bit 3 unknown` solo nel ramo ninjemak (`galivan.cpp:566`). Vanno considerati "non implementati", non "assenti dall'hardware".
5. **Campi colore marcati `// seems correct`**: `(attr & 0x78) >> 3` per il background (`galivan.cpp:463`) e per il testo (`galivan.cpp:473`), e la category del testo (`galivan.cpp:475`).
6. **Banchi di palette del background**: *"I think that background tiles use colors 0xc0-0xff in four banks"* (`galivan.cpp:382-384`). Il range 0xC0-0xFF e la regola dei due banchi 2+2 bit potrebbero non essere esatti sull'hardware.
7. **Bit non documentati nelle strutture dati**: attributo testo bit 7 e bit 2-1 = `?` (`galivan.cpp:310-312`); attributo background bit 7 e bit 2 = `?` (`galivan.cpp:327-329`). Possibile flip, possibile priorita, possibili bit di codice non emulati.
8. **Clock**: `// 6 MHz?` sul main Z80 (`galivan.cpp:1169`) e `// 4 MHz?` sull'audio (`galivan.cpp:1172`). Le note Guru danno 6.000 e 4.000 MHz esatti (`galivan.cpp:64`, `galivan.cpp:114`) ma sono di un'altra board (cap. 12).
9. **Divisore dell'IRQ sonoro**: `XTAL(8'000'000) / 2 / 512` porta il commento `// ?` (`galivan.cpp:1175`). Se la musica risultasse fuori tempo, il /512 e il primo sospetto.
10. **Volumi dei due DAC possibilmente scambiati**: *"note the two dac channel volume mix values might be backwards, we need a PCB reference recording!"* (`galivan.cpp:1224`).
11. **Porta main 0x46**: la riga `nopw` e commentata (`galivan.cpp:760`). Una `nopw` di solito viene aggiunta perche il gioco ci scrive davvero: non e chiaro se l'hardware la decodifichi.
12. **Letture I/O non mappate** (main: 0x05-0x3F, 0x40-0xBF, 0xC1-0xFF; sound: 0x00-0x03, 0x05, 0x07-0xFF): nessun handler, nessun unmap value esplicito (`galivan.cpp:748-763`, `galivan.cpp:860-868`). Il file non dice cosa legga la CPU; scelta tipica nel core 0xFF, ma non e un fatto.
13. **Mirror della RAM sonora**: `0xc800-0xffff` non e mappato (`galivan.cpp:854-858`); il file non dice se sul PCB il 6116 sia rispecchiato.
14. **Rilettura della char RAM**: MAME restituisce la ROM bancata perche installa solo `.bankr` + `.w` (`galivan.cpp:730-731`); il file non dice se sul PCB reale la TMM2015 sia rileggibile dalla CPU. Il driver assume solo che il gioco non la rilegga.
15. **Banco ROM dopo un soft reset**: `set_entry(0)` sta solo in `machine_start` (`galivan.cpp:1119`) e non in `machine_reset` (`galivan.cpp:1148-1155`), quindi in MAME il banco sopravvive a un reset a caldo. Sull'hardware il latch e presumibilmente azzerato dal RESET: nel core conviene azzerarlo, ma non e derivabile dal file.
16. **Service mode**: il TODO dice *"dangar input ports - parent set requires F2 be held for Service Mode"* (`galivan.cpp:22`), mentre il set usa `PORT_SERVICE(0x20, IP_ACTIVE_LOW)` cioe un interruttore a toggle (`galivan.cpp:971-972`). Le due cose non concordano.
17. **Cosa sia davvero la porta 0xC0**: il sorgente da solo il valore fisso 0x58 e il commento sul reset (`galivan.cpp:713-717`); il commento del bootleg `dangarb` aggiunge *"(also checks I/O port 0xc0?)"* con punto interrogativo (`galivan.cpp:1915`). Non e noto quali bit il programma confronti davvero.
18. **Wrap delle coordinate sprite**: `sx` e `sy` sono int con segno mai mascherati e MAME si limita a clippare (`galivan.cpp:631-632`, `galivan.cpp:644-648`). Non e detto se l'hardware faccia wrap a 9 bit su X e a 8 bit su Y, cosa che mostrerebbe sprite dove MAME non ne mostra.
19. **Colore di "background spento"**: `bitmap.fill(0)` da il colore indiretto 0 delle PROM (`galivan.cpp:658-659`, `galivan.cpp:377`); non e documentato se l'hardware reale emetta quel colore o forzi il nero.
20. **Doppio buffer sprite sull'hardware**: MAME modella una copia software a inizio VBLANK (`galivan.cpp:1178`, `galivan.cpp:1182`). Le note Guru elencano sei SRAM 2148 come sprite RAM (`galivan.cpp:97-98`, `galivan.cpp:105-106`, `galivan.cpp:119`), molto piu dei 256 byte mappati (`galivan.cpp:733`): non e deducibile se sul PCB ci sia un banco doppio, un buffer di riga o altro (e quelle note sono comunque di un'altra board).
