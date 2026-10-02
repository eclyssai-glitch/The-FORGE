extends Node
## DEV ONLY — Loop 5 r2: CPU per frame of MIKU (body: AnimationTree + manual motor) and of the whole
## Miku.tick with 0, 1, 2 and 6 puppet hands, legacy vs native body, headless (no render).
## godot --headless --path . res://tools/research/native_character/r2_bench.tscn
## Prints `R2BENCH backend hands body_us tree_us motor_us tick_us` (medians of RUNS runs of FRAMES frames).

const DT := 1.0 / 30.0
const FRAMES := 450
const RUNS := 5


func _ready() -> void:
	# Backends interleaved run by run (the machine's load drifts); medians of RUNS runs.
	for n in [0, 1, 2, 6]:
		var res := {}
		for backend: StringName in [MikuBody.LEGACY, MikuBody.NATIVE]:
			res[backend] = [[], [], [], []]
		for run in RUNS:
			for backend: StringName in [MikuBody.LEGACY, MikuBody.NATIVE]:
				var r := await _run(backend, n)
				for k in 4:
					res[backend][k].append(r[k])
		for backend: StringName in [MikuBody.LEGACY, MikuBody.NATIVE]:
			var a: Array = res[backend]
			print("R2BENCH %s hands=%d body_us=%.1f tree_us=%.1f motor_us=%.1f tick_us=%.1f" % [backend, n,
				_median(a[0]), _median(a[1]), _median(a[3]), _median(a[2])])
	get_tree().quit()


func _run(backend: StringName, n: int) -> Array:
	MikuBody.override_backend = backend
	var holder := Node3D.new()
	add_child(holder)
	var m := Miku.new()
	holder.add_child(m)
	m.set_process(false)
	MikuBody.override_backend = &""
	for i in 10:
		m.tick(DT)
	if n > 0:
		m.perform(&"SUMMON_HANDS" if n > 1 else &"SUMMON_HAND", {"count": n})
		for i in 150:
			m.tick(DT)
	var b := 0
	var tr := 0
	var tk := 0
	var mo := 0
	for i in FRAMES:
		# Keep the summoned hands out (no idle release during the measure).
		m.set(&"_hand_idle", 0.0)
		var t0 := Time.get_ticks_usec()
		m.tick(DT)
		tk += Time.get_ticks_usec() - t0
		b += m.body.tree_us + m.body.motor_us
		tr += m.body.tree_us
		mo += m.body.motor_us
	var hands := m.hands.active_count()
	holder.free()
	await get_tree().process_frame
	if hands != n:
		push_warning("bench: %d hands active, wanted %d" % [hands, n])
	return [float(b) / FRAMES, float(tr) / FRAMES, float(tk) / FRAMES, float(mo) / FRAMES]


static func _median(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2]
