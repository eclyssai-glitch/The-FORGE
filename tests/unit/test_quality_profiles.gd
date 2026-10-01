extends GutTest
## Quality presets are complete, ordered by cost, and auto-detection is sane.

const KEYS := ["level", "name", "render_scale", "scaling_mode", "msaa", "fxaa", "ssao", "ssil",
	"glow", "volumetric_fog", "shadow_size", "shadows", "shadow_splits", "shadow_filter", "particles"]


func test_every_level_has_complete_profile() -> void:
	for level in QualityProfiles.Level.values():
		var p := QualityProfiles.get_profile(level)
		for k in KEYS:
			assert_true(p.has(k), "%s missing %s" % [QualityProfiles.LEVEL_NAMES[level], k])
		assert_eq(p["level"], level)


func test_cost_is_monotonic() -> void:
	var prev := {}
	for level in QualityProfiles.Level.values():
		var p := QualityProfiles.get_profile(level)
		if not prev.is_empty():
			assert_true(p["render_scale"] >= prev["render_scale"])
			assert_true(p["shadow_size"] >= prev["shadow_size"])
			assert_true(p["particles"] >= prev["particles"])
			assert_true(p["shadow_splits"] >= prev["shadow_splits"])
			assert_true(p["shadow_filter"] >= prev["shadow_filter"])
		prev = p


func test_detect_by_adapter() -> void:
	assert_eq(QualityProfiles.detect(RenderingDevice.DEVICE_TYPE_DISCRETE_GPU), QualityProfiles.Level.HIGH)
	assert_eq(QualityProfiles.detect(RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU), QualityProfiles.Level.MEDIUM)
	assert_eq(QualityProfiles.detect(RenderingDevice.DEVICE_TYPE_CPU), QualityProfiles.Level.LOW)


func test_step_down_floors_at_low() -> void:
	assert_eq(QualityProfiles.step_down(QualityProfiles.Level.HIGH), QualityProfiles.Level.MEDIUM)
	assert_eq(QualityProfiles.step_down(QualityProfiles.Level.LOW), QualityProfiles.Level.LOW)


func test_shadow_splits_are_valid_cascade_counts() -> void:
	# Loop 4 r1: every level uses 4 cascades (2 cascades in a 2048 atlas drew stair-stepped
	# shadows across MIKU's torso and gown at LOW).
	for level in QualityProfiles.Level.values():
		assert_eq(QualityProfiles.get_profile(level)["shadow_splits"], 4, "%s: 4 cascades" % QualityProfiles.LEVEL_NAMES[level])
		assert_has([1, 2, 4], QualityProfiles.get_profile(level)["shadow_splits"])


func test_directional_shadows_are_dense_and_soft() -> void:
	# No level goes below a 4096 directional atlas or below soft PCF (never hard/very-low taps).
	for level in QualityProfiles.Level.values():
		var p := QualityProfiles.get_profile(level)
		assert_true(int(p["shadow_size"]) >= 4096, "%s atlas" % p["name"])
		assert_true(int(p["shadow_filter"]) >= RenderingServer.SHADOW_QUALITY_SOFT_LOW, "%s filter" % p["name"])
		assert_true(int(p["shadow_filter"]) < RenderingServer.SHADOW_QUALITY_MAX)
	assert_eq(QualityProfiles.get_profile(QualityProfiles.Level.HIGH)["shadow_filter"], RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
