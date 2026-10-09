#!/usr/bin/env python3
"""Generates App/Resources/Assets.xcassets (color tokens + app icon) and the widget's asset catalog.

Colors are the design system tokens from the Claude Design handoff (keystone-kit.js), dark + light.
The icon follows "Keystone Store": brass keystone on a thin beam, slate background, three iOS 18
appearances (default, dark, tinted). Re-run after changing a token: python3 scripts/gen_assets.py
"""
import json, os, re, shutil
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
APP = os.path.join(ROOT, "App/Resources/Assets.xcassets")
WIDGET = os.path.join(ROOT, "Widget/Assets.xcassets")

# name: (dark, light, usage)
TOKENS = {
    "BackgroundPrimary": ("#111519", "#F3F0E9", "Screen background"),
    "BackgroundSecondary": ("#161B21", "#EBE7DE", "Play-area floor gradient"),
    "BackgroundSheet": ("#191E25", "#F9F7F2", "Sheets"),
    "FillSurface": ("#1C222A", "#FFFFFF", "Cards, rows, chips"),
    "FillSurfaceSecondary": ("#262D36", "#E8E3D9", "Secondary buttons, tracks"),
    "LabelPrimary": ("#ECE7DE", "#1B1E22", "Primary text"),
    "LabelSecondary": ("#A9A398", "#5B574F", "Secondary text"),
    "LabelTertiary": ("#8E8A83", "#69655E", "Captions, disabled, empty stars (≥ 4.5:1 on every background)"),
    "Separator": ("rgba(220,214,200,0.10)", "rgba(30,34,40,0.10)", "Hairlines"),
    "SeparatorStrong": ("rgba(220,214,200,0.20)", "rgba(30,34,40,0.20)", "Dashed placeholders, ghost edges"),
    "AccentBrass": ("#D9A85B", "#925B16", "Primary button, selection, keystone, stars (≥ 4.5:1 as text in light)"),
    "LabelOnAccent": ("#1A1408", "#FFFFFF", "Text on brass"),
    "AccentSoft": ("rgba(217,168,91,0.15)", "rgba(146,91,22,0.11)", "Selection halo, icon tiles"),
    "StateCollapse": ("#E0574B", "#B8392E", "Collapse + critical stress only"),
    "StateCollapseSoft": ("rgba(224,87,75,0.16)", "rgba(184,57,46,0.11)", "Collapse tint"),
    "StateSuccess": ("#8DBBA0", "#3B7656", "Success, valid placement, switches on"),
    "StateSuccessSoft": ("rgba(141,187,160,0.16)", "rgba(59,118,86,0.11)", "Success tint"),
    "HudMaterial": ("rgba(22,27,33,0.78)", "rgba(249,247,242,0.82)", "HUD buttons / chips"),
    "Scrim": ("rgba(6,8,10,0.55)", "rgba(25,24,22,0.28)", "Behind sheets"),
    "BlueprintGrid": ("rgba(150,175,200,0.045)", "rgba(40,85,130,0.06)", "Background grid (minor)"),
    "BlueprintGridStrong": ("rgba(150,175,200,0.085)", "rgba(40,85,130,0.11)", "Background grid (major)"),
    "MaterialWood": ("#B98A5E", "#A27146", "Wood base"),
    "MaterialWoodDark": ("#86603D", "#6F4A29", "Wood shade"),
    "MaterialWoodLight": ("#D1A87D", "#BE8E60", "Wood light"),
    "MaterialStone": ("#A8A296", "#9A9384", "Stone base"),
    "MaterialStoneDark": ("#7C776D", "#6F695E", "Stone shade"),
    "MaterialStoneLight": ("#C2BDB2", "#B3AC9F", "Stone light"),
    "MaterialSteel": ("#7E8FA2", "#62748A", "Steel base"),
    "MaterialSteelDark": ("#56647A", "#435264", "Steel shade"),
    "MaterialSteelLight": ("#A6B4C4", "#8597AC", "Steel light"),
    "MaterialRope": ("#D9CFB8", "#BCAB85", "Rope base"),
    "MaterialRopeDark": ("#A99F88", "#8B7C59", "Rope shade"),
    "MaterialKeystone": ("#D9A85B", "#BC7B22", "Keystone base"),
    "MaterialKeystoneDark": ("#A57732", "#8A5612", "Keystone shade"),
    "MaterialKeystoneLight": ("#EDC787", "#D79E4A", "Keystone light"),
    "PieceOutline": ("rgba(0,0,0,0.6)", "rgba(30,20,10,0.55)", "Piece edge"),
    "GroundLine": ("#3A424D", "#BDB6A8", "Floor line and hatch"),
    "Crack": ("rgba(25,12,0,0.8)", "rgba(25,12,0,0.75)", "Stress cracks"),
    "LaunchBackground": ("#111519", "#F3F0E9", "Launch screen"),
}


def parse(c):
    if c.startswith("#"):
        return int(c[1:3], 16) / 255, int(c[3:5], 16) / 255, int(c[5:7], 16) / 255, 1.0
    m = re.match(r"rgba\(([\d.]+),([\d.]+),([\d.]+),([\d.]+)\)", c.replace(" ", ""))
    r, g, b, a = map(float, m.groups())
    return r / 255, g / 255, b / 255, a


def comp(c):
    r, g, b, a = parse(c)
    return {"color-space": "srgb", "components": {"red": f"{r:.3f}", "green": f"{g:.3f}", "blue": f"{b:.3f}", "alpha": f"{a:.3f}"}}


def colorset(folder, name, dark, light):
    d = os.path.join(folder, f"{name}.colorset")
    os.makedirs(d, exist_ok=True)
    contents = {
        "colors": [
            {"idiom": "universal", "color": comp(light)},
            {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}], "color": comp(dark)},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    json.dump(contents, open(os.path.join(d, "Contents.json"), "w"), indent=2)


def lin_grad(size, angle_deg, stops):
    """CSS-like linear gradient (angle measured clockwise from 'to top')."""
    import math
    w, h = size
    img = Image.new("RGBA", size)
    px = img.load()
    a = math.radians(angle_deg)
    dx, dy = math.sin(a), -math.cos(a)
    half = abs(w * dx) / 2 + abs(h * dy) / 2
    for y in range(h):
        for x in range(w):
            t = ((x - w / 2) * dx + (y - h / 2) * dy) / (2 * half) + 0.5
            t = min(1, max(0, t))
            for i in range(len(stops) - 1):
                (p0, c0), (p1, c1) = stops[i], stops[i + 1]
                if t <= p1 or i == len(stops) - 2:
                    u = 0 if p1 == p0 else min(1, max(0, (t - p0) / (p1 - p0)))
                    px[x, y] = tuple(int(c0[k] + (c1[k] - c0[k]) * u) for k in range(4))
                    break
    return img


def hexrgba(h, a=255):
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16), a)


def icon(variant, out_path, size=1024):
    S = 4  # supersample
    W = size * S
    k = W / 320.0
    if variant == "default":
        bg = lin_grad((W // 8, W // 8), 160, [(0, hexrgba("#1E252D")), (1, hexrgba("#12171C"))]).resize((W, W), Image.BICUBIC)
    elif variant == "dark":
        bg = Image.new("RGBA", (W, W), (0, 0, 0, 255))
    else:
        bg = Image.new("RGBA", (W, W), (17, 17, 17, 255))
    img = bg
    if variant == "default":
        grid = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        gd = ImageDraw.Draw(grid)
        step = int(40 * k)
        for i in range(0, W, step):
            gd.line([(i, 0), (i, W)], fill=(150, 175, 200, 18), width=max(1, int(k)))
            gd.line([(0, i), (W, i)], fill=(150, 175, 200, 18), width=max(1, int(k)))
        img = Image.alpha_composite(img, grid)
    d = ImageDraw.Draw(img, "RGBA")
    # Beam
    beam_box = (int(60 * k), int(226 * k), int(260 * k), int(240 * k))
    if variant == "tinted":
        d.rounded_rectangle(beam_box, radius=int(2 * k), fill=hexrgba("#6A6A6A"))
    else:
        top, bot = ("#5B6774", "#3B444F") if variant == "default" else ("#6D7A88", "#4A5460")
        g = lin_grad((8, 8), 180, [(0, hexrgba(top)), (1, hexrgba(bot))]).resize((beam_box[2] - beam_box[0], beam_box[3] - beam_box[1]))
        m = Image.new("L", g.size, 0)
        ImageDraw.Draw(m).rounded_rectangle((0, 0, g.size[0] - 1, g.size[1] - 1), radius=int(2 * k), fill=255)
        img.paste(g, beam_box[:2], m)
    # Keystone trapezoid
    x0, y0, kw, kh = 96 * k, 84 * k, 128 * k, 142 * k
    poly = [(x0, y0), (x0 + kw, y0), (x0 + 0.8 * kw, y0 + kh), (x0 + 0.2 * kw, y0 + kh)]
    if variant == "default":
        stops = [(0, hexrgba("#F0CC8E")), (0.55, hexrgba("#D9A85B")), (1, hexrgba("#A57732"))]
    elif variant == "dark":
        stops = [(0, hexrgba("#FFE0A6")), (0.55, hexrgba("#EDBB6A")), (1, hexrgba("#C08A3E"))]
    else:
        stops = [(0, hexrgba("#FFFFFF")), (1, hexrgba("#D6D6D6"))]
    kg = lin_grad((32, 36), 170, stops).resize((int(kw), int(kh)), Image.BICUBIC)
    if variant != "tinted":
        stripes = Image.new("RGBA", kg.size, (0, 0, 0, 0))
        kd = ImageDraw.Draw(stripes)
        band = 10 * k
        yy = kh - 9 * k
        while yy > 0:
            kd.rectangle((0, yy, kw, yy + k), fill=(80, 45, 0, 40))
            yy -= band
        kg = Image.alpha_composite(kg, stripes)
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    layer.paste(kg, (int(x0), int(y0)))
    img = Image.composite(layer, img, mask)
    if variant == "default":
        ticks = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        d = ImageDraw.Draw(ticks)
        c = (217, 168, 91, 140)
        d.rectangle((96 * k, 62 * k, 224 * k, 63 * k), fill=c)
        d.rectangle((96 * k, 56 * k, 97 * k, 68 * k), fill=c)
        d.rectangle((223 * k, 56 * k, 224 * k, 68 * k), fill=c)
        img = Image.alpha_composite(img.convert("RGBA"), ticks)
    img = img.resize((size, size), Image.LANCZOS).convert("RGB")
    img.save(out_path)


def main():
    if os.path.isdir(APP):
        shutil.rmtree(APP)
    os.makedirs(APP)
    json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(APP, "Contents.json"), "w"), indent=2)
    for name, (dark, light, _) in TOKENS.items():
        colorset(APP, name, dark, light)
    colorset(APP, "AccentColor", "#D9A85B", "#925B16")

    ic = os.path.join(APP, "AppIcon.appiconset")
    os.makedirs(ic)
    icon("default", os.path.join(ic, "AppIcon.png"))
    icon("dark", os.path.join(ic, "AppIcon-Dark.png"))
    icon("tinted", os.path.join(ic, "AppIcon-Tinted.png"))
    json.dump({
        "images": [
            {"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "AppIcon-Dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "tinted"}], "filename": "AppIcon-Tinted.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        ],
        "info": {"author": "xcode", "version": 1},
    }, open(os.path.join(ic, "Contents.json"), "w"), indent=2)

    if os.path.isdir(WIDGET):
        shutil.rmtree(WIDGET)
    os.makedirs(WIDGET)
    json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(WIDGET, "Contents.json"), "w"), indent=2)
    colorset(WIDGET, "WidgetBackground", "#111519", "#F3F0E9")
    for name in ["AccentBrass", "LabelPrimary", "LabelSecondary", "LabelTertiary", "StateSuccess", "GroundLine", "Separator"]:
        dark, light, _ = TOKENS[name]
        colorset(WIDGET, name, dark, light)
    print("assets written")


if __name__ == "__main__":
    main()
