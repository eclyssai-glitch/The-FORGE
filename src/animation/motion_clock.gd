class_name MotionClock
extends RefCounted
## Single clock for real-time motion (camera transitions, ambient drift). Owner: animator.
## Normally wall-clock time (ADR-011: a frame's delta is capped at 8/60 s, so on a slow renderer
## a delta-driven clock would run slower than real time). Under the Movie Maker
## (`--write-movie`, fixed delta) wall-clock time does not follow the recorded time — a frame takes
## ~0.4 s to render and stands for 1/fps s — so there the clock is the accumulated game time of the
## process frames. Simulation progress never uses this clock (it is `Simulation.time`).

static var _last_frame: int = 0
static var _game_time: float = 0.0


## Seconds of motion time: wall clock, or accumulated frame time while writing a movie.
static func now() -> float:
	if Engine.get_write_movie_path() == "":
		return Time.get_ticks_msec() * 0.001
	var frame := Engine.get_process_frames()
	if frame != _last_frame:
		_game_time = accumulate(_game_time, _last_frame, frame, _frame_delta())
		_last_frame = frame
	return _game_time


## Pure accumulation step: game time after moving from process frame `last_frame` to `frame`,
## each frame lasting `delta` (fixed under the Movie Maker). Repeated calls within one frame add
## nothing; frames in which nobody asked still count; the clock never goes back.
static func accumulate(game_time: float, last_frame: int, frame: int, delta: float) -> float:
	if frame <= last_frame or delta <= 0.0:
		return game_time
	return game_time + float(frame - last_frame) * delta


static func _frame_delta() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return 0.0
	return tree.root.get_process_delta_time()
