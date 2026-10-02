extends Node3D
## SPIKE demo — 12 s scripted beat on the native stack (record with Movie Maker):
##   0.0 calm, looks at the work orb · 1.4 notices the camera (user) · 2.3 summons: right arm reaches
##   (anticipation), the thread grows from her index, then the puppet hand arrives with mass · 3.4 focus,
##   conducts the hand around the orb · 6.0 the orb fails · 6.15 composure lost: frustrated, gaze locks,
##   left-arm flick (one-shot) summons two more hands, aggressive fast control, threads taut · 8.6 the
##   orb holds: recover (deep exhale, look at her own hand), extra hands withdraw · 10.4 calm, looks at
##   the user again.
## User args (after --): --measure (no movie; prints frame timings), --strip=modifiers|all (disables the
## native layers to measure their share), --hands=N (extra hands for the cost test), --seconds=S.

const DT := 1.0 / 30.0
const ORB := Vector3(-0.95, 1.3, 0.95)
const CAMERA_POS := Vector3(0.5, 1.7, 4.5)
const CAMERA_LOOK := Vector3(-0.45, 1.42, 0.45)
const FOLLOW_GAIN := 2.0  ## puppet amplification of MIKU's fingertip motion
const FOLLOW_MAX := 0.22  ## m
## close-up inset on the head (gaze chain evidence): offset from the head, in world space
const INSET_OFFSET := Vector3(0.12, 0.04, 0.95)

var miku: NCMiku
var hands: Array[NCPuppetHand] = []
var threads: Array[NCThread] = []
var orb: MeshInstance3D
var orb_mat: StandardMaterial3D
var cam: Camera3D
var inset_cam: Camera3D
var head_att: BoneAttachment3D
var hud: Label
var t := 0.0
var frame := 0
var seconds := 12.0
var measure := false
var strip := ""
var extra_hands := 0
var _frame_us: Array[int] = []
var _last_us := 0
var _tree_us_acc := 0
var _mod_us_acc := 0
var _rig := 0.0
var _tip_ref := Vector3.ZERO
var _tip_ref_l := Vector3.ZERO
var _orb_fail := 0.0
var _orb_spring := NCSpring.new(2.0, 0.4, 0.0, Vector3.ONE)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--measure":
			measure = true
		elif a.begins_with("--strip="):
			strip = a.get_slice("=", 1)
		elif a.begins_with("--hands="):
			extra_hands = int(a.get_slice("=", 1))
		elif a.begins_with("--seconds="):
			seconds = float(a.get_slice("=", 1))
	_build_world()
	miku = NCMiku.new()
	add_child(miku)
	for i in range(3 + extra_hands):
		var h := NCPuppetHand.new(ORB + Vector3(0.3, 0.8, 0.0))
		add_child(h)
		hands.append(h)
		var th := NCThread.new()
		add_child(th)
		th.layers = 2  # not seen by the head close-up camera (it sits in front of her face)
		threads.append(th)
	_build_hud()
	head_att = BoneAttachment3D.new()
	miku.sk.add_child(head_att)
	head_att.bone_name = "head"
	if strip != "":
		_apply_strip.call_deferred()
	_last_us = Time.get_ticks_usec()


func _apply_strip() -> void:
	var sks: Array[Skeleton3D] = [miku.sk]
	for h in hands:
		sks.append(h.sk)
	for s in sks:
		for c in s.get_children():
			if c is SkeletonModifier3D:
				(c as SkeletonModifier3D).active = false
	if strip == "all":
		miku.tree.active = false
		for h in hands:
			h.tree.active = false


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.36, 0.42)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-38), deg_to_rad(25), 0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.5, 2.2, -1.2)
	rim.light_color = Color(0.75, 0.82, 1.0)
	rim.light_energy = 2.0
	rim.omni_range = 5.0
	add_child(rim)
	var floor_mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 2.2
	disc.bottom_radius = 2.2
	disc.height = 0.02
	floor_mi.mesh = disc
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.09, 0.09, 0.11)
	fm.roughness = 0.9
	floor_mi.material_override = fm
	floor_mi.position = Vector3(-0.3, 0.05, 0.3)
	add_child(floor_mi)
	orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	orb.mesh = sm
	orb_mat = StandardMaterial3D.new()
	orb_mat.albedo_color = Color(0.2, 0.22, 0.28)
	orb_mat.emission_enabled = true
	orb_mat.emission = Color(0.55, 0.7, 1.0)
	orb_mat.emission_energy_multiplier = 0.8
	orb.material_override = orb_mat
	orb.position = ORB
	add_child(orb)
	cam = Camera3D.new()
	cam.fov = 46.0
	add_child(cam)
	cam.position = CAMERA_POS
	cam.look_at(CAMERA_LOOK)
	cam.current = true


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var frame_box := SubViewportContainer.new()
	var vs := get_viewport().get_visible_rect().size
	frame_box.position = Vector2(vs.x - 300 - 14, vs.y - 300 - 34)
	frame_box.size = Vector2(300, 300)
	frame_box.stretch = true
	layer.add_child(frame_box)
	var vp := SubViewport.new()
	vp.size = Vector2i(300, 300)
	frame_box.add_child(vp)
	inset_cam = Camera3D.new()
	inset_cam.fov = 26.0
	inset_cam.cull_mask = 1
	vp.add_child(inset_cam)
	var cap := Label.new()
	cap.text = "head close-up (same world)"
	cap.position = Vector2(vs.x - 300 - 14, vs.y - 30)
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", Color(0.6, 0.6, 0.62))
	layer.add_child(cap)
	hud = Label.new()
	hud.position = Vector2(18, 14)
	hud.add_theme_font_size_override("font_size", 15)
	hud.add_theme_color_override("font_color", Color(0.85, 0.83, 0.79))
	layer.add_child(hud)


func _phase(at: float) -> bool:
	return t >= at and t - DT < at


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if frame > 0:
		_frame_us.append(now - _last_us)
	_last_us = now
	_direct()
	miku.step(DT)
	var hp := head_att.global_position + Vector3(0, 0.07, 0)
	inset_cam.global_position = hp + INSET_OFFSET
	inset_cam.look_at(hp)
	_drive_hands()
	_update_orb()
	_tree_us_acc += miku.tree_us
	_mod_us_acc += miku.modifiers_us
	_update_hud()
	t += DT
	frame += 1
	if t >= seconds:
		_finish()


## The "mind + director" of the spike: a fixed script of intentions. In the product this is MikuMind
## + the ANIMATION DIRECTOR choosing vocabulary actions; here it only writes director inputs.
func _direct() -> void:
	var user := cam.global_position
	var h1 := hands[0]
	# mood
	if _phase(3.4):
		miku.travel(&"focus")
	if _phase(6.15):
		miku.travel(&"frustrated")
	if _phase(8.6):
		miku.travel(&"recover")
	if _phase(10.4):
		miku.travel(&"calm")
	if _phase(6.35):
		miku.fire_gesture()
	# composure: lost fast, regained slowly
	var rig_goal := 0.0
	if t >= 6.1 and t < 8.6:
		rig_goal = 1.0
	elif t >= 8.6 and t < 10.4:
		rig_goal = 0.25
	_rig = move_toward(_rig, rig_goal, DT * (6.0 if rig_goal > _rig else 0.45))
	miku.rigidity = _rig
	# root motion of the floating figure: a slow float; a recoil when the work fails; a lean in
	var bob := Vector3(0, 0.012 * sin(t * TAU * miku.breath_rate), 0)
	if t >= 6.0 and t < 6.35:
		miku.body_offset_goal = Vector3(0, 0.03, -0.09)
	elif t >= 6.35 and t < 8.6:
		miku.body_offset_goal = Vector3(-0.04, 0.0, 0.04) + bob * 0.3
	else:
		miku.body_offset_goal = bob
	# breath
	match miku.mood:
		&"calm":
			miku.breath_depth = 1.0
			miku.breath_rate = 0.22
		&"focus":
			miku.breath_depth = 0.6
			miku.breath_rate = 0.3
		&"frustrated":
			miku.breath_depth = 0.25
			miku.breath_rate = 0.65
		&"recover":
			miku.breath_depth = 1.6
			miku.breath_rate = 0.16
	# gaze
	if t < 1.4:
		miku.gaze_goal = ORB + Vector3(0, 0.05, 0)
	elif t < 2.6:
		miku.gaze_goal = user
	elif t < 6.0:
		miku.gaze_goal = h1.global_position.lerp(ORB, 0.5) if t > 3.0 else ORB
	elif t < 8.6:
		miku.gaze_goal = ORB  # locked
	elif t < 9.7:
		miku.gaze_goal = miku.tip_position_l() + Vector3(0, -0.05, 0.1)  # looks at her own hand
	elif t < 11.0:
		miku.gaze_goal = user
	else:
		miku.gaze_goal = ORB
	# right arm: summon / conduct / aggressive control / release
	var rest_reach := Vector3(-0.29, 1.11, 0.25)
	var conduct := Vector3(-0.38, 1.47, 0.33)
	if t < 2.3:
		miku.reach_weight = 0.0
		miku.reach_goal = rest_reach
	elif t < 3.4:
		miku.reach_weight = 1.0
		miku.reach_goal = conduct
	elif t < 6.0:
		var a := (t - 3.4) * 1.4
		miku.reach_goal = conduct + Vector3(cos(a) * 0.06, sin(a * 1.3) * 0.05, sin(a) * 0.05)
	elif t < 8.6:
		var k := int((t - 6.0) / 0.42)
		var jerk := [Vector3(0.05, 0.06, 0.04), Vector3(-0.07, -0.03, 0.08), Vector3(0.02, 0.09, -0.02),
				Vector3(-0.04, -0.06, 0.06)]
		miku.reach_goal = conduct + Vector3(jerk[k % 4]) * 1.3
	elif t < 10.4:
		miku.reach_weight = 0.35
		miku.reach_goal = conduct + Vector3(0.05, -0.2, -0.05)
	else:
		miku.reach_weight = 0.0
	miku.aim_node = h1
	miku.aim_weight = 1.0 if (t >= 2.5 and t < 8.6) else 0.0
	if _phase(3.0):
		_tip_ref = miku.tip_position()
	if _phase(6.3):
		_tip_ref_l = miku.tip_position_l()


func _drive_hands() -> void:
	var tip := miku.tip_position()
	var tip_l := miku.tip_position_l()
	var h1 := hands[0]
	# hand 1: thread first (2.4), the hand answers after (2.75) — never the inverse
	threads[0].presence = move_toward(threads[0].presence, 1.0 if (t >= 2.4 and t < 10.6) else 0.0, DT * 2.2)
	h1.presence_goal = 1.0 if (t >= 2.75 and t < 11.0) else 0.0
	var follow := ((tip - _tip_ref) * FOLLOW_GAIN).limit_length(FOLLOW_MAX) if t >= 3.0 else Vector3.ZERO
	h1.goal = ORB + Vector3(0.05, 0.5, 0.1) + follow
	h1.facing_goal = (ORB - h1.global_position).normalized().slide(Vector3.UP).normalized() if t > 2.0 else Vector3.BACK
	h1.grip_goal = 0.0
	if t >= 3.4 and t < 6.0:
		h1.goal = ORB + Vector3(0.0, 0.4, 0.08) + follow
		h1.grip_goal = 0.35 + 0.35 * sin((t - 3.4) * 2.2)
	elif t >= 6.0 and t < 8.6:
		h1.goal = ORB + Vector3(0.05, 0.32, 0.05) + follow
		h1.grip_goal = 1.0
	elif t >= 8.6:
		h1.goal = ORB + Vector3(0.1, 0.6, 0.0) + follow * 0.5
		h1.grip_goal = -0.6
	h1.force = _rig
	# hands 2..N: summoned by the left-hand flick, aggressive, withdrawn on recovery
	var follow_l := ((tip_l - _tip_ref_l) * FOLLOW_GAIN).limit_length(FOLLOW_MAX) if t >= 6.3 else Vector3.ZERO
	for i in range(1, hands.size()):
		var h := hands[i]
		# extra hands spread around the orb, in front of it (their threads pass in front of her)
		var spots := [Vector3(-0.15, -0.25, 0.6), Vector3(0.45, 0.2, 0.55), Vector3(-0.55, 0.3, 0.2)]
		var around: Vector3 = spots[(i - 1) % spots.size()] + Vector3(0, 0, -0.1 * float((i - 1) / spots.size()))
		var active := t >= 6.45 + 0.12 * float(i - 1) and t < 8.9
		threads[i].presence = move_toward(threads[i].presence, 1.0 if t >= 6.38 + 0.12 * float(i - 1) and t < 9.2 else 0.0, DT * 5.0)
		h.presence_goal = 1.0 if active else 0.0
		h.goal = ORB + around * (1.0 if t < 7.6 else 0.8) + follow_l
		if t >= 8.9:
			h.goal = ORB + around * 1.3 + Vector3(0, 0.5, -0.4)
		h.facing_goal = (ORB - h.global_position).normalized()
		h.grip_goal = 1.0 if t >= 7.0 and t < 8.6 else 0.2
		h.force = 1.0
	for i in range(hands.size()):
		hands[i].step(DT)
		var th := threads[i]
		var from := tip if i == 0 else tip_l
		th.tension = clampf(maxf(hands[i].pull(), _rig * 0.85), 0.0, 1.0)
		th.draw(from, hands[i].anchor(), cam.global_position)


func _update_orb() -> void:
	if _phase(6.0):
		_orb_fail = 1.0
	if t >= 8.4:
		_orb_fail = move_toward(_orb_fail, 0.0, DT * 0.8)
	var squeeze := 0.0
	for i in range(hands.size()):
		squeeze += maxf(hands[i].grip_goal, 0.0) * hands[i].presence * 0.06
	var jitter := Vector3.ZERO
	if _orb_fail > 0.5:
		jitter = Vector3(sin(t * 37.0), sin(t * 29.0 + 1.0), sin(t * 41.0 + 2.0)) * 0.12 * _orb_fail
	var s := _orb_spring.step(Vector3.ONE * (1.0 - squeeze) + jitter, DT)
	orb.scale = s
	orb.rotation.y += DT * 0.3
	orb_mat.emission = Color(0.55, 0.7, 1.0).lerp(Color(1.0, 0.42, 0.18), _orb_fail)
	orb_mat.emission_energy_multiplier = 0.8 + 1.6 * _orb_fail


func _update_hud() -> void:
	var fus: int = _frame_us.back() if not _frame_us.is_empty() else 0
	hud.text = "NATIVE CHARACTER SPIKE  Godot %s\nt %.2f s   state %s   rigidity %.2f\nAnimationTree %d us   modifier stack %d us   frame %.1f ms" % [
			Engine.get_version_info()["string"], t, miku.playback.get_current_node(), _rig,
			miku.tree_us, miku.modifiers_us, float(fus) / 1000.0]


func _finish() -> void:
	set_process(false)
	var arr := _frame_us.duplicate()
	arr.sort()
	var sum := 0
	for v in arr:
		sum += v
	var n := maxi(arr.size(), 1)
	print("MEASURE strip=%s extra_hands=%d frames=%d avg_frame_ms=%.2f p50=%.2f p95=%.2f miku_tree_avg_us=%.0f miku_modifiers_avg_us=%.0f renderer=%s" % [
			strip if strip != "" else "none", extra_hands, frame, float(sum) / n / 1000.0, float(arr[n / 2]) / 1000.0,
			float(arr[int(n * 0.95)]) / 1000.0, float(_tree_us_acc) / frame, float(_mod_us_acc) / frame,
			RenderingServer.get_video_adapter_name()])
	get_tree().quit()
