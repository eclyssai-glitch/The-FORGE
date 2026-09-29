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
