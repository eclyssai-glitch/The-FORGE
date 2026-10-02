extends SceneTree
## DEV ONLY — Loop 5 r2: CPU per frame of MIKU (body: AnimationTree + manual motor) and of the whole
## Miku.tick with 0, 1, 2 and 6 puppet hands, legacy vs native body, headless (no render).
## godot --headless --path . -s res://tools/research/native_character/r2_bench.gd
## Prints `R2BENCH backend hands body_us tree_us tick_us` (medians of 3 runs of 300 frames).

const DT := 1.0 / 30.0
const FRAMES := 300


func _initialize() -> void:
	for backend: StringName in [MikuBody.LEGACY, MikuBody.NATIVE]:
		for n in [0, 1, 2, 6]:
			var body := []
			var tree := []
			var tick := []
			for run in 3:
				var r := await _run(backend, n)
				body.append(r[0])
				tree.append(r[1])
				tick.append(r[2])
			print("R2BENCH %s hands=%d body_us=%.1f tree_us=%.1f tick_us=%.1f" % [backend, n, _median(body),
				_median(tree), _median(tick)])
	quit()


func _run(backend: StringName, n: int) -> Array:
	MikuBody.override_backend = backend
	var holder := Node3D.new()
	root.add_child(holder)
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
	for i in FRAMES:
		var t0 := Time.get_ticks_usec()
		m.tick(DT)
		tk += Time.get_ticks_usec() - t0
		b += m.body.tree_us + m.body.motor_us
		tr += m.body.tree_us
	var hands := m.hands.active_count()
	holder.free()
	await process_frame
	if hands != n:
		push_warning("bench: %d hands active, wanted %d" % [hands, n])
	return [float(b) / FRAMES, float(tr) / FRAMES, float(tk) / FRAMES]


static func _median(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2]
