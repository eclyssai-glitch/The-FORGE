extends GutTest
## MotionClock: wall clock outside the Movie Maker; the accumulation used while recording is pure.


func test_now_is_wall_clock_when_not_recording() -> void:
	assert_eq(Engine.get_write_movie_path(), "", "tests never run under the Movie Maker")
	var before := Time.get_ticks_msec() * 0.001
	var now := MotionClock.now()
	var after := Time.get_ticks_msec() * 0.001
	assert_between(now, before, after, "ADR-011: wall clock in normal play")


func test_accumulate_adds_one_delta_per_frame() -> void:
	var dt := 1.0 / 30.0
	var t := 0.0
	var last := 0
	for frame in range(1, 31):
		t = MotionClock.accumulate(t, last, frame, dt)
		last = frame
	assert_almost_eq(t, 1.0, 1e-5, "30 frames at 30 fps = 1 s of motion time")


func test_accumulate_same_frame_adds_nothing() -> void:
	var t := MotionClock.accumulate(2.0, 10, 10, 1.0 / 30.0)
	assert_eq(t, 2.0, "several callers in the same frame read the same time")


func test_accumulate_counts_skipped_frames() -> void:
	assert_almost_eq(MotionClock.accumulate(1.0, 10, 13, 0.5), 2.5, 1e-6,
			"frames where nobody asked still advance the clock")


func test_accumulate_never_goes_back() -> void:
	assert_eq(MotionClock.accumulate(3.0, 10, 9, 1.0 / 30.0), 3.0)
	assert_eq(MotionClock.accumulate(3.0, 10, 11, 0.0), 3.0)
	assert_eq(MotionClock.accumulate(3.0, 10, 11, -1.0), 3.0)


func test_accumulate_is_independent_of_render_cost() -> void:
	# Movie Maker: 0.4 s of wall time per frame does not matter, only frames x fixed delta.
	var t := 0.0
	for frame in range(1, 91):
		t = MotionClock.accumulate(t, frame - 1, frame, 1.0 / 30.0)
	assert_almost_eq(t, 3.0, 1e-5)
