extends Node3D
## DEV ONLY (tools/, outside the export) — Loop 5 r2 native migration: the SAME sequence of MIKU,
## the SAME fixed camera, with either body backend, for the OLD vs NEW comparisons of each
## migration step. The scene ticks Miku itself with a fixed 1/30 s (deterministic under the Movie
## Maker) and drives her through the roteiro's own `living.*` events:
##   0 s calm (her agenda only) · 6 s work order -> FOCUSED · 7 s first stage (hands, threads,
##   matter) · 15 s the crack (failure 1) -> FRUSTRATED · 22 s the collapse (failure 2) -> ANGRY ·
##   (16 s her frustration is forced if the crack alone did not do it) ·
##   26 s the tear-down · 31 s it holds -> RECOVERING · until 42 s back to calm.
## User args (after --): --body=legacy|native (MikuBody), --seconds=S (default 42), --view=torso|
## full, --inspect=<dir> --inspect-every=<s> (dev inspector JSON dumps, no PNG), --hud=on|off,
## --bench (no movie: prints CPU per frame of MIKU's body and of the whole tick).

const DT := 1.0 / 30.0
const WORLD := &"world_calyx"
const CUES: Array = [
	[6.0, "living.work_order", {}],
	[7.0, "living.work_step", {"step": 0, "attempt": 1, "hands": 2}],
	[15.0, "living.work_failed", {"attempt": 1}],
	[16.0, "mood", {"to": &"frustrated"}],
	[22.0, "living.work_failed", {"attempt": 2}],
	[26.0, "living.work_dismantled", {"hands": 6}],
	[31.0, "living.work_recovered", {}],
]

var miku: Miku
var cam: Camera3D
var hud: Label
var t := 0.0
var frame := 0
var seconds := 42.0
var view := "torso"
var bench := false
var _cue := 0
var _body_us: Array[int] = []
var _tree_us: Array[int] = []
var _tick_us: Array[int] = []
var _moods: Array[String] = []


func _ready() -> void:
	var inspect := ""
	var every := ""
	var hud_on := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			seconds = float(a.get_slice("=", 1))
		elif a.begins_with("--view="):
			view = a.get_slice("=", 1)
		elif a.begins_with("--inspect="):
			inspect = a.get_slice("=", 1)
		elif a.begins_with("--inspect-every="):
			every = a.get_slice("=", 1)
		elif a == "--hud=off":
			hud_on = false
		elif a == "--bench":
			bench = true
	var env := WorldEnvironment.new()
	var sky := GenesisEnvironment.make_sky_material()
	env.environment = GenesisEnvironment.make_environment(sky)
	add_child(env)
	if not Quality.profile.is_empty():
		GenesisEnvironment.apply_quality(env.environment, sky, Quality.profile)
	GenesisEnvironment.apply_mode(env.environment, sky, Session.mode)
	add_child(LivingLightRig.new())
	miku = Miku.new()
	add_child(miku)
	miku.set_process(false)
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
	miku.tick(DT)
	_frame_camera()
	if hud_on:
		hud = Label.new()
		hud.add_theme_font_size_override(&"font_size", 15)
		hud.position = Vector2(14, get_viewport().get_visible_rect().size.y - 34.0)
		var layer := CanvasLayer.new()
		layer.add_child(hud)
		add_child(layer)
	if inspect != "":
		var script := load("res://tools/inspector/dev_inspector.gd") as Script
		if script != null:
			var ins: Node = script.new()
			ins.call(&"configure", {"inspect": inspect, "inspect-every": every, "inspect-png": "off"})
			add_child(ins)
	print("[r2] start body=%s view=%s seconds=%.1f" % [miku.body.backend(), view, seconds])


## Fixed camera: 3/4 from her front-left, framing her from the hips (torso) or whole (full).
func _frame_camera() -> void:
	var b := miku.body.body_basis()
	var head := miku.body.head_position()
	var chest := miku.body.chest_position()
	var span := head.distance_to(chest)
	var target := chest.lerp(head, 0.1) - b.y * span * (0.35 if view == "torso" else 2.6)
	var dist := span * (7.6 if view == "torso" else 15.0)
	var dir := (b.z * 0.86 + b.x * 0.42 + b.y * 0.12).normalized()
	cam.global_position = target + dir * dist
	cam.look_at(target, Vector3.UP)


func _process(_delta: float) -> void:
	while _cue < CUES.size() and t >= float(CUES[_cue][0]):
		var c: Array = CUES[_cue]
		var p: Dictionary = (c[2] as Dictionary).duplicate()
		p["world"] = WORLD
		if c[1] == "mood":
			# The crack alone does not always frustrate a patient MIKU: the sequence asks for it.
			miku.mind.force_mood(p["to"])
		else:
			miku.call(&"_on_sim_event", SimEvent.new(&"r2", t, StringName(c[1]), String(c[1]), "", &"miku", p))
		print("[r2] cue %.1f %s mood=%s" % [t, c[1], miku.mood()])
		_cue += 1
	var t0 := Time.get_ticks_usec()
	miku.tick(DT)
	var tick_us := Time.get_ticks_usec() - t0
	if frame > 30:
		_tick_us.append(tick_us)
		_body_us.append(miku.body.tree_us + miku.body.motor_us)
		_tree_us.append(miku.body.tree_us)
	var m := String(miku.mood())
	if _moods.is_empty() or _moods[-1].get_slice("@", 0) != m:
		_moods.append("%s@%.2f" % [m, t])
	if hud != null:
		var s := miku.inspect_state()
		var bd: Dictionary = s["body"]
		var tr := ""
		if bd.has("tree"):
			var td: Dictionary = bd["tree"]
			tr = "  tree %s%s tension %.2f" % [td["state"], (" <- " + String(td["fading_from"])) if td["fading_from"] != "" else "",
				td["tension"]]
		hud.text = "%s   t %5.2f s   mood %s   composure %.2f%s" % [String(bd["backend"]).to_upper(), t, m,
			s["composure"], tr]
	t += DT
	frame += 1
	if t >= seconds:
		_report()
		get_tree().quit()


func _report() -> void:
	print("[r2] moods ", " ".join(_moods))
	print("[r2] cpu body=%s tick_us mean %.1f p95 %d | body(tree+motor)_us mean %.1f p95 %d | tree_us mean %.1f | hands %d" % [
		miku.body.backend(), _mean(_tick_us), _p95(_tick_us), _mean(_body_us), _p95(_body_us), _mean(_tree_us),
		miku.hands.built])
	print("[r2] done frames=%d" % frame)


static func _mean(a: Array[int]) -> float:
	if a.is_empty():
		return 0.0
	var s := 0
	for x in a:
		s += x
	return float(s) / float(a.size())


static func _p95(a: Array[int]) -> int:
	if a.is_empty():
		return 0
	var b := a.duplicate()
	b.sort()
	return b[int(b.size() * 0.95)]
