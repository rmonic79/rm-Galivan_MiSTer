#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# This file is part of rmGalivan_MiSTer.
# Author: Umberto Parisi (rmonic79)
"""Genera font_6x8.hex — font a celle da 6 px per l'overlay di pausa.

PERCHE'
font_darius.hex e' 8x8 e i glifi usano davvero tutte e otto le colonne
(verificato: W, X, Z arrivano all'ottava). Nello spazio pre-ruotato
dell'overlay la larghezza utile e' 224 px, quindi con celle da 8 px il tetto e'
28 caratteri per riga — e i link ne vogliono 30
(YOUTUBE.COM/IBECERIVIDEOLUDICI). Con celle da 6 px si arriva a 37.

FORMA
Glifo 5 px di larghezza + 1 px di spazio a destra, 7 righe + 1 vuota sotto.
Formato identico a quello che pause_text si aspetta: 8 byte per carattere, una
riga per byte, BIT 7 = COLONNA 0 (pause_text.sv:155 fa font_row[7 - pix_col]).
Le colonne 5, 6 e 7 restano a zero.

COPERTURA
0x20-0x5F, che e' l'intervallo che l'overlay usa davvero (gen_msg.py porta
tutto a maiuscolo e mappa fuori range su spazio).
"""

import io, os, sys

# Ogni glifo: 7 righe da 5 caratteri, '#' acceso. L'ottava riga e' vuota.
G = {
' ': ["     "]*7,
'!': ["  #  ","  #  ","  #  ","  #  ","  #  ","     ","  #  "],
'"': [" # # "," # # ","     ","     ","     ","     ","     "],
'#': [" # # "," # # ","#####"," # # ","#####"," # # "," # # "],
'$': ["  #  "," ####","# #  "," ### ","  # #","#### ","  #  "],
'%': ["##   ","##  #","   # ","  #  "," #   ","#  ##","   ##"],
'&': [" ##  ","#  # "," ##  "," ##  ","#  ##","#  # "," ## #"],
"'": ["  #  ","  #  ","     ","     ","     ","     ","     "],
'(': ["   # ","  #  "," #   "," #   "," #   ","  #  ","   # "],
')': [" #   ","  #  ","   # ","   # ","   # ","  #  "," #   "],
'*': ["     ","# # #"," ### ","#####"," ### ","# # #","     "],
'+': ["     ","  #  ","  #  ","#####","  #  ","  #  ","     "],
',': ["     ","     ","     ","     ","  ## ","  ## ","  #  "],
'-': ["     ","     ","     ","#####","     ","     ","     "],
'.': ["     ","     ","     ","     ","     ","  ## ","  ## "],
'/': ["    #","    #","   # ","  #  "," #   ","#    ","#    "],
'0': [" ### ","#   #","#  ##","# # #","##  #","#   #"," ### "],
'1': ["  #  "," ##  ","  #  ","  #  ","  #  ","  #  "," ### "],
'2': [" ### ","#   #","    #","   # ","  #  "," #   ","#####"],
'3': ["#####","   # ","  #  ","   # ","    #","#   #"," ### "],
'4': ["   # ","  ## "," # # ","#  # ","#####","   # ","   # "],
'5': ["#####","#    ","#### ","    #","    #","#   #"," ### "],
'6': ["  ## "," #   ","#    ","#### ","#   #","#   #"," ### "],
'7': ["#####","    #","   # ","  #  "," #   "," #   "," #   "],
'8': [" ### ","#   #","#   #"," ### ","#   #","#   #"," ### "],
'9': [" ### ","#   #","#   #"," ####","    #","   # "," ##  "],
':': ["     ","  ## ","  ## ","     ","  ## ","  ## ","     "],
';': ["     ","  ## ","  ## ","     ","  ## ","  ## ","  #  "],
'<': ["   # ","  #  "," #   ","#    "," #   ","  #  ","   # "],
'=': ["     ","     ","#####","     ","#####","     ","     "],
'>': [" #   ","  #  ","   # ","    #","   # ","  #  "," #   "],
'?': [" ### ","#   #","    #","   # ","  #  ","     ","  #  "],
'@': [" ### ","#   #","# ###","# # #","# ## ","#    "," ### "],
'A': ["  #  "," # # ","#   #","#   #","#####","#   #","#   #"],
'B': ["#### ","#   #","#   #","#### ","#   #","#   #","#### "],
'C': [" ### ","#   #","#    ","#    ","#    ","#   #"," ### "],
'D': ["###  ","#  # ","#   #","#   #","#   #","#  # ","###  "],
'E': ["#####","#    ","#    ","#### ","#    ","#    ","#####"],
'F': ["#####","#    ","#    ","#### ","#    ","#    ","#    "],
'G': [" ### ","#   #","#    ","# ###","#   #","#   #"," ####"],
'H': ["#   #","#   #","#   #","#####","#   #","#   #","#   #"],
'I': [" ### ","  #  ","  #  ","  #  ","  #  ","  #  "," ### "],
'J': ["    #","    #","    #","    #","#   #","#   #"," ### "],
'K': ["#   #","#  # ","# #  ","##   ","# #  ","#  # ","#   #"],
'L': ["#    ","#    ","#    ","#    ","#    ","#    ","#####"],
'M': ["#   #","## ##","# # #","# # #","#   #","#   #","#   #"],
'N': ["#   #","##  #","# # #","#  ##","#   #","#   #","#   #"],
'O': [" ### ","#   #","#   #","#   #","#   #","#   #"," ### "],
'P': ["#### ","#   #","#   #","#### ","#    ","#    ","#    "],
'Q': [" ### ","#   #","#   #","#   #","# # #","#  # "," ## #"],
'R': ["#### ","#   #","#   #","#### ","# #  ","#  # ","#   #"],
'S': [" ####","#    ","#    "," ### ","    #","    #","#### "],
'T': ["#####","  #  ","  #  ","  #  ","  #  ","  #  ","  #  "],
'U': ["#   #","#   #","#   #","#   #","#   #","#   #"," ### "],
'V': ["#   #","#   #","#   #","#   #","#   #"," # # ","  #  "],
'W': ["#   #","#   #","#   #","# # #","# # #","## ##","#   #"],
'X': ["#   #","#   #"," # # ","  #  "," # # ","#   #","#   #"],
'Y': ["#   #","#   #"," # # ","  #  ","  #  ","  #  ","  #  "],
'Z': ["#####","    #","   # ","  #  "," #   ","#    ","#####"],
'[': [" ### "," #   "," #   "," #   "," #   "," #   "," ### "],
'\\':["#    ","#    "," #   ","  #  ","   # ","    #","    #"],
']': [" ### ","   # ","   # ","   # ","   # ","   # "," ### "],
'^': ["  #  "," # # ","#   #","     ","     ","     ","     "],
'_': ["     ","     ","     ","     ","     ","     ","#####"],
}


def byte_di(riga):
    "bit 7 = colonna 0, come vuole pause_text.sv:155"
    v = 0
    for i, c in enumerate(riga[:5]):
        if c != ' ':
            v |= 0x80 >> i
    return v


def main():
    qui = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(qui, "font_6x8.hex")

    mancanti = [c for c in range(0x20, 0x60) if chr(c) not in G]
    if mancanti:
        print("mancano i glifi per: %s" % " ".join("0x%02X('%s')" % (c, chr(c)) for c in mancanti),
              file=sys.stderr)
        sys.exit(1)

    # Il font ROM e' indicizzato dall'ASCII a 7 bit: 128 caratteri da 8 byte.
    dati = bytearray(128 * 8)
    for c in range(0x20, 0x60):
        righe = G[chr(c)]
        assert len(righe) == 7, chr(c)
        for r, riga in enumerate(righe):
            assert len(riga) == 5, (chr(c), r, riga)
            dati[c * 8 + r] = byte_di(riga)
        dati[c * 8 + 7] = 0x00          # ottava riga vuota

    with io.open(out, "w", newline="\n") as f:
        for b in dati:
            f.write("%02x\n" % b)
    print("scritto %s (%d byte)" % (out, len(dati)))

    if "--mostra" in sys.argv:
        for base in range(0x20, 0x60, 16):
            for r in range(8):
                riga = ""
                for c in range(base, base + 16):
                    b = dati[c * 8 + r]
                    riga += "".join("#" if b & (0x80 >> i) else "." for i in range(6)) + " "
                print(riga)
            print("   " + "     ".join(chr(c) for c in range(base, base + 16)))
            print()


if __name__ == "__main__":
    main()
