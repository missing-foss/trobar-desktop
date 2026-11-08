#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 missing-foss
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generates lib/brand_tokens.dart from brand/trobar-themes.json (a copy of
trobar-server's brand/tokens/trobar-themes.json, the single source): each
theme's six brand roles, and its derived light/dark ColorScheme.

    python3 tool/gen_brand_tokens.py          # rewrite it
    python3 tool/gen_brand_tokens.py --check  # dev/verify.sh: stale or under WCAG AA = exit 1

The derivation is trobar-server's (dev/gen_brand_css.py there, the table
agreed in trobar-server#141), copied verbatim between the markers below, and
the Material 3 additions are trobar-android's (dev/gen_brand_tokens.py
there), so web, Android and desktop cannot drift. Flutter's ColorScheme also
requires onSecondary and onTertiary: black or white, whichever reads better.
"""
import colorsys
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOKENS = ROOT / "brand/trobar-themes.json"
OUT = ROOT / "lib/brand_tokens.dart"

WHITE, BLACK = "#FFFFFF", "#000000"
ERROR_LIGHT = "#B3261E"
ERROR_DARK_HUE = "#E2586E"
CONTRASTE_YELLOW = "#FFD400"
CONTRASTE_ERROR = "#FF6B6B"
DARK_ONLY = ("nuech", "contraste")

# --- BEGIN shared with trobar-server dev/gen_brand_css.py ---
# --- colour arithmetic -------------------------------------------------------

def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def hexc(c):
    return "#" + "".join(f"{round(max(0.0, min(1.0, v)) * 255):02X}" for v in c)


def mix(a, b, t):
    """a moved a fraction t of the way to b."""
    return hexc(tuple(x + (y - x) * t for x, y in zip(rgb(a), rgb(b))))


def at_lightness(h, light):
    r, g, b = rgb(h)
    hue, _, sat = colorsys.rgb_to_hls(r, g, b)
    return hexc(colorsys.hls_to_rgb(hue, light, sat))


def alpha(h, a):
    r, g, b = (round(v * 255) for v in rgb(h))
    return f"rgba({r},{g},{b},{a})"


def over(fg, a, bg):
    """fg at opacity a composited over bg, as the browser paints it."""
    return mix(bg, fg, a)


def luminance(h):
    def channel(v):
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(v) for v in rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def neutral_with_white_at(a, b, target):
    """The colour between a and b, closest to a, on which white text reaches
    the target contrast: a button background that carries white labels."""
    lo, hi = 0.0, 1.0
    for _ in range(40):
        mid = (lo + hi) / 2
        if ratio(WHITE, mix(a, b, mid)) >= target:
            hi = mid
        else:
            lo = mid
    return mix(a, b, hi)


# --- the derivation (the table in trobar-server#141) --------------------------

def light_roles(t):
    return {
        "background": t["ground"], "surface": WHITE,
        "surfaceVariant": mix(t["ground"], t["text"], 0.06),
        "onSurface": t["text"], "onSurfaceVariant": mix(t["text"], t["ground"], 0.30),
        "primary": t["disc"], "onPrimary": t["star"],
        "primaryContainer": mix(t["disc"], WHITE, 0.85), "onPrimaryContainer": mix(t["disc"], BLACK, 0.6),
        "accent": t["accent"], "tertiary": t["dot"],
        "outline": mix(t["text"], t["ground"], 0.50), "error": ERROR_LIGHT, "onError": WHITE,
    }


def dark_roles(t, key):
    night = key == "nuech"
    base = t["watch"]
    ink = t["text"] if night else t["ground"]
    return {
        "background": base, "surface": mix(base, ink, 0.08), "surfaceVariant": mix(base, ink, 0.14),
        "onSurface": ink, "onSurfaceVariant": mix(ink, base, 0.30),
        "primary": t["star"] if night else at_lightness(t["disc"], 0.72),
        "onPrimary": t["ground"] if night else mix(t["disc"], BLACK, 0.7),
        "primaryContainer": t["disc"] if night else mix(t["disc"], BLACK, 0.35),
        "onPrimaryContainer": mix(t["disc"], WHITE, 0.82),
        "accent": t["accent"] if night else at_lightness(t["accent"], 0.70), "tertiary": t["dot"],
        "outline": mix(ink, base, 0.50), "error": at_lightness(ERROR_DARK_HUE, 0.72), "onError": BLACK,
    }


def contraste_roles():
    return {
        "background": BLACK, "surface": BLACK, "surfaceVariant": BLACK,
        "onSurface": WHITE, "onSurfaceVariant": WHITE,
        "primary": CONTRASTE_YELLOW, "onPrimary": BLACK,
        "primaryContainer": BLACK, "onPrimaryContainer": CONTRASTE_YELLOW,
        "accent": CONTRASTE_YELLOW, "tertiary": CONTRASTE_YELLOW,
        "outline": WHITE, "error": CONTRASTE_ERROR, "onError": BLACK,
    }


def variants(themes):
    """(theme key, light|dark, roles, theme tokens) for every variant shipped."""
    out = []
    for key, t in themes.items():
        if key == "contraste":
            out.append((key, "dark", contraste_roles(), t))
            continue
        if key not in DARK_ONLY:
            out.append((key, "light", light_roles(t), t))
        out.append((key, "dark", dark_roles(t, key), t))
    return out


# --- END shared with trobar-server dev/gen_brand_css.py ---


# --- BEGIN shared with trobar-android dev/gen_brand_tokens.py ---
def with_secondary_container(mode, r):
    """The Android-only additions: Material 3 draws the navigation indicator
    and selected chips in secondaryContainer, so it follows the accent the
    way primaryContainer follows primary; and its cards and bars in the
    surfaceContainer levels, which follow the theme's surfaces."""
    r = dict(r)
    if r["primaryContainer"] == BLACK:  # Contraste
        r["secondaryContainer"], r["onSecondaryContainer"] = BLACK, CONTRASTE_YELLOW
    elif mode == "light":
        r["secondaryContainer"] = mix(r["accent"], WHITE, 0.85)
        r["onSecondaryContainer"] = mix(r["accent"], BLACK, 0.6)
    else:
        r["secondaryContainer"] = mix(r["accent"], BLACK, 0.55)
        r["onSecondaryContainer"] = mix(r["accent"], WHITE, 0.82)
    # Cards, sheets and bars draw on the surfaceContainer levels; left at
    # Material's defaults they were a neutral grey-lavender in every theme.
    # Five even steps from the surface to surfaceVariant, the lowest the
    # page itself in dark mode.
    lowest = r["surface"] if mode == "light" else r["background"]
    for name, t in (("surfaceContainerLowest", None), ("surfaceContainerLow", 0.25), ("surfaceContainer", 0.5),
                    ("surfaceContainerHigh", 0.75), ("surfaceContainerHighest", 1.0)):
        r[name] = lowest if t is None else mix(r["surface"], r["surfaceVariant"], t)
    # Dividers and outlined-button borders: the theme's outline, softened
    # toward the surface (decorative, so no contrast minimum).
    r["outlineVariant"] = r["outline"] if r["outline"] == WHITE else mix(r["outline"], r["surface"], 0.45)
    return r


# --- END shared with trobar-android dev/gen_brand_tokens.py ---


def on_colour(bg):
    return WHITE if ratio(WHITE, bg) >= ratio(BLACK, bg) else BLACK


def complete(mode, r):
    r = with_secondary_container(mode, r)
    r["onSecondary"] = on_colour(r["accent"])
    r["onTertiary"] = on_colour(r["tertiary"])
    return r


ROLES = ("ground", "disc", "star", "dot", "text", "accent")

PAIRS = [
    ("onSurface", "surface", 4.5), ("onSurface", "background", 4.5),
    ("onSurfaceVariant", "surface", 4.5), ("onSurfaceVariant", "background", 4.5),
    ("onPrimary", "primary", 4.5), ("onPrimaryContainer", "primaryContainer", 4.5),
    ("onSecondary", "accent", 4.5), ("onSecondaryContainer", "secondaryContainer", 4.5),
    ("onTertiary", "tertiary", 4.5),
    ("primary", "surface", 4.5), ("accent", "surface", 4.5),
    ("outline", "surface", 3.0), ("error", "surface", 4.5), ("onError", "error", 4.5),
    ("onSurface", "surfaceContainerHighest", 4.5), ("onSurfaceVariant", "surfaceContainerHighest", 4.5),
    ("onSurfaceVariant", "surfaceContainer", 4.5),
]

# Flutter ColorScheme parameter <- derived role
SCHEME = [
    ("primary", "primary"), ("onPrimary", "onPrimary"),
    ("primaryContainer", "primaryContainer"), ("onPrimaryContainer", "onPrimaryContainer"),
    ("secondary", "accent"), ("onSecondary", "onSecondary"),
    ("secondaryContainer", "secondaryContainer"), ("onSecondaryContainer", "onSecondaryContainer"),
    ("tertiary", "tertiary"), ("onTertiary", "onTertiary"),
    ("error", "error"), ("onError", "onError"),
    ("surface", "surface"), ("onSurface", "onSurface"), ("onSurfaceVariant", "onSurfaceVariant"),
    ("surfaceContainerLowest", "surfaceContainerLowest"), ("surfaceContainerLow", "surfaceContainerLow"),
    ("surfaceContainer", "surfaceContainer"), ("surfaceContainerHigh", "surfaceContainerHigh"),
    ("surfaceContainerHighest", "surfaceContainerHighest"),
    ("outline", "outline"), ("outlineVariant", "outlineVariant"),
]


def dart(h):
    return "Color(0xFF" + h.lstrip("#").upper() + ")"


def render():
    data = json.loads(TOKENS.read_text())
    themes = data["themes"]
    schemes = {(k, m): complete(m, r) for k, m, r, t in variants(themes)}
    out = [
        # REUSE-IgnoreStart (the generated file's header, not this file's)
        "// SPDX-FileCopyrightText: 2026 missing-foss",
        "// SPDX-License-Identifier: GPL-3.0-or-later",
        # REUSE-IgnoreEnd
        "// GENERATED by tool/gen_brand_tokens.py from brand/trobar-themes.json. Do not edit:",
        "// change the tokens or the derivation there and rerun it.",
        "",
        "import 'package:flutter/material.dart';",
        "",
        "/// The five brand themes (brand/BRAND.md): the six roles that colour the",
        "/// mark and wordmark. [darkOnly] themes ignore the system light/dark setting.",
        "enum BrandTheme {",
    ]
    entries = []
    for key, t in themes.items():
        roles = ", ".join(f"{role}: {dart(t[role])}" for role in ROLES)
        entries.append(f"  {key}('{key}', '{t['name']}', {roles}, darkOnly: {str(key in DARK_ONLY).lower()})")
    out.append(",\n".join(entries) + ";")
    out += [
        "",
        "  const BrandTheme(this.key, this.displayName,",
        "      {required this.ground, required this.disc, required this.star, required this.dot,",
        "      required this.text, required this.accent, required this.darkOnly});",
        "",
        "  final String key;",
        "  final String displayName;",
        "  final Color ground, disc, star, dot, text, accent;",
        "  final bool darkOnly;",
        "",
        f"  static const BrandTheme fallback = BrandTheme.{data['default']};",
        "",
        "  /// The theme stored under [key]; the default for anything else.",
        "  static BrandTheme of(String? key) =>",
        "      values.firstWhere((t) => t.key == key, orElse: () => fallback);",
        "}",
        "",
        "/// The page background of [theme] in [brightness] (Material 3 has no",
        "/// background role of its own any more: the scaffold takes this).",
        "Color brandBackground(BrandTheme theme, Brightness brightness) {",
        "  final dark = theme.darkOnly || brightness == Brightness.dark;",
        "  switch (theme) {",
    ]
    for key in themes:
        light = schemes.get((key, "light")); dark_ = schemes[(key, "dark")]
        if light is None:
            out.append(f"    case BrandTheme.{key}: return {dart(dark_['background'])};")
        else:
            out.append(f"    case BrandTheme.{key}: return dark ? {dart(dark_['background'])} : {dart(light['background'])};")
    out += ["  }", "}", "",
            "/// [theme]'s derived ColorScheme; a dark-only theme returns its dark",
            "/// scheme whatever [brightness] asks for.",
            "ColorScheme brandColorScheme(BrandTheme theme, Brightness brightness) {",
            "  final dark = theme.darkOnly || brightness == Brightness.dark;",
            "  switch (theme) {"]
    def scheme(r, b):
        args = "".join(f"\n        {p}: {dart(r[role])}," for p, role in SCHEME)
        return f"ColorScheme(\n        brightness: Brightness.{b},{args}\n      )"
    for key in themes:
        light = schemes.get((key, "light")); dark_ = schemes[(key, "dark")]
        if light is None:
            out.append(f"    case BrandTheme.{key}:\n      return {scheme(dark_, 'dark')};")
        else:
            out.append(f"    case BrandTheme.{key}:\n      return dark\n          ? {scheme(dark_, 'dark')}\n          : {scheme(light, 'light')};")
    out += ["  }", "}", ""]
    return "\n".join(out), schemes


def main():
    text, schemes = render()
    failures = []
    for (key, mode), r in schemes.items():
        for fg, bg, minimum in PAIRS:
            got = ratio(r[fg], r[bg])
            if got < minimum:
                failures.append(f"{key} {mode}: {fg} on {bg} is {got:.2f}:1, needs {minimum}:1")
    if "--check" in sys.argv:
        stale = not OUT.exists() or OUT.read_text() != text
        if stale:
            print(f"{OUT.relative_to(ROOT)} is stale: run python3 tool/gen_brand_tokens.py")
        for f in failures:
            print("FAIL", f)
        if stale or failures:
            sys.exit(1)
        print(f"ok ({len(PAIRS) * len(schemes)} pairs across {len(schemes)} theme variants, all at WCAG AA)")
        return
    for f in failures:
        print("FAIL", f)
    if failures:
        sys.exit(1)
    OUT.write_text(text)
    print("wrote", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
