#!/usr/bin/env python3
"""Renders level JSON files into a contact sheet PNG for curation review.

usage: python3 scripts/render_levels.py OUT.png level.json [more.json | pool-file.json ...]
Colours follow the design kit; goal targets get a brass outline, fixed pieces a hatch, the solution
path is printed under each cell.
"""
import json, math, sys
from PIL import Image, ImageDraw, ImageFont

COLORS = {"wood": (185, 138, 94), "stone": (168, 162, 150), "steel": (126, 143, 162), "brass": (217, 168, 91), "rope": (217, 207, 184)}
BG, GRID, TEXT, ACCENT, GROUND = (17, 21, 25), (28, 34, 42), (236, 231, 222), (217, 168, 91), (58, 66, 77)
CELL_W, CELL_H = 320, 400


def outline(p):
    s = p["shape"]
    if s["type"] == "rect":
        w, h = s["w"], s["h"]
        pts = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
    else:
        pts = [tuple(q) if isinstance(q, list) else (q["x"], q["y"]) for q in s["points"]]
    r = p.get("rotation", 0)
    c, si = math.cos(r), math.sin(r)
    x0, y0 = p["position"]["x"], p["position"]["y"]
    return [(x0 + x * c - y * si, y0 + x * si + y * c) for x, y in pts]


def draw_level(level, font):
    img = Image.new("RGB", (CELL_W, CELL_H), BG)
    d = ImageDraw.Draw(img)
    floor = level.get("floorY", -190)
    def tx(x, y):
        return (CELL_W / 2 + x * 0.95, CELL_H - 60 - (y - floor) * 0.95)
    d.line([tx(-170, floor), tx(170, floor)], fill=GROUND, width=2)
    targets = set(level["goal"]["targetPieceIds"])
    for p in level["pieces"]:
        pts = [tx(x, y) for x, y in outline(p)]
        d.polygon(pts, fill=COLORS.get(p["material"], (200, 200, 200)), outline=(0, 0, 0))
        if p.get("fixed"):
            xs = [q[0] for q in pts]; ys = [q[1] for q in pts]
            for k in range(int(min(xs)) - 60, int(max(xs)), 6):
                d.line([(k, max(ys)), (k + (max(ys) - min(ys)), min(ys))], fill=(90, 90, 90))
            d.polygon(pts, outline=(0, 0, 0))
        if p["id"] in targets:
            d.polygon(pts, outline=ACCENT, width=3)
        cx = sum(q[0] for q in pts) / len(pts); cy = sum(q[1] for q in pts) / len(pts)
        d.text((cx - 8, cy - 6), p["id"], fill=(20, 20, 20), font=font)
    pieces = {p["id"]: p for p in level["pieces"]}
    for j in level.get("joints", []):
        a, b = pieces.get(j["a"]), pieces.get(j["b"])
        if not a or not b: continue
        def anchor(p, off):
            r = p.get("rotation", 0); ox, oy = (off or {"x": 0, "y": 0})["x"], (off or {"x": 0, "y": 0})["y"]
            return (p["position"]["x"] + ox * math.cos(r) - oy * math.sin(r), p["position"]["y"] + ox * math.sin(r) + oy * math.cos(r))
        if j["type"] == "rope":
            d.line([tx(*anchor(a, j.get("anchorA"))), tx(*anchor(b, j.get("anchorB")))], fill=COLORS["rope"], width=3)
    g = level["goal"]
    a = level.get("annotation") or {}
    title = f'{level["id"]}  {level.get("region", "")}'
    d.text((8, 6), title, fill=TEXT, font=font)
    d.text((8, 22), f'{g["type"]} {",".join(g["targetPieceIds"])} req={g.get("requiredCount", "all")} budget={g["moveBudget"]} sup={level.get("supportsAllowed", 0)}', fill=TEXT, font=font)
    d.text((8, CELL_H - 44), f'solution: {" → ".join(a.get("solutionPath", [])) or "-"}', fill=ACCENT, font=font)
    d.text((8, CELL_H - 26), f'margin {a.get("marginRatio", "-")}  difficulty {a.get("difficulty", "-")}  states {len(a.get("stateMoves", []))}', fill=TEXT, font=font)
    return img


def main():
    out, files = sys.argv[1], sys.argv[2:]
    levels = []
    for f in files:
        data = json.load(open(f, encoding="utf-8"))
        levels += data if isinstance(data, list) else [data]
    font = ImageFont.load_default()
    cols = min(4, max(1, len(levels)))
    rows = math.ceil(len(levels) / cols)
    sheet = Image.new("RGB", (cols * CELL_W, rows * CELL_H), (0, 0, 0))
    for i, lv in enumerate(levels):
        sheet.paste(draw_level(lv, font), ((i % cols) * CELL_W, (i // cols) * CELL_H))
    sheet.save(out)
    print(f"{len(levels)} levels → {out}")


if __name__ == "__main__":
    main()
