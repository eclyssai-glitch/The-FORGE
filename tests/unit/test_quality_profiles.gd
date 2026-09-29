extends GutTest
## Quality presets are complete, ordered by cost, and auto-detection is sane.

const KEYS := ["level", "name", "render_scale", "scaling_mode", "msaa", "fxaa", "ssao", "ssil",
	"glow", "volumetric_fog", "shadow_size", "shadows", "particles"]


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
		prev = p


func test_detect_by_adapter() -> void:
	assert_eq(QualityProfiles.detect(RenderingDevice.DEVICE_TYPE_DISCRETE_GPU), QualityProfiles.Level.HIGH)
	assert_eq(QualityProfiles.detect(RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU), QualityProfiles.Level.MEDIUM)
	assert_eq(QualityProfiles.detect(RenderingDevice.DEVICE_TYPE_CPU), QualityProfiles.Level.LOW)


func test_step_down_floors_at_low() -> void:
	assert_eq(QualityProfiles.step_down(QualityProfiles.Level.HIGH), QualityProfiles.Level.MEDIUM)
	assert_eq(QualityProfiles.step_down(QualityProfiles.Level.LOW), QualityProfiles.Level.LOW)
