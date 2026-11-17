#!/usr/bin/env python3
"""Génère les images du jeu (SVG avec dégradés) : pièces dans assets/pieces, plateau,
rails et boutons dans assets/ui.

Les images sont dessinées au double de leur taille à l'écran. Après exécution, relancer
l'import : godot --headless --path . --import
"""
import math
import os

PALETTE = ["f0412b", "2f86f5", "ffc61a", "2fb344", "a35cf2", "f760b4"]
BONUS = "f4f1ff"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "pieces")


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(h, other, t):
    a, b = rgb(h), rgb(other)
    return "#%02x%02x%02x" % tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def light(h, t):
    return mix(h, "ffffff", t)


def dark(h, t):
    return mix(h, "120a3a", t)


def doc(w, h, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">\n'
            + body + "\n</svg>\n")


def grad(name, y1, y2, stops):
    inner = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return (f'<linearGradient id="{name}" gradientUnits="userSpaceOnUse" x1="0" y1="{y1}" x2="0" y2="{y2}">'
            + inner + "</linearGradient>")


# Les pièces sont vues du dessus et regardent vers la droite : le jeu les fait pivoter le
# long des rails. L'éclairage est donc symétrique (toit bombé, plus clair au centre) ;
# l'épaisseur et l'ombre sont ajoutées par le jeu, toujours vers le bas de l'écran.
STEEL = "#1b1642"


def bombe(name, y1, y2, c, lo, hi):
    return grad(name, y1, y2, [(0, dark(c, lo), 1), (0.5, light(c, hi), 1), (1, dark(c, lo), 1)])


def wagon(c, bonus=False):
    edge = "#8377cf" if bonus else dark(c, 0.42)
    d = bombe("roof", 12, 116, c, 0.20, 0.20) + bombe("panel", 26, 102, c, 0.04, 0.36)
    body = f"<defs>{d}</defs>"
    for x in (26, 90):
        for y in (4, 112):
            body += f'<rect x="{x}" y="{y}" width="28" height="12" rx="4" fill="{STEEL}"/>'
    for x in (0, 130):
        body += f'<rect x="{x}" y="54" width="14" height="20" rx="5" fill="{STEEL}"/>'
    body += f'<rect x="10" y="12" width="124" height="104" rx="22" fill="url(#roof)" stroke="{edge}" stroke-width="4"/>'
    body += '<rect x="26" y="26" width="92" height="76" rx="14" fill="url(#panel)"/>'
    if not bonus:
        for x in (49, 72, 95):
            body += f'<line x1="{x}" y1="32" x2="{x}" y2="96" stroke="{dark(c, 0.20)}" stroke-width="4" stroke-linecap="round" stroke-opacity="0.75"/>'
    body += '<rect x="32" y="58" width="80" height="12" rx="6" fill="#ffffff" fill-opacity="0.34"/>'
    return doc(144, 128, body)


def loco(c):
    d = bombe("roof", 12, 116, c, 0.20, 0.20) + bombe("panel", 20, 108, c, 0.04, 0.36) \
        + bombe("boiler", 26, 102, c, 0.16, 0.50)
    body = (f'<defs>{d}<radialGradient id="dome" cx="0.4" cy="0.4" r="0.7"><stop offset="0" stop-color="{light(c, 0.6)}"/>'
            f'<stop offset="1" stop-color="{dark(c, 0.25)}"/></radialGradient>'
            '<radialGradient id="lamp" cx="0.4" cy="0.4" r="0.7"><stop offset="0" stop-color="#ffffff"/>'
            '<stop offset="1" stop-color="#ffcf3a"/></radialGradient></defs>')
    for y in (4, 112):
        body += f'<rect x="72" y="{y}" width="100" height="12" rx="5" fill="{STEEL}"/>'
    body += f'<rect x="0" y="54" width="14" height="20" rx="5" fill="{STEEL}"/>'
    body += f'<rect x="178" y="20" width="14" height="88" rx="5" fill="{STEEL}"/>'
    body += f'<rect x="10" y="12" width="172" height="104" rx="22" fill="url(#roof)" stroke="{dark(c, 0.42)}" stroke-width="4"/>'
    body += '<rect x="18" y="20" width="58" height="88" rx="14" fill="url(#panel)"/>'
    body += '<rect x="26" y="58" width="42" height="12" rx="6" fill="#ffffff" fill-opacity="0.34"/>'
    body += f'<rect x="82" y="26" width="96" height="76" rx="30" fill="url(#boiler)" stroke="{dark(c, 0.45)}" stroke-width="4"/>'
    for x in (98, 164):
        body += f'<line x1="{x}" y1="31" x2="{x}" y2="97" stroke="{STEEL}" stroke-width="5" stroke-linecap="round"/>'
    body += '<circle cx="117" cy="64" r="12" fill="url(#dome)"/>'
    body += f'<circle cx="144" cy="64" r="17" fill="{STEEL}"/><circle cx="144" cy="64" r="10" fill="#05021c"/>'
    body += f'<circle cx="144" cy="64" r="15" fill="none" stroke="{light(c, 0.3)}" stroke-width="2.5" stroke-opacity="0.7"/>'
    body += f'<circle cx="176" cy="64" r="11" fill="{STEEL}"/><circle cx="176" cy="64" r="8" fill="url(#lamp)"/>'
    return doc(196, 128, body)


UI = os.path.join(os.path.dirname(__file__), "..", "assets", "ui")
TRAY = "453a9e"
SLOT = "2a2370"
BUTTONS = {"violet": "6a55f2", "dark": "3a3095", "green": "2fb344"}


def tray():
    """Plateau vu légèrement du dessus : dessus des parois clair, fond en creux ombré par
    la paroi du fond, façade avant haute (9 tranches, marge 100)."""
    d = grad("wall", 8, 60, [(0, light(TRAY, 0.34), 1), (1, light(TRAY, 0.12), 1)]) \
        + grad("rim", 8, 60, [(0, "#ffffff", 0.6), (1, "#ffffff", 0)]) \
        + grad("floor", 30, 100, [(0, dark(TRAY, 0.72), 1), (0.3, dark(TRAY, 0.50), 1), (1, dark(TRAY, 0.14), 1)]) \
        + grad("side", 150, 236, [(0, dark(TRAY, 0.40), 1), (1, dark(TRAY, 0.70), 1)]) \
        + grad("lip", 150, 190, [(0, "#ffffff", 0), (1, "#ffffff", 0.28)])
    body = f"<defs>{d}</defs>"
    for i, op in enumerate([0.10, 0.13, 0.16]):
        body += f'<rect x="{2 + i * 2}" y="{52 + i * 2}" width="{236 - i * 4}" height="{188 - i * 4}" rx="62" fill="#05021c" fill-opacity="{op}"/>'
    body += '<rect x="8" y="48" width="224" height="188" rx="60" fill="url(#side)"/>'
    body += '<rect x="8" y="8" width="224" height="184" rx="60" fill="url(#wall)"/>'
    body += '<rect x="11" y="11" width="218" height="178" rx="57" fill="none" stroke="url(#rim)" stroke-width="6"/>'
    body += '<rect x="30" y="30" width="180" height="140" rx="40" fill="url(#floor)"/>'
    body += '<rect x="32.5" y="32.5" width="175" height="135" rx="37.5" fill="none" stroke="url(#lip)" stroke-width="5"/>'
    return doc(240, 240, body)


def slot():
    """Creux d'une voie d'arrivée (9 tranches, marge 60)."""
    d = grad("fill", 0, 100, [(0, dark(SLOT, 0.80), 1), (0.35, dark(SLOT, 0.45), 1), (1, "#" + SLOT, 1)]) \
        + grad("lip", 100, 160, [(0, "#ffffff", 0), (1, "#ffffff", 0.42)])
    body = f"<defs>{d}</defs>"
    body += '<rect x="0" y="0" width="160" height="160" rx="40" fill="url(#fill)"/>'
    body += '<rect x="2.5" y="2.5" width="155" height="155" rx="37.5" fill="none" stroke="url(#lip)" stroke-width="5"/>'
    return doc(160, 160, body)


def socket():
    """Place à remplir, en blanc et gris : le jeu la teinte de la couleur attendue."""
    d = grad("in", 4, 70, [(0, "#000000", 0.55), (1, "#000000", 0)]) \
        + grad("ring", 0, 140, [(0, "#ffffff", 1), (1, "#c8c8c8", 1)])
    body = f"<defs>{d}</defs>"
    body += '<rect x="4" y="4" width="128" height="116" rx="26" fill="#6a6a6a" fill-opacity="0.9"/>'
    body += '<rect x="4" y="4" width="128" height="116" rx="26" fill="url(#in)"/>'
    body += '<rect x="5" y="5" width="126" height="114" rx="25" fill="none" stroke="url(#ring)" stroke-width="9"/>'
    return doc(136, 124, body)


def tie():
    d = grad("bar", 0, 18, [(0, "#9d92f0", 1), (1, "#5a4fb8", 1)])
    body = f"<defs>{d}</defs>"
    body += '<rect x="2" y="7" width="96" height="17" rx="6" fill="#0c0830" fill-opacity="0.45"/>'
    body += '<rect x="0" y="0" width="100" height="18" rx="6" fill="url(#bar)"/>'
    body += '<rect x="6" y="2.5" width="88" height="4" rx="2" fill="#ffffff" fill-opacity="0.35"/>'
    return doc(100, 24, body)


def knob():
    body = ('<defs><radialGradient id="k" cx="0.38" cy="0.32" r="0.75"><stop offset="0" stop-color="#ffffff"/>'
            '<stop offset="1" stop-color="#a99ee8"/></radialGradient></defs>'
            '<circle cx="26" cy="29" r="23" fill="#0c0830" fill-opacity="0.45"/>'
            '<circle cx="26" cy="26" r="24" fill="#1b1642"/><circle cx="26" cy="26" r="16" fill="url(#k)"/>'
            '<ellipse cx="21" cy="20" rx="6" ry="3.5" fill="#ffffff" fill-opacity="0.9"/>')
    return doc(52, 56, body)


def bumper():
    d = grad("top", 0, 28, [(0, "#fff0a8", 1), (0.5, "#ffc61a", 1), (1, "#e7a400", 1)])
    body = f"<defs>{d}</defs>"
    body += '<rect x="2" y="14" width="112" height="30" rx="10" fill="#0c0830" fill-opacity="0.4"/>'
    body += '<rect x="0" y="12" width="116" height="28" rx="10" fill="#a86f00"/>'
    body += '<rect x="0" y="0" width="116" height="28" rx="10" fill="url(#top)"/>'
    body += '<rect x="8" y="3.5" width="100" height="7" rx="3.5" fill="#ffffff" fill-opacity="0.6"/>'
    return doc(116, 44, body)


def chip(c):
    body = (f'<defs><radialGradient id="c" cx="0.38" cy="0.3" r="0.8"><stop offset="0" stop-color="{light(c, 0.45)}"/>'
            f'<stop offset="0.6" stop-color="#{c}"/><stop offset="1" stop-color="{dark(c, 0.18)}"/></radialGradient></defs>'
            f'<circle cx="40" cy="50" r="36" fill="{dark(c, 0.55)}"/><circle cx="40" cy="38" r="36" fill="url(#c)"/>'
            '<ellipse cx="30" cy="20" rx="14" ry="7" fill="#ffffff" fill-opacity="0.55"/>')
    return doc(80, 88, body)


def button(c, pressed):
    """Bouton bombé (9 tranches : marges 50 en haut et sur les côtés, 70 en bas)."""
    y = 16 if pressed else 0
    face = dark(c, 0.10) if pressed else "#" + c
    d = grad("face", y, y + 134, [(0, light(c, 0.05 if pressed else 0.32), 1), (0.35, face, 1), (0.7, face, 1), (1, dark(c, 0.16), 1)]) \
        + grad("gloss", y + 6, y + 40, [(0, "#ffffff", 0.52), (1, "#ffffff", 0.04)]) \
        + grad("rim", y, y + 70, [(0, "#ffffff", 0.7), (1, "#ffffff", 0)]) \
        + grad("side", 90, 160, [(0, dark(c, 0.42), 1), (1, dark(c, 0.66), 1)])
    body = f"<defs>{d}</defs>"
    body += '<rect x="0" y="26" width="160" height="134" rx="36" fill="url(#side)"/>'
    body += f'<rect x="0" y="{y}" width="160" height="134" rx="36" fill="url(#face)"/>'
    body += f'<rect x="2.5" y="{y + 2.5}" width="155" height="129" rx="33.5" fill="none" stroke="url(#rim)" stroke-width="5"/>'
    if not pressed:
        body += '<rect x="12" y="7" width="136" height="30" rx="15" fill="url(#gloss)"/>'
    return doc(160, 160, body)


def station(c):
    """Gare de la carte : un gros jeton brillant."""
    body = (f'<defs><radialGradient id="s" cx="0.38" cy="0.3" r="0.85"><stop offset="0" stop-color="{light(c, 0.55)}"/>'
            f'<stop offset="0.55" stop-color="#{c}"/><stop offset="1" stop-color="{dark(c, 0.22)}"/></radialGradient>'
            '<radialGradient id="sh" cx="0.5" cy="0.5" r="0.5"><stop offset="0.4" stop-color="#05021c" stop-opacity="0.5"/>'
            '<stop offset="1" stop-color="#05021c" stop-opacity="0"/></radialGradient></defs>'
            '<ellipse cx="88" cy="160" rx="86" ry="30" fill="url(#sh)"/>'
            f'<circle cx="88" cy="106" r="80" fill="{dark(c, 0.58)}"/>'
            '<circle cx="88" cy="84" r="80" fill="url(#s)"/>'
            f'<circle cx="88" cy="84" r="66" fill="none" stroke="{dark(c, 0.20)}" stroke-width="5" stroke-opacity="0.6"/>'
            '<ellipse cx="62" cy="40" rx="34" ry="16" fill="#ffffff" fill-opacity="0.5"/>')
    return doc(176, 192, body)


def star(fill_a, fill_b, edge):
    pts = []
    for k in range(10):
        r = 44 if k % 2 == 0 else 20
        ang = -math.pi / 2 + k * math.pi / 5
        pts.append(f"{48 + r * math.cos(ang):.1f},{50 + r * math.sin(ang):.1f}")
    d = grad("st", 4, 96, [(0, fill_a, 1), (1, fill_b, 1)])
    body = f"<defs>{d}</defs>"
    body += f'<polygon points="{" ".join(pts)}" fill="url(#st)" stroke="{edge}" stroke-width="7" stroke-linejoin="round"/>'
    body += '<ellipse cx="40" cy="32" rx="9" ry="5" fill="#ffffff" fill-opacity="0.75"/>'
    return doc(96, 100, body)


def blob(cx, cy, r, c):
    return (f'<circle cx="{cx}" cy="{cy + 5}" r="{r}" fill="{dark(c, 0.45)}"/><circle cx="{cx}" cy="{cy}" r="{r}" fill="#{c}"/>'
            f'<ellipse cx="{cx - r * 0.3:.0f}" cy="{cy - r * 0.45:.0f}" rx="{r * 0.4:.0f}" ry="{r * 0.2:.0f}" fill="#ffffff" fill-opacity="0.45"/>')


def tree():
    body = ('<ellipse cx="60" cy="112" rx="40" ry="10" fill="#05021c" fill-opacity="0.35"/>'
            '<rect x="51" y="70" width="18" height="42" rx="6" fill="#7a4a24"/>'
            + blob(60, 52, 36, "2fb344") + blob(36, 70, 22, "3cc552") + blob(84, 72, 20, "27a03b"))
    return doc(120, 124, body)


def peak():
    d = grad("pk", 10, 110, [(0, "#b9c6ee", 1), (1, "#5a67b0", 1)])
    body = (f"<defs>{d}</defs>"
            '<ellipse cx="70" cy="110" rx="62" ry="10" fill="#05021c" fill-opacity="0.35"/>'
            '<polygon points="96,108 140,108 118,56" fill="#4b5799" stroke="#4b5799" stroke-width="8" stroke-linejoin="round"/>'
            '<polygon points="8,108 112,108 60,14" fill="url(#pk)" stroke="url(#pk)" stroke-width="8" stroke-linejoin="round"/>'
            '<polygon points="60,14 42,48 54,42 62,52 70,42 80,50" fill="#ffffff" stroke="#ffffff" stroke-width="6" stroke-linejoin="round"/>')
    return doc(148, 124, body)


def wave():
    path = "M10 34 a18 18 0 0 1 36 0 a18 18 0 0 1 36 0 a18 18 0 0 1 36 0"
    body = (f'<path d="{path}" transform="translate(0 6)" fill="none" stroke="#0c3a5c" stroke-width="12" stroke-linecap="round"/>'
            f'<path d="{path}" fill="none" stroke="#5fc9f2" stroke-width="12" stroke-linecap="round"/>'
            f'<path d="{path}" transform="translate(0 -3)" fill="none" stroke="#d6f4ff" stroke-width="3.5" stroke-linecap="round"/>')
    return doc(128, 60, body)


def write(folder, name, text):
    os.makedirs(folder, exist_ok=True)
    open(os.path.join(folder, name), "w").write(text)


def main():
    write(UI, "tray.svg", tray())
    write(UI, "slot.svg", slot())
    write(UI, "socket.svg", socket())
    write(UI, "tie.svg", tie())
    write(UI, "knob.svg", knob())
    write(UI, "bumper.svg", bumper())
    for i, c in enumerate(PALETTE):
        write(UI, f"chip_{i}.svg", chip(c))
    write(UI, "station_done.svg", station("ffc61a"))
    write(UI, "station_open.svg", station("f4f1ff"))
    write(UI, "station_locked.svg", station("6f67a8"))
    write(UI, "star.svg", star("#fff0a8", "#ffb400", "#a86f00"))
    write(UI, "star_empty.svg", star("#4a40a6", "#2f2778", "#1b1642"))
    write(UI, "tree.svg", tree())
    write(UI, "peak.svg", peak())
    write(UI, "wave.svg", wave())
    for name, c in BUTTONS.items():
        write(UI, f"button_{name}.svg", button(c, False))
        write(UI, f"button_{name}_pressed.svg", button(c, True))
    os.makedirs(OUT, exist_ok=True)
    for i, c in enumerate(PALETTE):
        open(os.path.join(OUT, f"wagon_{i}.svg"), "w").write(wagon(c))
        open(os.path.join(OUT, f"loco_{i}.svg"), "w").write(loco(c))
    open(os.path.join(OUT, "wagon_bonus.svg"), "w").write(wagon(BONUS, True))


main()
