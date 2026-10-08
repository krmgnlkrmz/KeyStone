#!/usr/bin/env python3
"""Writes Tools/LevelForge/curation-plan.json: one slot per curated level 8–80 (1–7 are hand-made drafts).

Each slot names the archetype, the region, a seed range for the generator, the solution-length band the
slot needs (the difficulty curve), the slack added to the move budget, and the level's name (EN/TR).
LevelForge's testCuratePlan takes the first candidate in the seed range that passes the solver and the
slot's bar. Edit this script, not the JSON.
"""
import json, os

NAMES = {
    8: ("Short Span", "Kısa Açıklık"), 9: ("Two Floors", "İki Kat"), 10: ("Loose Plank", "Gevşek Tahta"),
    11: ("Lintel", "Lento"), 12: ("Quiet Pyramid", "Sessiz Piramit"), 13: ("Column Stack", "Sütun Yığını"),
    14: ("Held Breath", "Tutulan Nefes"), 15: ("Corbel", "Konsol"), 16: ("Gate of Blocks", "Bloklu Kapı"),
    17: ("Two Pillars", "İki Ayak"), 18: ("Stepped Base", "Basamaklı Taban"), 19: ("Capstone", "Başlık Taşı"),
    20: ("Last Arch", "Son Kemer"),
    21: ("Rivet Line", "Perçin Hattı"), 22: ("Girder Table", "Putrel Masa"), 23: ("Cold Frame", "Soğuk Çerçeve"),
    24: ("Iron Stack", "Demir Yığın"), 25: ("Bolted", "Cıvatalı"), 26: ("Cross Member", "Ara Eleman"),
    27: ("Truss Deck", "Kafes Döşeme"), 28: ("Steel Shelf", "Çelik Raf"), 29: ("Load Path", "Yük Yolu"),
    30: ("Foundry", "Dökümhane"),
    31: ("First Rope", "İlk Halat"), 32: ("Hanging Deck", "Asılı Döşeme"), 33: ("Slack", "Boşluk"),
    34: ("Two Lines", "İki Hat"), 35: ("Swing", "Salınım"), 36: ("Plumb Line", "Çekül"), 37: ("Ferry", "Sal"),
    38: ("Tether", "Bağ"), 39: ("Knot", "Düğüm"), 40: ("Rope Walk", "Halat Yolu"),
    41: ("Jib", "Bom"), 42: ("Hook Load", "Kanca Yükü"), 43: ("Mast", "Kule Direği"), 44: ("Trolley", "Araba"),
    45: ("Balance Arm", "Denge Kolu"), 46: ("Hoist", "Vinç"), 47: ("Outrigger", "Destek Ayağı"),
    48: ("Gantry", "Portal"), 49: ("Ballast", "Safra"), 50: ("Topping Out", "Tepe Töreni"),
    51: ("First Prop", "İlk Payanda"), 52: ("Shore", "Dayanak"), 53: ("Under the Load", "Yükün Altında"),
    54: ("Jack Post", "Kriko Direği"), 55: ("Temporary Works", "Geçici İşler"), 56: ("Seesaw", "Tahterevalli"),
    57: ("Even Keel", "Dengede"), 58: ("Pivot", "Mil"), 59: ("Spread Load", "Yayılı Yük"),
    60: ("Needle Beam", "İğne Kiriş"), 61: ("Fulcrum", "Dayanak Noktası"), 62: ("Scales", "Terazi"),
    63: ("Shoring", "Payandalama"), 64: ("Tip Point", "Devrilme Noktası"), 65: ("Counterpoise", "Karşılık"),
    66: ("Dead Load", "Ölü Yük"), 67: ("Live Load", "Hareketli Yük"), 68: ("Propped", "Desteklenmiş"),
    69: ("Equilibrium", "Denge"), 70: ("Moment", "Moment"),
    71: ("Voussoir", "Kemer Taşı"), 72: ("Springing", "Kemer Ayağı"), 73: ("Crown", "Tepe"),
    74: ("Haunch", "Kemer Omzu"), 75: ("Centering", "Kemer Kalıbı"), 76: ("Thrust", "İtki"),
    77: ("Corbel Vault", "Bindirme Tonoz"), 78: ("Abutment", "Yan Ayak"), 79: ("Keystone Set", "Kilit Yerinde"),
    80: ("Point of Balance", "Denge Noktası"),
}

# (first index, last index, region, archetype cycle, length band per position, slack, extra)
CURRICULUM = [
    (8, 10, "wood_scaffold", ["table", "tower", "table"], lambda i: (2, 2), 1, {}),
    (11, 20, "stone_arch", ["lintel", "pyramid", "tower"], lambda i: (2, 2) if i < 15 else (2, 3), 1, {}),
    (21, 30, "iron_truss", ["table", "tower"], lambda i: (2, 3) if i < 26 else (3, 4), 1, {}),
    (31, 40, "rope_bridge", ["hanger"], lambda i: (2, 2) if i < 35 else (2, 3), 1, {}),
    (41, 50, "steel_crane", ["hanger", "counterweight"], lambda i: (2, 3) if i < 46 else (3, 4), 1, {}),
    (51, 60, "counterweight", ["bridge"], lambda i: (3, 3) if i < 56 else (3, 4), 1, {"goal": "placeSupportThenRemove"}),
    (61, 70, "counterweight", ["counterweight", "bridge"], lambda i: (3, 4) if i < 66 else (4, 5), 2, {}),
    (71, 80, "keystone", ["pyramid", "lintel"], lambda i: (3, 4) if i < 76 else (4, 5), 2, {}),
]

# Per-slot corrections from forge runs: an archetype that cannot produce the slot's band is swapped,
# or the band is widened where the archetype's shortest solutions are shorter than planned.
OVERRIDES = {
    11: {"archetype": "tower"},             # lintels need >= 3 moves; 11-14 teach two-move order
    14: {"archetype": "pyramid", "attempts": 90},
    42: {"archetype": "hanger"},            # counterweights need >= 4 moves; 41-45 are short
    44: {"archetype": "hanger"},
    66: {"minLength": 3}, 68: {"minLength": 3}, 70: {"minLength": 3},   # bridges solve in 3
    77: {"minLength": 3}, 79: {"minLength": 3},                         # pyramids solve in 3
}

slots = []
for first, last, region, cycle, band, slack, extra in CURRICULUM:
    for n, index in enumerate(range(first, last + 1)):
        lo, hi = band(index)
        slot = {
            "index": index, "region": region, "archetype": cycle[n % len(cycle)],
            "seed": 100000 + index * 1000, "attempts": 60,
            "minLength": lo, "maxLength": hi, "slack": slack, "minUnsafe": 0.2,
            "name": {"en": NAMES[index][0], "tr": NAMES[index][1]},
        }
        slot.update(extra)
        slot.update(OVERRIDES.get(index, {}))
        if slot["archetype"] != "bridge" and slot.get("goal") == "placeSupportThenRemove":
            del slot["goal"]
        slots.append(slot)

out = os.path.join(os.path.dirname(__file__), "..", "Tools/LevelForge/curation-plan.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump({"slots": slots}, f, indent=1, ensure_ascii=False)
    f.write("\n")
print(f"{len(slots)} slots")
