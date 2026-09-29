extends GutTest
## UI theme (Loop 3): built from Palette + the embedded fonts, no EMBER/PALE anywhere in the UI.


func test_theme_builds_with_embedded_fonts() -> void:
	var t := UiTheme.get_theme()
	assert_not_null(t)
	assert_same(t, UiTheme.get_theme(), "shared instance")
	assert_eq(t.default_font_size, Palette.SIZE_BODY)
	var sans := t.default_font as FontVariation
	assert_not_null(sans)
	assert_eq((sans.base_font as FontFile).resource_path, Palette.FONT_SANS)
	var mono := t.get_font("font", "Data") as FontFile
	assert_not_null(mono)
	assert_eq(mono.resource_path, Palette.FONT_MONO)
	assert_eq((t.get_font("font", "BadgeText") as FontFile).resource_path, Palette.FONT_MONO_MEDIUM)


func test_type_variations_exist() -> void:
	var t := UiTheme.get_theme()
	for v in ["Caption", "Title", "Body", "Data", "DataDim", "RowText", "BadgeText"]:
		assert_eq(t.get_type_variation_base(v), &"Label", v)
	for v in ["ModeTab", "TransportButton", "Chip", "Action"]:
		assert_eq(t.get_type_variation_base(v), &"Button", v)
	for v in ["HudPanel", "Sheet", "BadgePanel", "Bare"]:
		assert_eq(t.get_type_variation_base(v), &"PanelContainer", v)


func test_labels_are_legible_sizes() -> void:
	var t := UiTheme.get_theme()
	for v in ["Caption", "Title", "Body", "Data", "DataDim", "RowText", "BadgeText"]:
		assert_between(t.get_font_size("font_size", v), 11, 15, "%s size" % v)


func test_ui_never_uses_ember_or_pale() -> void:
	var t := UiTheme.get_theme()
	for type in t.get_color_type_list():
		for c in t.get_color_list(type):
			var col := t.get_color(c, type)
			assert_false(col.is_equal_approx(Palette.EMBER) or col.is_equal_approx(Palette.EMBER_DEEP),
				"%s/%s is EMBER" % [type, c])
			assert_false(col.is_equal_approx(Palette.PALE), "%s/%s is PALE" % [type, c])
	for type in t.get_stylebox_type_list():
		for n in t.get_stylebox_list(type):
			var sb := t.get_stylebox(n, type) as StyleBoxFlat
			if sb == null:
				continue
			for col in [sb.bg_color, sb.border_color]:
				assert_false(col.is_equal_approx(Palette.EMBER) or col.is_equal_approx(Palette.PALE),
					"%s/%s stylebox" % [type, n])


func test_demo_badge_style() -> void:
	var b := DemoBadge.new()
	add_child_autofree(b)
	assert_true(b.is_in_group(DemoBadge.GROUP))
	assert_eq(b.label.text, DemoBadge.TEXT)
	assert_true(b.label.text.contains("DEMO"))
	assert_eq(b.label.theme_type_variation, &"BadgeText")
	assert_eq(b.theme_type_variation, &"BadgePanel")
	var panel := UiTheme.get_theme().get_stylebox("panel", "BadgePanel") as StyleBoxFlat
	assert_eq(panel.bg_color, Palette.PANEL)
	assert_eq(panel.border_color, Palette.PANEL_LINE)
	assert_eq(UiTheme.get_theme().get_color("font_color", "BadgeText"), Palette.BONE)


func test_fade_hides_after_fading_out() -> void:
	var c := Control.new()
	add_child_autofree(c)
	UiKit.fade(c, false, 0.05)
	await wait_seconds(0.2)
	assert_false(c.visible)
	UiKit.fade(c, true, 0.05)
	assert_true(c.visible, "visible at once when fading in")
	await wait_seconds(0.2)
	assert_almost_eq(c.modulate.a, 1.0, 0.01)


func test_kit_defaults() -> void:
	var b := UiKit.button("X")
	var l := UiKit.label("X")
	var v := UiKit.vbox()
	for n: Node in [b, l, v]:
		autofree(n)
	assert_eq(b.focus_mode, Control.FOCUS_NONE)
	assert_eq(l.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(v.mouse_filter, Control.MOUSE_FILTER_IGNORE)
