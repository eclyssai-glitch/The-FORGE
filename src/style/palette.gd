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

const FONT_SANS := "res://assets/fonts/Inter-Variable.ttf"
const FONT_MONO := "res://assets/fonts/IBMPlexMono-Regular.ttf"
const FONT_MONO_MEDIUM := "res://assets/fonts/IBMPlexMono-Medium.ttf"

## Motion (seconds).
const T_FAST := 0.22
const T_BASE := 0.6
const T_SLOW := 1.4
const T_CINEMATIC := 2.6
