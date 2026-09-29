extends GutTest
## Motion: progress/easing helpers are bounded, anchored on event timestamps and deterministic.


func test_progress_before_event_or_missing_is_zero() -> void:
	assert_eq(Motion.progress(-1.0, 10.0, 2.0), 0.0, "event not happened")
	assert_eq(Motion.progress(5.0, 4.0, 2.0), 0.0, "before the event")
	assert_eq(Motion.progress(5.0, 5.0, 2.0), 0.0)


func test_progress_is_linear_and_clamped() -> void:
	assert_almost_eq(Motion.progress(5.0, 6.0, 2.0), 0.5, 1e-6)
	assert_eq(Motion.progress(5.0, 99.0, 2.0), 1.0)
	assert_eq(Motion.progress(5.0, 5.1, 0.0), 1.0, "zero duration jumps")


func test_eased_endpoints_and_monotonic() -> void:
	assert_almost_eq(Motion.eased(0.0), 0.0, 1e-6)
	assert_almost_eq(Motion.eased(1.0), 1.0, 1e-6)
	assert_almost_eq(Motion.eased(0.5), 0.5, 1e-4, "sine in-out is symmetric")
	assert_almost_eq(Motion.eased(-3.0), 0.0, 1e-6, "clamped below")
	assert_almost_eq(Motion.eased(7.0), 1.0, 1e-6, "clamped above")
	var prev := -1.0
	for i in 101:
		var v := Motion.eased(i / 100.0, Tween.TRANS_CUBIC, Tween.EASE_OUT)
		assert_true(v >= prev - 1e-6)
		prev = v


func test_decay_starts_at_one_and_ends_at_zero() -> void:
	assert_eq(Motion.decay(-1.0, 3.0, 1.0), 0.0)
	assert_eq(Motion.decay(2.0, 1.9, 1.0), 0.0)
	assert_almost_eq(Motion.decay(2.0, 2.0, 1.0), 1.0, 1e-6)
	assert_almost_eq(Motion.decay(2.0, 3.0, 1.0), 0.0, 1e-6)
	assert_true(Motion.decay(2.0, 2.5, 1.0) < 0.5, "quadratic fall")


func test_window_rises_holds_and_falls() -> void:
	assert_eq(Motion.window(-1.0, 5.0, 1.0, 6.0, 1.0), 0.0)
	assert_eq(Motion.window(2.0, 1.0, 1.0, 6.0, 1.0), 0.0)
	assert_almost_eq(Motion.window(2.0, 3.0, 1.0, 6.0, 1.0), 1.0, 1e-6, "risen")
	assert_almost_eq(Motion.window(2.0, 6.0, 1.0, 6.0, 1.0), 1.0, 1e-6, "held")
	assert_almost_eq(Motion.window(2.0, 7.0, 1.0, 6.0, 1.0), 0.0, 1e-6, "fallen")
	# Continuity at the hold boundary even when the rise is not complete.
	var a := Motion.window(2.0, 2.3, 1.0, 2.3, 1.0)
	var b := Motion.window(2.0, 2.3001, 1.0, 2.3, 1.0)
	assert_almost_eq(a, b, 1e-3)


func test_hash01_is_bounded_and_deterministic() -> void:
	var seen := {}
	for i in 200:
		var h := Motion.hash01(i)
		assert_true(h >= 0.0 and h < 1.0)
		assert_eq(h, Motion.hash01(i))
		seen[snappedf(h, 0.1)] = true
	assert_gt(seen.size(), 6, "spread over the range")
