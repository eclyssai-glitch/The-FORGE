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

# --- UI v2 (Loop 4, GENESIS HUD; docs/VISUAL_DIRECTION.md section 8) ------------------------------
# The UI speaks in pearl ink at a few opacities over the night, never in boxes; it never uses GOLD
# (the UI creates nothing). Ink levels, from the word being read to the thread that leads to it:

## Active word, card title, a whisper at its peak.
const UI_INK := Color(0.957, 0.937, 0.914, 0.9)
## Secondary text, hovered words, done objectives, the elapsed part of the transport arc.
const UI_INK_SOFT := Color(0.957, 0.937, 0.914, 0.6)
## Inactive words, pending objectives, the legend.
const UI_INK_FAINT := Color(0.957, 0.937, 0.914, 0.34)
## Leader lines of labels in space, the revealed arc track.
const UI_THREAD := Color(0.957, 0.937, 0.914, 0.22)
## The collapsed transport line (the scene is the hero).
const UI_THREAD_FAINT := Color(0.957, 0.937, 0.914, 0.1)
## Night veil behind a floating card (SPACE_DEEP, translucent: the universe stays visible).
const UI_VEIL := Color(0.02, 0.024, 0.043, 0.62)
## Soft night shade under text and at the bottom edge when the transport is revealed.
const UI_SHADE := Color(0.02, 0.024, 0.043, 0.55)

## Type v2: thin, widely spaced capitals (Inter light) for whispers and words; Plex Mono for time.
const WEIGHT_THIN := 300
const WEIGHT_WORD := 420
const SIZE_WHISPER := 15
const TRACKING_WORD := 3
const TRACKING_WHISPER := 7

## Motion v2 of the UI (seconds, sine fades only, nothing pops).
## Whisper of an event: rises, rests, dissolves.
const T_WHISPER_IN := 1.4
const T_WHISPER_HOLD := 3.0
const T_WHISPER_OUT := 2.4
## A newer whisper first dissolves the one showing (this long from full ink), then rises: one line
## at a time, never two words over each other.
const T_WHISPER_HANDOFF := 0.6
## Transport arc: reveal when the pointer nears the bottom edge (or on pause), conceal after a linger.
const T_REVEAL := 0.8
const T_CONCEAL := 1.6
const T_REVEAL_LINGER := 1.4
## A label in space fading in/out beside its body.
const T_LABEL := 0.9

## Layout v2 (px): pointer distance to the bottom edge that reveals the transport; arc width share
## and sagitta; leader line of a label in space (diagonal, then horizontal run).
const UI_REVEAL_ZONE := 120
const UI_ARC_SHARE := 0.5
const UI_ARC_SAG := 9.0
const UI_LEADER := 26.0
const UI_LEADER_RUN := 12.0

# --- Living (Loop 5, MIKU LIVING CHARACTER prototype; docs/VISUAL_DIRECTION.md section 12) ---------
# No new hues: the living materials and the call line reuse the v2 tokens above. Only motion and
# layout of what the living scenario adds.

## Confirmation of a validated configuration artifact: `validated` goes 0 -> 1 over this time (the
## short pulse lives inside that ramp; at 1 the sheet is calm and sealed).
const T_CONFIRM := 0.9
## Call line: draw-in when Enter opens it, retract after a submission / cancel (sine).
const T_CALL_OPEN := 0.45
const T_CALL_CLOSE := 0.9
## Whisper of the recognised intent under the call line: rises, rests, dissolves (sine).
const T_CALL_ECHO_IN := 0.5
const T_CALL_ECHO_HOLD := 2.4
const T_CALL_ECHO_OUT := 1.6
## The immediate "→ <assunto>" of a request that has just started rests (instead of T_CALL_ECHO_HOLD)
## until that request's result replaces it; past this cap it dissolves on its own.
const T_CALL_ECHO_WAIT := 20.0
## Call line geometry (px): open width, resting hairline width, distance of the line from the
## bottom edge (clear of the transport arc and its revealed controls), echo gap above the line.
const UI_CALL_WIDTH := 440.0
const UI_CALL_REST := 44.0
const UI_CALL_FROM_BOTTOM := 104.0
const UI_CALL_ECHO_GAP := 30.0
## Typed text of the call line (thin pearl, not tracked: it is speech, not a label).
const SIZE_CALL := 15
