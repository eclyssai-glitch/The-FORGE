extends GutTest
## Palette v2 (Loop 4, GENESIS): tokens exist, stay low-saturation (no neon) and keep their roles'
## luminance ordering. Rules: docs/VISUAL_DIRECTION.md.

const V2 := {
	"SPACE_DEEP": Palette.SPACE_DEEP, "INDIGO": Palette.INDIGO, "NEBULA": Palette.NEBULA,
	"LILAC": Palette.LILAC, "DUSK_ROSE": Palette.DUSK_ROSE, "PEARL": Palette.PEARL,
	"BLUSH": Palette.BLUSH, "GOLD": Palette.GOLD, "GOLD_DEEP": Palette.GOLD_DEEP,
	"MAGMA": Palette.MAGMA, "ICE": Palette.ICE, "STONE": Palette.STONE,
}


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func test_contract_tokens_exist() -> void:
	for n in ["SPACE_DEEP", "INDIGO", "NEBULA", "DUSK_ROSE", "PEARL", "BLUSH", "GOLD", "ICE", "STONE"]:
		assert_true(n in Palette, "Palette.%s" % n)


func test_no_neon_saturation() -> void:
	for n: String in V2:
		var c: Color = V2[n]
		assert_lte(c.s, 0.6, "%s saturation %.2f" % [n, c.s])
		assert_eq(c.a, 1.0, "%s opaque" % n)


func test_night_base_is_dark_and_ordered() -> void:
	assert_lt(_lum(Palette.SPACE_DEEP), 0.03, "SPACE_DEEP near black")
	assert_gt(_lum(Palette.SPACE_DEEP), 0.0, "SPACE_DEEP never pure black")
	assert_lt(_lum(Palette.SPACE_DEEP), _lum(Palette.INDIGO))
	assert_lt(_lum(Palette.INDIGO), _lum(Palette.NEBULA))
	assert_lt(_lum(Palette.NEBULA), _lum(Palette.LILAC))
	assert_lt(_lum(Palette.STONE), 0.15, "hands' stone stays night-dark")


func test_light_tones_are_light_but_not_white() -> void:
	for c: Color in [Palette.PEARL, Palette.BLUSH]:
		assert_gt(_lum(c), 0.75)
		assert_false(c.is_equal_approx(Color.WHITE))
	assert_gt(_lum(Palette.GOLD), _lum(Palette.MAGMA))
	assert_gt(_lum(Palette.MAGMA), _lum(Palette.GOLD_DEEP))


func test_blue_is_not_turquoise() -> void:
	# ICE and the night tones lean blue/violet, never cyan-green (no turquoise anywhere in v2).
	for n: String in V2:
		var c: Color = V2[n]
		if c.s < 0.15:
			continue
		var hue_deg := c.h * 360.0
		assert_false(hue_deg > 160.0 and hue_deg < 200.0, "%s hue %.0f° is turquoise" % [n, hue_deg])


func test_motion_v2() -> void:
	assert_between(Palette.T_BREATH, 4.0, 8.0, "breath 4–8 s")
	assert_between(Palette.T_BREATH_SLOW, Palette.T_BREATH, 8.0)
	assert_gt(Palette.T_SWELL, Palette.T_SLOW, "formation swells, never flashes")
	assert_gt(Palette.T_CRANE, Palette.T_CINEMATIC)
	assert_gt(Palette.T_HALO_TURN, 30.0)


func test_v1_tokens_still_present() -> void:
	# The ORIGIN scene keeps using v1 until the switch (Phase C).
	for n in ["VOID", "ABYSS", "GRAPHITE", "SLATE", "ASH", "BONE", "PALE", "EMBER", "EMBER_DEEP"]:
		assert_true(n in Palette, "Palette.%s kept" % n)
