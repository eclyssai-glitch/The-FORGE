class_name UiTheme
extends RefCounted
## The native UI theme, built in code from Palette + the embedded OFL fonts (Inter for labels,
## IBM Plex Mono for data, times and IDs). Owner: art-director. Rules: docs/VISUAL_DIRECTION.md, "UI".
##
## Type variations (set `theme_type_variation` on a node):
##   Label:  Caption (11 px spaced caps, dim) · Title (13 px spaced caps, BONE) · Body (12 px, dim,
##           prose) · Data (12 px mono, BONE) · DataDim (11 px mono, dim) · BadgeText (11 px mono medium)
##   Button: ModeTab (top bar) · TransportButton (outlined) · Chip (small toggles) · Action (flat link)
##   PanelContainer: HudPanel (default: translucent PANEL + hairline) · BadgePanel · Sheet (OBSERVATORY)
## Nothing here is EMBER or PALE: the UI carries no energy and does not verify anything.
##
## GENESIS (UI v2, src/ui/genesis): pearl ink over the night, no boxes, never GOLD.
##   Label:  Whisper (thin, widely spaced capitals) · Word / WordSoft / WordFaint (spaced capitals at
##           three ink levels) · Verse (12 px prose, soft) · CardTitle · Clock (mono) · SealText
##   Button: WordButton (flat word: faint -> soft on hover -> ink when pressed) · ModeWord (pearl;
##           the owner fades it with self_modulate) · GlyphButton (no text: the glyph is drawn)
##   PanelContainer: Card (night veil + one pearl hairline on the left) · Seal (bare)

static var _theme: Theme
## Cache of fonts and shared styleboxes.
static var _fonts: Dictionary = {}


## Shared theme instance (built once).
static func get_theme() -> Theme:
	if _theme == null:
		_theme = build()
	return _theme


static func font_sans(weight: int = 420, tracking: int = 0) -> Font:
	var key := "sans_%d_%d" % [weight, tracking]
	if not _fonts.has(key):
		var fv := FontVariation.new()
		fv.base_font = load(Palette.FONT_SANS) as FontFile
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): weight}
		fv.spacing_glyph = tracking
		_fonts[key] = fv
	return _fonts[key]


## Plex Mono with letter spacing (px per glyph), cached.
static func font_mono_spaced(medium: bool, tracking: int) -> Font:
	var key := "mono_%s_%d" % [medium, tracking]
	if not _fonts.has(key):
		var fv := FontVariation.new()
		fv.base_font = font_mono(medium)
		fv.spacing_glyph = tracking
		_fonts[key] = fv
	return _fonts[key]


static func font_mono(medium: bool = false) -> Font:
	var key := "mono_medium" if medium else "mono"
	if not _fonts.has(key):
		_fonts[key] = load(Palette.FONT_MONO_MEDIUM if medium else Palette.FONT_MONO) as FontFile
	return _fonts[key]


## Flat box: fill, 1 px border (sides given by `sides`: Vector4i left, top, right, bottom widths),
## content margins (horizontal, vertical).
static func box(fill: Color, border: Color = Palette.CLEAR, sides: Vector4i = Vector4i.ZERO,
		margin_h: float = 0.0, margin_v: float = 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.border_width_left = sides.x
	sb.border_width_top = sides.y
	sb.border_width_right = sides.z
	sb.border_width_bottom = sides.w
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	sb.anti_aliasing = false
	return sb


static func empty(margin_h: float = 0.0, margin_v: float = 0.0) -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb


## Row styles for ListRow (cached): normal / hover / selected (BONE hairline at the left edge).
static func row_style(state: StringName) -> StyleBox:
	var key := "row_" + String(state)
	if not _fonts.has(key):
		match state:
			&"hover":
				_fonts[key] = box(Palette.PANEL_HOVER, Palette.PANEL_LINE, Vector4i(2, 0, 0, 0), 8, 3)
			&"selected":
				_fonts[key] = box(Palette.PANEL_ACTIVE, Palette.BONE, Vector4i(2, 0, 0, 0), 8, 3)
			_:
				_fonts[key] = box(Palette.CLEAR, Palette.CLEAR, Vector4i(2, 0, 0, 0), 8, 3)
	return _fonts[key]


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font_sans()
	t.default_font_size = Palette.SIZE_BODY

	var caps := font_sans(520, Palette.TRACKING)
	var caps_strong := font_sans(600, Palette.TRACKING)
	var mono := font_mono()
	var mono_medium := font_mono(true)
	var clear := Palette.CLEAR

	# --- Labels ---
	t.set_color("font_color", "Label", Palette.BONE)
	t.set_color("font_shadow_color", "Label", clear)
	t.set_constant("line_spacing", "Label", 2)
	_label(t, "Caption", caps, Palette.SIZE_SMALL, Palette.TEXT_DIM)
	_label(t, "Title", caps_strong, Palette.SIZE_LABEL, Palette.BONE)
	_label(t, "Body", font_sans(400), Palette.SIZE_BODY, Palette.TEXT_DIM)
	_label(t, "Data", mono, Palette.SIZE_BODY, Palette.BONE)
	_label(t, "DataDim", mono, Palette.SIZE_SMALL, Palette.TEXT_DIM)
	_label(t, "RowText", caps, Palette.SIZE_SMALL, Palette.BONE)
	_label(t, "BadgeText", mono_medium, Palette.SIZE_SMALL, Palette.BONE)

	# --- Panels ---
	t.set_stylebox("panel", "PanelContainer", box(Palette.PANEL, Palette.PANEL_LINE, Vector4i.ONE, 16, 14))
	t.set_type_variation("HudPanel", "PanelContainer")
	t.set_stylebox("panel", "HudPanel", box(Palette.PANEL, Palette.PANEL_LINE, Vector4i.ONE, 16, 14))
	t.set_type_variation("Sheet", "PanelContainer")
	t.set_stylebox("panel", "Sheet", box(Palette.PANEL, Palette.PANEL_LINE, Vector4i.ONE, 22, 18))
	t.set_type_variation("BadgePanel", "PanelContainer")
	t.set_stylebox("panel", "BadgePanel", box(Palette.PANEL, Palette.PANEL_LINE, Vector4i.ONE, 10, 5))
	t.set_type_variation("Bare", "PanelContainer")
	t.set_stylebox("panel", "Bare", empty())

	# --- Separators / containers ---
	var line := StyleBoxLine.new()
	line.color = Palette.PANEL_LINE
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 18)
	t.set_constant("separation", "VBoxContainer", 4)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("h_separation", "GridContainer", 12)
	t.set_constant("v_separation", "GridContainer", 3)
	t.set_stylebox("panel", "ScrollContainer", empty())
	for sb_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_type, box(clear, clear, Vector4i.ZERO, 2, 2))
		t.set_stylebox("scroll_focus", sb_type, box(clear, clear, Vector4i.ZERO, 2, 2))
		t.set_stylebox("grabber", sb_type, box(Palette.PANEL_LINE, clear, Vector4i.ZERO, 2, 2))
		t.set_stylebox("grabber_highlight", sb_type, box(Palette.LINE_STRONG, clear, Vector4i.ZERO, 2, 2))
		t.set_stylebox("grabber_pressed", sb_type, box(Palette.LINE_STRONG, clear, Vector4i.ZERO, 2, 2))

	# --- Buttons (base: flat text action) ---
	_button_colors(t, "Button")
	t.set_font("font", "Button", caps)
	t.set_font_size("font_size", "Button", Palette.SIZE_SMALL)
	t.set_stylebox("normal", "Button", empty(8, 5))
	t.set_stylebox("hover", "Button", box(Palette.PANEL_HOVER, clear, Vector4i.ZERO, 8, 5))
	t.set_stylebox("pressed", "Button", box(Palette.PANEL_ACTIVE, clear, Vector4i.ZERO, 8, 5))
	t.set_stylebox("hover_pressed", "Button", box(Palette.PANEL_ACTIVE, clear, Vector4i.ZERO, 8, 5))
	t.set_stylebox("disabled", "Button", empty(8, 5))
	t.set_stylebox("focus", "Button", empty())

	t.set_type_variation("Action", "Button")

	# Mode tabs: ASH text, BONE + 1 px underline when active.
	t.set_type_variation("ModeTab", "Button")
	t.set_font("font", "ModeTab", caps)
	t.set_font_size("font_size", "ModeTab", Palette.SIZE_SMALL)
	t.set_stylebox("normal", "ModeTab", box(clear, clear, Vector4i(0, 0, 0, 1), 10, 7))
	t.set_stylebox("hover", "ModeTab", box(clear, Palette.PANEL_LINE, Vector4i(0, 0, 0, 1), 10, 7))
	t.set_stylebox("pressed", "ModeTab", box(clear, Palette.BONE, Vector4i(0, 0, 0, 1), 10, 7))
	t.set_stylebox("hover_pressed", "ModeTab", box(clear, Palette.BONE, Vector4i(0, 0, 0, 1), 10, 7))

	# Transport: outlined, a little more weight.
	t.set_type_variation("TransportButton", "Button")
	t.set_font("font", "TransportButton", caps_strong)
	t.set_stylebox("normal", "TransportButton", box(clear, Palette.PANEL_LINE, Vector4i.ONE, 12, 6))
	t.set_stylebox("hover", "TransportButton", box(Palette.PANEL_HOVER, Palette.LINE_STRONG, Vector4i.ONE, 12, 6))
	t.set_stylebox("pressed", "TransportButton", box(Palette.PANEL_ACTIVE, Palette.LINE_STRONG, Vector4i.ONE, 12, 6))
	t.set_stylebox("hover_pressed", "TransportButton", box(Palette.PANEL_ACTIVE, Palette.LINE_STRONG, Vector4i.ONE, 12, 6))
	t.set_color("font_color", "TransportButton", Palette.BONE)

	# Chips: small mono toggles (speed, quality).
	t.set_type_variation("Chip", "Button")
	t.set_font("font", "Chip", mono)
	t.set_font_size("font_size", "Chip", Palette.SIZE_SMALL)
	t.set_stylebox("normal", "Chip", box(clear, clear, Vector4i.ONE, 6, 4))
	t.set_stylebox("hover", "Chip", box(Palette.PANEL_HOVER, Palette.PANEL_LINE, Vector4i.ONE, 6, 4))
	t.set_stylebox("pressed", "Chip", box(Palette.PANEL_ACTIVE, Palette.LINE_STRONG, Vector4i.ONE, 6, 4))
	t.set_stylebox("hover_pressed", "Chip", box(Palette.PANEL_ACTIVE, Palette.LINE_STRONG, Vector4i.ONE, 6, 4))
	_build_genesis(t)
	return t


## UI v2 (GENESIS) variations: see the header. Text keeps a soft night shade so thin pearl letters
## stay legible over the warm nebula core.
static func _build_genesis(t: Theme) -> void:
	var clear := Palette.CLEAR
	var word := font_sans(Palette.WEIGHT_WORD, Palette.TRACKING_WORD)
	_label(t, "Whisper", font_sans(Palette.WEIGHT_THIN, Palette.TRACKING_WHISPER), Palette.SIZE_WHISPER, Palette.PEARL)
	_label(t, "Word", word, Palette.SIZE_SMALL, Palette.UI_INK)
	_label(t, "WordSoft", word, Palette.SIZE_SMALL, Palette.UI_INK_SOFT)
	_label(t, "WordFaint", word, Palette.SIZE_SMALL, Palette.UI_INK_FAINT)
	_label(t, "Verse", font_sans(400, 0), Palette.SIZE_BODY, Palette.UI_INK_SOFT)
	_label(t, "CardTitle", font_sans(480, Palette.TRACKING_WORD), Palette.SIZE_TITLE, Palette.UI_INK)
	_label(t, "Clock", font_mono_spaced(false, 1), Palette.SIZE_SMALL, Palette.UI_INK_SOFT)
	_label(t, "SealText", font_mono_spaced(true, 2), Palette.SIZE_SMALL, Palette.UI_INK_SOFT)
	for v in ["Whisper", "Word", "WordSoft", "WordFaint", "Verse", "CardTitle", "Clock", "SealText"]:
		t.set_color("font_shadow_color", v, Palette.UI_SHADE)
		t.set_constant("shadow_offset_x", v, 0)
		t.set_constant("shadow_offset_y", v, 1)
		t.set_constant("shadow_outline_size", v, 3)

	t.set_type_variation("WordButton", "Button")
	t.set_font("font", "WordButton", word)
	t.set_font_size("font_size", "WordButton", Palette.SIZE_SMALL)
	t.set_color("font_color", "WordButton", Palette.UI_INK_FAINT)
	t.set_color("font_hover_color", "WordButton", Palette.UI_INK_SOFT)
	t.set_color("font_focus_color", "WordButton", Palette.UI_INK_FAINT)
	t.set_color("font_pressed_color", "WordButton", Palette.UI_INK)
	t.set_color("font_hover_pressed_color", "WordButton", Palette.UI_INK)
	t.set_color("font_disabled_color", "WordButton", Palette.UI_THREAD)
	t.set_color("font_outline_color", "WordButton", clear)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "WordButton", empty(6, 4))
	t.set_stylebox("focus", "WordButton", empty())

	t.set_type_variation("ModeWord", "Button")
	t.set_font("font", "ModeWord", word)
	t.set_font_size("font_size", "ModeWord", Palette.SIZE_SMALL)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "ModeWord", Palette.PEARL)
	t.set_color("font_outline_color", "ModeWord", clear)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "ModeWord", empty(12, 8))
	t.set_stylebox("focus", "ModeWord", empty())

	t.set_type_variation("GlyphButton", "Button")
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(st, "GlyphButton", empty())

	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", box(Palette.UI_VEIL, Palette.UI_THREAD, Vector4i(1, 0, 0, 0), 16, 12))
	t.set_type_variation("Seal", "PanelContainer")
	t.set_stylebox("panel", "Seal", empty(0, 2))


static func _label(t: Theme, variation: String, font: Font, size: int, color: Color) -> void:
	t.set_type_variation(variation, "Label")
	t.set_font("font", variation, font)
	t.set_font_size("font_size", variation, size)
	t.set_color("font_color", variation, color)


static func _button_colors(t: Theme, type: String) -> void:
	t.set_color("font_color", type, Palette.TEXT_DIM)
	t.set_color("font_hover_color", type, Palette.BONE)
	t.set_color("font_pressed_color", type, Palette.BONE)
	t.set_color("font_hover_pressed_color", type, Palette.BONE)
	t.set_color("font_focus_color", type, Palette.TEXT_DIM)
	t.set_color("font_disabled_color", type, Palette.SLATE)
	t.set_color("font_outline_color", type, Palette.CLEAR)
