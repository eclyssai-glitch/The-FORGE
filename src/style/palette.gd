class_name Palette
extends RefCounted
## Single source of colour, type and motion for both the 3D world and the native UI.
## Monochrome base with one controlled accent (EMBER) reserved for energy/activation,
## and PALE reserved for verification. Never introduce loose colour literals elsewhere.

const VOID := Color("#040405")
const ABYSS := Color("#0a0a0c")
const GRAPHITE := Color("#17181b")
const SLATE := Color("#2a2c31")
const ASH := Color("#77797f")
const BONE := Color("#d8d4cb")
const PALE := Color("#f3f0e8")
const EMBER := Color("#d98a4e")
const EMBER_DEEP := Color("#7a3f1c")

## UI panel fill: translucent abyss so the universe stays visible behind panels.
const PANEL := Color(0.039, 0.039, 0.047, 0.82)
const PANEL_LINE := Color(0.847, 0.831, 0.796, 0.10)
## Fully transparent (empty UI fills and borders).
const CLEAR := Color(0, 0, 0, 0)
## UI interaction washes (BONE at low alpha): hover and pressed/selected fills, a stronger hairline
## for the selected row marker and the timeline track. Never EMBER/PALE: the UI carries no energy.
const PANEL_HOVER := Color(0.847, 0.831, 0.796, 0.05)
const PANEL_ACTIVE := Color(0.847, 0.831, 0.796, 0.09)
const LINE_STRONG := Color(0.847, 0.831, 0.796, 0.34)
## Secondary UI text: ASH, lifted slightly so 11 px mono stays legible over the void.
const TEXT_DIM := Color("#8b8d92")

const FONT_SANS := "res://assets/fonts/Inter-Variable.ttf"
const FONT_MONO := "res://assets/fonts/IBMPlexMono-Regular.ttf"
const FONT_MONO_MEDIUM := "res://assets/fonts/IBMPlexMono-Medium.ttf"

## UI type scale (px) and letter spacing (px per glyph) for spaced uppercase labels.
const SIZE_SMALL := 11
const SIZE_BODY := 12
const SIZE_LABEL := 13
const SIZE_TITLE := 15
const TRACKING := 1
## UI layout (px): distance of the chrome to the window edge, and the gap between blocks.
const UI_EDGE := 24
const UI_GAP := 12
## OBSERVATORY: share of the width taken by the left panel (the world lives on the right).
const OBSERVATORY_PANEL_SHARE := 0.38

## Motion (seconds).
const T_FAST := 0.22
const T_BASE := 0.6
const T_SLOW := 1.4
const T_CINEMATIC := 2.6
## HUD text refresh period (time, phase): 10 Hz, never per frame.
const T_UI_REFRESH := 0.1

# --- Palette v2 (Loop 4, "GENESIS"). Rules and roles: docs/VISUAL_DIRECTION.md. --------------------
# Night-sky base (SPACE_DEEP -> INDIGO -> NEBULA), warm creation light (DUSK_ROSE, GOLD), MIKU's
# porcelain (PEARL, BLUSH), knowledge (ICE) and the hands' stone (STONE). Low saturation, no neon:
# every v2 token keeps HSV saturation <= 0.6 (test_style_palette_v2). The v1 tokens above stay
# until the scene switches to GENESIS (Phase C).

## Deepest space: sky floor, background, depth fog. Never pure black: a breath of blue.
const SPACE_DEEP := Color("#05060b")
## Night body of the sky and of shadowed matter; ambient light colour.
const INDIGO := Color("#141a30")
## Violet of the nebula clouds; the hair's far tips; fill light.
const NEBULA := Color("#3a2d63")
## Luminous violet (hair tips, thread ends, nebula highlights) — NEBULA lifted to be emissive.
const LILAC := Color("#9a88c6")
## Warm rose of the backlight nebula core and of the rim light; the hair's middle.
const DUSK_ROSE := Color("#c48b9f")
## MIKU's porcelain: pearl white, warm, never pure white.
const PEARL := Color("#f4efe9")
## Porcelain translucency / grazing sheen; the warm side of pearl.
const BLUSH := Color("#f2d6d0")
## Creation: kintsugi veins, magma, the seed on MIKU's brow, formation light. The one warm accent.
const GOLD := Color("#e9b872")
## Molten copper: the mid-tone of incandescent magma between GOLD_DEEP and GOLD (never orange neon).
const MAGMA := Color("#c47a50")
## Deep gold: cooled magma, crack floors, the dark end of the gold ramp.
const GOLD_DEEP := Color("#7d5836")
## Knowledge / documentation: ice moons, the planet's atmosphere, cool rim light.
const ICE := Color("#a9c6e8")
## The auxiliary hands' night stone (polished blue basalt); planet crust; asteroids.
const STONE := Color("#1b1e2e")

## Motion v2 (seconds). Nothing in GENESIS moves faster than it breathes.
## Ambient breathing period (MIKU's light, hands, halo shimmer): 4–8 s band, sine only.
const T_BREATH := 6.0
## Slowest breath (nebula shimmer, belt drift glints).
const T_BREATH_SLOW := 8.0
## Formation swell: a body inflates / accretes into existence over this time (never a flash).
const T_SWELL := 3.2
## Camera crane / dolly between compositions.
const T_CRANE := 7.0
## One full turn of MIKU's astrolabe halo.
const T_HALO_TURN := 90.0
