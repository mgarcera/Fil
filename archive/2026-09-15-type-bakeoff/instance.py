#!/usr/bin/env python3
"""Write static cuts from Gabarito[wght].ttf, named so Font.custom / UIFont(name:) find them."""
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

SRC = "Gabarito[wght].ttf"
CUTS = [("Regular", 400), ("Medium", 500), ("SemiBold", 600), ("Bold", 700)]

for name, weight in CUTS:
    font = instantiateVariableFont(TTFont(SRC), {"wght": weight})
    names = font["name"]
    names.setName(f"Gabarito-{name}", 6, 3, 1, 0x409)   # PostScript name, what the app asks for
    names.setName("Gabarito", 1, 3, 1, 0x409)
    names.setName(name, 2, 3, 1, 0x409)
    names.setName(f"Gabarito {name}", 4, 3, 1, 0x409)
    names.setName("Gabarito", 16, 3, 1, 0x409)
    names.setName(name, 17, 3, 1, 0x409)
    font.save(f"Gabarito-{name}.ttf")
    print("wrote", f"Gabarito-{name}.ttf")
