extends GutTest
## LocalParser (Loop 5): deterministic pt-BR + en parsing into Intents.

var worlds: Array


func before_each() -> void:
	worlds = LivingScript.world_directory()


func _p(text: String) -> Intent:
	return LocalParser.parse(text, worlds)


func test_attention_pt_and_en() -> void:
	for t in ["Miku!", "Miku", "miku?", "Miku, olha aqui", "Ei, Miku!", "Miku, olhe para mim", "Hey Miku, look here",
			"Miku, look at me", "olha aqui"]:
		var i := _p(t)
		assert_eq(i.kind, Intent.Kind.ATTENTION, t)
		assert_eq(i.route, Intent.Route.LOCAL, t)
		assert_eq(i.target, &"miku", t)
		assert_eq(i.text, t)


func test_world_target_by_side_and_name() -> void:
	var cases := {
		"Miku, trabalhe no planeta da esquerda": &"world_vesper",
		"Miku, trabalhe no planeta da direita": &"world_orrin",
		"Miku, olhe o mundo do centro": &"world_calyx",
		"Miku, work on the planet on the left": &"world_vesper",
		"Miku, work on the right world": &"world_orrin",
		"Miku, trabalhe em Orrin": &"world_orrin",
		"Miku, trabalhe no planeta VÉSPER": &"world_vesper",
		"Miku, go to calyx": &"world_calyx",
	}
	for t: String in cases:
		var i := _p(t)
		assert_eq(i.kind, Intent.Kind.WORLD_TARGET, t)
		assert_eq(i.target, cases[t], t)
		assert_eq(i.route, Intent.Route.LOCAL)


func test_world_sides_follow_the_given_directory() -> void:
	var flipped := LivingScript.world_directory()
	flipped[0]["side"] = &"right"
	flipped[2]["side"] = &"left"
	assert_eq(LocalParser.parse("Miku, trabalhe no planeta da esquerda", flipped).target, &"world_orrin")
	var two := [{"id": &"world_vesper", "name": "VESPER", "side": &"left"}, {"id": &"world_orrin", "name": "ORRIN", "side": &"right"}]
	var none := LocalParser.parse("Miku, trabalhe no planeta do centro", two)
	assert_eq(none.kind, Intent.Kind.UNKNOWN, "no world there")
	assert_true(none.rule.begins_with("world_not_found"))


func test_relative_appearance_patches() -> void:
	var i := _p("Miku, aumente sua altura")
	assert_eq(i.kind, Intent.Kind.CONFIG_PATCH)
	assert_eq(i.route, Intent.Route.LOCAL)
	assert_eq(i.lang, "pt")
	assert_eq(i.patch.path, "appearance.height")
	assert_true(i.patch.relative)
	assert_almost_eq(i.patch.delta, 0.03, 1e-6, "one schema step")
	var s := _p("Miku, ombros um pouco mais largos")
	assert_eq(s.kind, Intent.Kind.CONFIG_PATCH)
	assert_eq(s.patch.path, "appearance.shoulder_width")
	assert_almost_eq(s.patch.delta, 0.02, 1e-6, "'um pouco' = half a step")
	var d := _p("Miku, diminua muito o brilho")
	assert_eq(d.patch.path, "appearance.glow")
	assert_almost_eq(d.patch.delta, -0.2, 1e-6, "'muito' = two steps down")
	var e := _p("Miku, make yourself a bit taller")
	assert_eq(e.lang, "en")
	assert_eq(e.patch.path, "appearance.height")
	assert_almost_eq(e.patch.delta, 0.015, 1e-6)
	var n := _p("Miku, fique menos alta")
	assert_almost_eq(n.patch.delta, -0.03, 1e-6, "negated adjective")
	var h := _p("Miku, um halo maior")
	assert_eq(h.patch.path, "appearance.halo_radius")
	assert_gt(h.patch.delta, 0.0)
	var neck := _p("Miku, a longer neck please")
	assert_eq(neck.patch.path, "appearance.neck_length")
	assert_gt(neck.patch.delta, 0.0)


func test_structured_commands() -> void:
	var a := _p("chest_volume 0.52")
	assert_eq(a.kind, Intent.Kind.CONFIG_PATCH)
	assert_eq(a.patch.path, "chest_volume")
	assert_false(a.patch.relative)
	assert_almost_eq(float(a.patch.value), 0.52, 1e-6)
	var b := _p("appearance.height 1.04")
	assert_eq(b.patch.path, "appearance.height")
	assert_almost_eq(float(b.patch.value), 1.04, 1e-6)
	var c := _p("set behaviour.patience 0.7")
	assert_eq(c.kind, Intent.Kind.CONFIG_PATCH)
	assert_eq(c.patch.path, "behaviour.patience", "section kept as written (the validator corrects it)")
	var d := _p("Miku, defina glow para 0,8")
	assert_almost_eq(float(d.patch.value), 0.8, 1e-6, "comma decimal")
	var e := _p("appearance.hair_color pink")
	assert_eq(e.kind, Intent.Kind.CONFIG_PATCH)
	assert_eq(e.patch.value, "pink")
	var f := _p("identity.curiosity=0.9")
	assert_eq(f.patch.path, "identity.curiosity")
	assert_eq(f.rule, "structured")


func test_subjective_and_compound_go_semantic() -> void:
	for t in ["Miku, fique mais curiosa, mas menos impulsiva", "Miku, be more curious but less impulsive",
			"Miku, fique mais curiosa", "Miku, me conte uma história", "Miku, aumente sua altura e o brilho",
			"Miku, sua altura"]:
		var i := _p(t)
		assert_eq(i.kind, Intent.Kind.SEMANTIC, t)
		assert_eq(i.route, Intent.Route.PROVIDER, t)
		assert_null(i.patch, t)


func test_asset_requests_are_config_patches_on_unsupported_features() -> void:
	for t in ["Miku, me dê asas", "Miku, mude a cor do cabelo para rosa", "Miku, give yourself wings", "Miku, um vestido novo"]:
		var i := _p(t)
		assert_eq(i.kind, Intent.Kind.CONFIG_PATCH, t)
		assert_true(i.rule.begins_with("asset:"), t)
		var v := ConfigValidator.validate(i.patch, ConfigSchema.fallback_values())
		assert_eq(v.status, ConfigValidator.Status.REQUIRES_ASSET, t)


func test_unknown_and_determinism() -> void:
	assert_eq(_p("").kind, Intent.Kind.UNKNOWN)
	assert_eq(_p("   ?!  ").kind, Intent.Kind.UNKNOWN)
	var a := _p("Miku, ombros um pouco mais largos")
	var b := _p("Miku, ombros um pouco mais largos")
	assert_eq(a.to_dict(), b.to_dict(), "same text, same intent")


func test_normalize_and_language() -> void:
	assert_eq(LocalParser.normalize("  Ação   Pescoço  "), "acao pescoco")
	assert_eq(LocalParser.detect_language("Miku, aumente sua altura", LocalParser.tokenize("miku aumente sua altura")), "pt")
	assert_eq(LocalParser.detect_language("Miku, look here", LocalParser.tokenize("miku look here")), "en")
	assert_eq(LocalParser.detect_language("Miku!", LocalParser.tokenize("miku")), "")
