#!/usr/bin/env python3
"""Génère les images du jeu (SVG avec dégradés) : pièces dans assets/pieces, plateau,
rails et boutons dans assets/ui.

Les images sont dessinées au double de leur taille à l'écran. Après exécution, relancer
l'import : godot --headless --path . --import
"""
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


def defs(c, bonus):
    side_a, side_b = (("#b3a8ee", "#8377cf") if bonus else (dark(c, 0.30), dark(c, 0.58)))
    return f'''<defs>
<linearGradient id="top" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{light(c, 0.34)}"/><stop offset="0.55" stop-color="#{c}"/><stop offset="1" stop-color="{dark(c, 0.10)}"/></linearGradient>
<linearGradient id="side" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{side_a}"/><stop offset="1" stop-color="{side_b}"/></linearGradient>
<linearGradient id="panel" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{dark(c, 0.26)}"/><stop offset="1" stop-color="{light(c, 0.12)}"/></linearGradient>
<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.75"/><stop offset="0.6" stop-color="#ffffff" stop-opacity="0"/></linearGradient>
<linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.62"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.04"/></linearGradient>
<radialGradient id="shadow" cx="0.5" cy="0.5" r="0.5"><stop offset="0.35" stop-color="#05021c" stop-opacity="0.55"/><stop offset="1" stop-color="#05021c" stop-opacity="0"/></radialGradient>
<radialGradient id="wheel" cx="0.4" cy="0.35" r="0.7"><stop offset="0" stop-color="#5d55a3"/><stop offset="1" stop-color="#120d36"/></radialGradient>
<radialGradient id="hub" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#9d95d8"/></radialGradient>
<radialGradient id="dome" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="{light(c, 0.45)}"/><stop offset="1" stop-color="{dark(c, 0.35)}"/></radialGradient>
<linearGradient id="glass" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#d8f4ff"/><stop offset="1" stop-color="#3fa9f0"/></linearGradient>
<radialGradient id="lamp" cx="0.4" cy="0.35" r="0.7"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#ffcf3a"/></radialGradient>
</defs>'''


def wheel(x, y, r):
    return (f'<circle cx="{x}" cy="{y}" r="{r}" fill="url(#wheel)"/>'
            f'<circle cx="{x}" cy="{y}" r="{r * 0.42:.1f}" fill="url(#hub)"/>')


def body(w, wheels):
    """Bloc brillant de largeur w (unités 2x), face du dessus de 112 de haut."""
    cx = 20 + w / 2
    parts = [
        f'<ellipse cx="{cx}" cy="150" rx="{w / 2 + 12}" ry="24" fill="url(#shadow)"/>',
        f'<rect x="20" y="24" width="{w}" height="112" rx="28" fill="url(#side)"/>',
    ]
    parts += [wheel(x, 139, r) for x, r in wheels]
    parts += [
        f'<rect x="20" y="8" width="{w}" height="112" rx="28" fill="url(#top)"/>',
        f'<rect x="22.5" y="10.5" width="{w - 5}" height="107" rx="25.5" fill="none" stroke="url(#rim)" stroke-width="5"/>',
    ]
    return parts


def finish(w):
    return [
        f'<rect x="32" y="15" width="{w - 24}" height="24" rx="12" fill="url(#gloss)"/>',
        '<ellipse cx="46" cy="26" rx="10" ry="5.5" fill="#ffffff" fill-opacity="0.9"/>',
    ]


def wagon(c, bonus=False):
    parts = body(128, [(48, 15), (120, 15)])
    if not bonus:
        parts.append('<rect x="42" y="50" width="84" height="50" rx="14" fill="url(#panel)"/>')
        parts.append(f'<rect x="48" y="57" width="72" height="36" rx="9" fill="#{c}"/>')
    parts += finish(128)
    return svg(168, c, bonus, parts)


def loco(c):
    parts = body(180, [(56, 17), (112, 17), (168, 17)])
    parts += [
        '<rect x="32" y="44" width="50" height="60" rx="13" fill="#1b1642"/>',
        '<rect x="38" y="50" width="38" height="28" rx="8" fill="url(#glass)"/>',
        '<ellipse cx="48" cy="57" rx="7" ry="3.5" fill="#ffffff" fill-opacity="0.8"/>',
        '<circle cx="128" cy="72" r="29" fill="#1b1642"/>',
        '<circle cx="128" cy="72" r="23" fill="url(#dome)"/>',
        '<circle cx="128" cy="72" r="10" fill="#1b1642"/>',
        '<circle cx="182" cy="72" r="15" fill="#1b1642"/>',
        '<circle cx="182" cy="72" r="11" fill="url(#lamp)"/>',
    ]
    parts += finish(180)
    return svg(220, c, False, parts)


def svg(width, c, bonus, parts):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="184" viewBox="0 0 {width} 184">\n'
            + defs(c, bonus) + "\n" + "\n".join(parts) + "\n</svg>\n")


UI = os.path.join(os.path.dirname(__file__), "..", "assets", "ui")
TRAY = "453a9e"
SLOT = "2a2370"
BUTTONS = {"violet": "6a55f2", "dark": "3a3095", "green": "2fb344"}


def doc(w, h, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">\n'
            + body + "\n</svg>\n")


def grad(name, y1, y2, stops):
    inner = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return (f'<linearGradient id="{name}" gradientUnits="userSpaceOnUse" x1="0" y1="{y1}" x2="0" y2="{y2}">'
            + inner + "</linearGradient>")


def tray():
    """Plateau en relief (9 tranches, marge 100)."""
    d = grad("face", 8, 100, [(0, light(TRAY, 0.20), 1), (1, "#" + TRAY, 1)]) \
        + grad("rim", 8, 80, [(0, "#ffffff", 0.55), (1, "#ffffff", 0)]) \
        + grad("side", 150, 232, [(0, dark(TRAY, 0.35), 1), (1, dark(TRAY, 0.62), 1)])
    body = f"<defs>{d}</defs>"
    for i, op in enumerate([0.10, 0.12, 0.14]):
        body += f'<rect x="{2 + i * 2}" y="{40 + i * 2}" width="{236 - i * 4}" height="{200 - i * 4}" rx="62" fill="#05021c" fill-opacity="{op}"/>'
    body += '<rect x="8" y="32" width="224" height="200" rx="60" fill="url(#side)"/>'
    body += '<rect x="8" y="8" width="224" height="200" rx="60" fill="url(#face)"/>'
    body += '<rect x="11" y="11" width="218" height="194" rx="57" fill="none" stroke="url(#rim)" stroke-width="6"/>'
    return doc(240, 240, body)


def slot():
    """Creux d'une voie d'arrivée (9 tranches, marge 60)."""
    d = grad("fill", 0, 56, [(0, dark(SLOT, 0.55), 1), (1, "#" + SLOT, 1)]) \
        + grad("lip", 100, 160, [(0, "#ffffff", 0), (1, "#ffffff", 0.30)])
    body = f"<defs>{d}</defs>"
    body += '<rect x="0" y="0" width="160" height="160" rx="40" fill="url(#fill)"/>'
    body += '<rect x="2.5" y="2.5" width="155" height="155" rx="37.5" fill="none" stroke="url(#lip)" stroke-width="5"/>'
    return doc(160, 160, body)


def socket():
    """Place à remplir, en blanc et gris : le jeu la teinte de la couleur attendue."""
    d = grad("in", 4, 70, [(0, "#000000", 0.55), (1, "#000000", 0)]) \
        + grad("ring", 0, 140, [(0, "#ffffff", 1), (1, "#c8c8c8", 1)])
    body = f"<defs>{d}</defs>"
    body += '<rect x="4" y="4" width="124" height="132" rx="28" fill="#6a6a6a" fill-opacity="0.9"/>'
    body += '<rect x="4" y="4" width="124" height="132" rx="28" fill="url(#in)"/>'
    body += '<rect x="5" y="5" width="122" height="130" rx="27" fill="none" stroke="url(#ring)" stroke-width="9"/>'
    return doc(132, 140, body)


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
    body += '<rect x="0" y="8" width="116" height="28" rx="10" fill="#a86f00"/>'
    body += '<rect x="0" y="0" width="116" height="28" rx="10" fill="url(#top)"/>'
    body += '<rect x="8" y="3.5" width="100" height="7" rx="3.5" fill="#ffffff" fill-opacity="0.6"/>'
    return doc(116, 44, body)


def chip(c):
    body = (f'<defs><radialGradient id="c" cx="0.38" cy="0.3" r="0.8"><stop offset="0" stop-color="{light(c, 0.45)}"/>'
            f'<stop offset="0.6" stop-color="#{c}"/><stop offset="1" stop-color="{dark(c, 0.18)}"/></radialGradient></defs>'
            f'<circle cx="40" cy="48" r="36" fill="{dark(c, 0.52)}"/><circle cx="40" cy="38" r="36" fill="url(#c)"/>'
            '<ellipse cx="30" cy="20" rx="14" ry="7" fill="#ffffff" fill-opacity="0.55"/>')
    return doc(80, 88, body)


def button(c, pressed):
    """Bouton bombé (9 tranches : marges 50 en haut et sur les côtés, 60 en bas)."""
    y = 10 if pressed else 0
    face = dark(c, 0.10) if pressed else "#" + c
    d = grad("face", y, y + 144, [(0, light(c, 0.05 if pressed else 0.30), 1), (0.35, face, 1), (0.7, face, 1), (1, dark(c, 0.16), 1)]) \
        + grad("gloss", y + 6, y + 40, [(0, "#ffffff", 0.50), (1, "#ffffff", 0.04)]) \
        + grad("rim", y, y + 70, [(0, "#ffffff", 0.7), (1, "#ffffff", 0)])
    body = f"<defs>{d}</defs>"
    body += f'<rect x="0" y="16" width="160" height="144" rx="36" fill="{dark(c, 0.50)}"/>'
    body += f'<rect x="0" y="{y}" width="160" height="144" rx="36" fill="url(#face)"/>'
    body += f'<rect x="2.5" y="{y + 2.5}" width="155" height="139" rx="33.5" fill="none" stroke="url(#rim)" stroke-width="5"/>'
    if not pressed:
        body += '<rect x="12" y="7" width="136" height="30" rx="15" fill="url(#gloss)"/>'
    return doc(160, 160, body)


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
    for name, c in BUTTONS.items():
        write(UI, f"button_{name}.svg", button(c, False))
        write(UI, f"button_{name}_pressed.svg", button(c, True))
    os.makedirs(OUT, exist_ok=True)
    for i, c in enumerate(PALETTE):
        open(os.path.join(OUT, f"wagon_{i}.svg"), "w").write(wagon(c))
        open(os.path.join(OUT, f"loco_{i}.svg"), "w").write(loco(c))
    open(os.path.join(OUT, "wagon_bonus.svg"), "w").write(wagon(BONUS, True))


main()
