class_name Miku
extends Node3D
## MIKU, the living character of the prototype (Loop 5, ADR-015/016). Owner: animator.
## Runtime of the character: her mind (MikuMind: mood, composure, attention, task), the agenda of
## micro-behaviours (MicroAgenda), the execution of the actions of the vocabulary as movement
## (ActionScript / WorkPlan beats), and the things she controls — puppet hands (HandPool), intent
## threads (IntentThreads), the work worlds (WorkWorld), the causal particles and the
## configuration artifact. Real-time state driven by MotionClock (deterministic under the Movie
## Maker); never a function of Simulation.time; no seek.
##
## API (interaction system, game-engineer):
##   perform(action, args := {}) -> bool     one of ActionScript.VOCABULARY; args by action:
##       WORK {world, fail: bool}, LOOK_AT_WORLD/POINT/INSPECT/ANGRY/SATISFIED {world},
##       SUMMON_HANDS {count, release}, SUMMON_HAND {release}, EDIT_FILE {patch: Dictionary (only
##       echoed back in file_committed), keep}, DISCARD {rejected}.
##     LOOK_AT_USER / ACKNOWLEDGE play over the running action; while WORK runs, FRUSTRATED / ANGRY /
##     RECOVER do too; WORK on another world switches the work there; anything else is queued.
##   notice_user()           the user called her: reaction by mood (curious, brief, curt, cold)
##   target_world(id)        the user pointed at a world: she looks, acknowledges, works on it
##   apply_config(config)    validated configuration {"identity", "behaviour", "appearance"}
##                           (call it after file_committed); she reacts to the change in herself
##   world_ids(), mood(), current_action(), is_busy(), story_focus()
## Signals: action_started(action), action_finished(action), mood_changed(state),
##   attention_changed(kind, id), file_committed(args) (EDIT_FILE reached the commit beat).
## Entity `miku` (pick body in MikuBody); worlds are entities `world_a/b/c` (WorkWorld).
## Composition: siblings in groups HandPool.GROUP, IntentThreads.GROUP, WorkWorld.GROUP,
## CausalParticles.GROUP are used when present; anything missing is created as a child.

signal action_started(action: StringName)
signal action_finished(action: StringName)
signal mood_changed(state: StringName)
signal attention_changed(kind: StringName, id: StringName)
signal file_committed(args: Dictionary)

const GROUP := &"living_miku"
const ENTITY := &"miku"
## A hand is "in place" this close to its goal (units).
const ARRIVE_DIST := 0.38
## A hand works the world when this close to its place and pulled.
const WORK_DIST := 0.7
## Hands summoned and left idle are released (with a gesture) after this many seconds.
const HAND_IDLE_RELEASE := 7.0
## Longest frame step (s): a hitch never becomes a jump.
const MAX_DT := 0.1
## Rhythm of the working gestures (s per cycle at tempo 1).
const RHYTHM_PERIOD := 1.9
## Hands mirror her hand's displacement by this gain while working (and `mirror` beats).
const WORK_MIRROR_GAIN := 1.6
## Seconds a camera story focus is held at least (no restless camera).
const FOCUS_HOLD := 2.2

## Posture of each mood (MikuMind.Mood order): lean, lean_side, chest lift, shoulder raise,
## shoulders forward, head tilt, nod. Calm = the dancer's carriage; angry = vertical, square,
## chin down, no tilt.
const MOOD_POSTURE: Array = [
	[0.0, 0.015, 0.2, -0.12, -0.18, 0.065, 0.0],
	[0.08, 0.0, 0.1, 0.0, 0.08, 0.03, 0.07],
	[0.06, 0.0, -0.05, 0.5, 0.25, 0.0, 0.05],
	[0.0, 0.0, 0.06, 0.3, 0.0, 0.0, 0.08],
	[0.02, 0.0, 0.12, -0.2, -0.1, 0.05, 0.08],
]
## Breath of each mood: [rate (Hz), depth].
const MOOD_BREATH: Array = [
	[1.0 / Palette.T_BREATH, 1.0], [1.0 / 4.6, 0.7], [1.0 / 3.0, 0.75], [1.0 / 3.8, 0.22],
	[1.0 / 7.5, 1.6],
]

var params := MikuParams.new()
var mind: MikuMind
var agenda: MicroAgenda
var body: MikuBody
var hands: HandPool
var threads: IntentThreads
var worlds: WorkWorld
var particles: CausalParticles
var artifact: ConfigArtifact
## Current work world (the last one she worked or was pointed to).
var work_world: StringName = LivingLayout.DEFAULT_WORLD

var _main: Dictionary = {}
var _overlay: Dictionary = {}
var _queue: Array[Dictionary] = []
var _clock := 0.0
var _last_now := -1.0
var _phase := 0.0
## Body channels written by beats: [main, overlay] sources.
var _gaze_beat: Array[Dictionary] = [{}, {}]
var _turn_beat: Array[Dictionary] = [{}, {}]
var _breath_beat: Dictionary = {}
var _poses: Dictionary = {}
var _arm_spec: Array[Dictionary] = [{}, {}]
var _wave: Array[Dictionary] = [{}, {}]
var _goal := Gestures.ArmGoal.new()
var _wave_buf := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _pv := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _noise := RandomNumberGenerator.new()
var _saccade := Vector3.ZERO
var _saccade_at := 0.0
var _weight_side := 0.6
var _hand_idle := 0.0
var _applied := false
var _appearance_changed := false
var _last_focus_kind: StringName = &""
var _focus := {"kind": &"miku", "points": PackedVector3Array(), "since": 0.0}
var _focus_since := 0.0
var _particle_clock := 0.0
var _energy_rr := 0
var _last_attention := &""
var _bound := false
var _last_mood: MikuMind.Mood = MikuMind.Mood.CALM


func _init() -> void:
	name = "Miku"
	mind = MikuMind.new(params)
	agenda = MicroAgenda.new(5051)
	_noise.seed = 8128
	body = MikuBody.new()
	add_child(body)
	artifact = ConfigArtifact.new()
	add_child(artifact)
	position = LivingLayout.MIKU_POSITION


func _ready() -> void:
	add_to_group(GROUP)
	set_meta(&"audio_anchor", &"miku")
	body.add_to_group(SessionState.entity_group(ENTITY))
	body.set_meta(&"focus_bounds", AABB(Vector3(-1.0, -4.2, -0.8), Vector3(2.0, 6.0, 1.6)))
	_last_now = MotionClock.now()


# ================================================================== API


## Performs an action of the vocabulary. Returns false for an unknown action.
func perform(action: StringName, args := {}) -> bool:
	if not ActionScript.is_action(action):
		push_warning("Miku: unknown action %s" % action)
		return false
	_bind()
	var a := args.duplicate()
	if action in ActionScript.OVERLAY:
		_start_overlay(action, a)
		return true
	var working: bool = not _main.is_empty() and _main["action"] == ActionScript.WORK
	if working and action in [ActionScript.FRUSTRATED, ActionScript.ANGRY, ActionScript.RECOVER]:
		_start_overlay(action, a)
		return true
	if working and action == ActionScript.WORK:
		var w: StringName = a.get("world", work_world)
		if w != StringName(_main["world"]):
			_switch_work(w)
			return true
	if action == ActionScript.DISCARD and not _main.is_empty() and _main["action"] in [ActionScript.EDIT_FILE, ActionScript.GRAB_FILE]:
		_finish_run(_main, 0)
		_main = {}
	if _main.is_empty():
		_start_main(action, a)
	else:
		_queue.append({"action": action, "args": a})
	return true


## The user called her (click on MIKU, "Miku, ..."): she reacts according to her state.
func notice_user() -> Dictionary:
	_bind()
	var r := mind.user_call()
	agenda.interrupt()
	_start_overlay_beats(ActionScript.LOOK_AT_USER, {"reaction": r["reaction"]}, ActionScript.user_reaction(r))
	return r


## The user pointed at a world: she looks at it, acknowledges, and puts her hands to work there.
func target_world(id: StringName) -> bool:
	_bind()
	if worlds == null or not worlds.has_world(id):
		return false
	mind.user_points(id)
	agenda.interrupt()
	_start_overlay_beats(ActionScript.LOOK_AT_WORLD, {"world": id}, ActionScript.world_target_reaction(id))
	var working: bool = not _main.is_empty() and _main["action"] == ActionScript.WORK
	if working:
		if StringName(_main["world"]) != id:
			_switch_work(id)
	else:
		for q in _queue.duplicate():
			if q["action"] == ActionScript.WORK:
				_queue.erase(q)
		var a := {"world": id, "point_first": true}
		if _main.is_empty():
			_start_main(ActionScript.WORK, a)
		else:
			_queue.append({"action": ActionScript.WORK, "args": a})
	return true


## Applies a VALIDATED configuration (sections identity/behaviour/appearance; ADR-016). Returns
## the keys that changed ("section.key"). Personality takes effect in the mind at once; the body
## eases into new appearance values; she reacts to the change in herself.
func apply_config(config: Dictionary) -> PackedStringArray:
	var changed := params.apply(config)
	body.set_appearance(params.appearance)
	_appearance_changed = false
	for k in changed:
		if k.begins_with("appearance."):
			_appearance_changed = true
	_applied = true
	var waiting: bool = not _main.is_empty() and _main["action"] == ActionScript.EDIT_FILE
	if not waiting and not changed.is_empty():
		_start_overlay_beats(&"SELF", {}, ActionScript.self_reaction(_appearance_changed))
	return changed


func world_ids() -> Array[StringName]:
	return LivingLayout.world_ids()


func mood() -> StringName:
	return mind.mood_id()


## Action running on the main channel (&"" when none).
func current_action() -> StringName:
	return _main.get("action", &"")


func is_busy() -> bool:
	return not _main.is_empty() or not _queue.is_empty()


## What the camera should tell now: {"kind": &"miku" | &"puppet" | &"work" | &"wide" |
## &"emotion" | &"user" | &"file", "points": world points to frame, "since": seconds}.
func story_focus() -> Dictionary:
	return _focus


## Advances the character by dt seconds (the node calls it every frame from MotionClock; tests
## call it directly).
func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	_bind()
	_clock += dt
	_phase += dt * mind.tempo() * TAU / RHYTHM_PERIOD
	mind.step(dt)
	_step_run(_main, dt, 0)
	_step_run(_overlay, dt, 1)
	_emit_mood()
	if not _main.is_empty() and _main["done"]:
		_finish_run(_main, 0)
		_main = {}
		if not _queue.is_empty():
			var q: Dictionary = _queue.pop_front()
			_start_main(q["action"], q["args"])
	if not _overlay.is_empty() and _overlay["done"]:
		_finish_run(_overlay, 1)
		_overlay = {}
	_idle_hands(dt)
	agenda.step(dt, mind, _agenda_context())
	_compose_body()
	body.step(dt)
	_drive_hands()
	hands.step(dt)
	_drive_work(dt)
	threads.tremble = mind.rigidity()
	threads.step(dt)
	worlds.step(dt)
	artifact.tempo = mind.tempo()
	artifact.step(dt)
	particles.step(dt)
	_update_focus()
	_emit_attention()


func _process(_delta: float) -> void:
	var now := MotionClock.now()
	if _last_now < 0.0:
		_last_now = now
		return
	var dt := clampf(now - _last_now, 0.0, MAX_DT)
	_last_now = now
	tick(dt)


# ================================================================== composition


## Finds the sibling modules (or builds the missing ones as children).
func _bind() -> void:
	if _bound:
		return
	var tree := get_tree() if is_inside_tree() else null
	if tree != null:
		hands = tree.get_first_node_in_group(HandPool.GROUP) as HandPool
		threads = tree.get_first_node_in_group(IntentThreads.GROUP) as IntentThreads
		worlds = tree.get_first_node_in_group(WorkWorld.GROUP) as WorkWorld
		particles = tree.get_first_node_in_group(CausalParticles.GROUP) as CausalParticles
	if hands == null:
		hands = HandPool.new()
		hands.name = "HandPool"
		add_child(hands)
	if threads == null:
		threads = IntentThreads.new()
		add_child(threads)
	if worlds == null:
		worlds = WorkWorld.new()
		add_child(worlds)
	if particles == null:
		particles = CausalParticles.new()
		add_child(particles)
	threads.miku_tip = body.fingertip
	particles.threads = threads
	_bound = true


# ================================================================== runs


func _new_run(action: StringName, args: Dictionary, beats: Array[Dictionary]) -> Dictionary:
	var sorted := beats.duplicate()
	sorted.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["t"]) < float(y["t"]))
	var world: StringName = args.get("world", work_world)
	if worlds != null and not worlds.has_world(world):
		world = work_world
	return {"action": action, "args": args, "beats": sorted, "next": 0, "t": 0.0, "wait": 0.0,
		"done": false, "hands": [] as Array[PuppetHand], "world": world, "data": {}, "lead": _lead_for(world)}


func _start_main(action: StringName, args: Dictionary) -> void:
	var beats := ActionScript.beats(action, args)
	if action == ActionScript.EDIT_FILE:
		beats = ActionScript.edit_beats(not artifact.is_present(), bool(args.get("keep", false)))
	_main = _new_run(action, args, beats)
	if action == ActionScript.WORK:
		work_world = _main["world"]
		_main["data"]["fail"] = bool(args.get("fail", false))
		mind.begin_task(&"build", work_world)
		if args.get("point_first", false):
			_replace_rest(_main, _point_then_work(work_world))
	elif action == ActionScript.EDIT_FILE or action == ActionScript.GRAB_FILE:
		_applied = false
	_adopt_idle_hands(_main)
	agenda.interrupt()
	action_started.emit(action)


func _start_overlay(action: StringName, args: Dictionary) -> void:
	_start_overlay_beats(action, args, ActionScript.beats(action, args))


func _start_overlay_beats(action: StringName, args: Dictionary, beats: Array[Dictionary]) -> void:
	if not _overlay.is_empty():
		_finish_run(_overlay, 1)
	_overlay = _new_run(action, args, beats)
	_gaze_beat[1] = {}
	_turn_beat[1] = {}
	action_started.emit(action)


func _finish_run(run: Dictionary, src: int) -> void:
	if src == 0:
		if run["action"] == ActionScript.WORK:
			mind.end_task(false)
			for s in worlds.sites.values():
				(s as WorkSite).via = Vector3.INF
		_poses.erase(&"m_stage")
		_turn_beat[0] = {}
		for s in 2:
			if _arm_spec[s].get("src", -1) == 0:
				_arm_spec[s] = {}
	else:
		for s in 2:
			if _arm_spec[s].get("src", -1) == 1:
				_arm_spec[s] = {}
	if run["action"] != &"SELF":
		action_finished.emit(run["action"])


func _step_run(run: Dictionary, dt: float, src: int) -> void:
	if run.is_empty() or run["done"]:
		return
	run["t"] = float(run["t"]) + dt * mind.tempo()
	if src == 0 and run["action"] == ActionScript.WORK:
		_check_failure(run)
		_check_switch(run)
	var beats: Array = run["beats"]
	while int(run["next"]) < beats.size():
		var bt: Dictionary = beats[int(run["next"])]
		if float(bt["t"]) > float(run["t"]):
			break
		if bt["op"] == &"wait":
			if not _wait_ok(run, bt):
				run["wait"] = float(run["wait"]) + dt
				if float(run["wait"]) < float(bt.get("timeout", 5.0)):
					run["t"] = float(bt["t"])
					break
			run["wait"] = 0.0
			run["next"] = int(run["next"]) + 1
			continue
		run["next"] = int(run["next"]) + 1
		_op(run, bt, src)
		if run["done"]:
			return
		beats = run["beats"]
	if int(run["next"]) >= (run["beats"] as Array).size():
		run["done"] = true


## Replaces the beats not yet played by `beats` (times relative to now).
func _replace_rest(run: Dictionary, beats: Array[Dictionary]) -> void:
	var played: Array = (run["beats"] as Array).slice(0, int(run["next"]))
	var add: Array = []
	for x in beats:
		var y: Dictionary = x.duplicate()
		y["t"] = float(x["t"]) + float(run["t"])
		add.append(y)
	add.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["t"]) < float(q["t"]))
	played.append_array(add)
	run["beats"] = played
	run["done"] = false


## Inserts `beats` now and delays the rest by their duration.
func _splice(run: Dictionary, beats: Array[Dictionary]) -> void:
	var dur := 0.0
	for x in beats:
		dur = maxf(dur, float(x["t"]))
	var all: Array = run["beats"]
	var played: Array = all.slice(0, int(run["next"]))
	var rest: Array = all.slice(int(run["next"]))
	var add: Array = []
	for x in beats:
		if x["op"] == &"done":
			continue
		var y: Dictionary = x.duplicate()
		y["t"] = float(x["t"]) + float(run["t"])
		add.append(y)
	add.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["t"]) < float(q["t"]))
	for x in rest:
		(x as Dictionary)["t"] = float(x["t"]) + dur
	played.append_array(add)
	played.append_array(rest)
	run["beats"] = played


func _point_then_work(world: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for x in ActionScript.beats(ActionScript.POINT, {"world": world}):
		if x["op"] != &"done":
			out.append(x)
	out.append(ActionScript.b(1.9, &"next_stage"))
	return out


func _switch_work(id: StringName) -> void:
	_main["data"]["switch_to"] = id


func _check_switch(run: Dictionary) -> void:
	var data: Dictionary = run["data"]
	if not data.has("switch_to"):
		return
	var id: StringName = data["switch_to"]
	data.erase("switch_to")
	data.erase("work")
	data.erase("repair")
	data.erase("dismantle")
	data["fail"] = false
	worlds.site(StringName(run["world"])).via = Vector3.INF
	threads_relax(run, -1)
	run["world"] = id
	run["lead"] = _lead_for(id)
	work_world = id
	mind.begin_task(&"build", id)
	var b: Array[Dictionary] = [ActionScript.b(0.0, &"arm", {"side": &"both", "g": &"rest"})]
	for x in _point_then_work(id):
		var y: Dictionary = x.duplicate()
		y["t"] = float(x["t"]) + 0.6
		b.append(y)
	_replace_rest(run, b)


## Starts the planned failure when the outer layer is half laid (WORK {"fail": true}).
func _check_failure(run: Dictionary) -> void:
	var data: Dictionary = run["data"]
	if not data.get("fail", false) or data.get("fail_started", false):
		return
	var b := worlds.site(StringName(run["world"])).build
	if b.stage == WorldBuild.Stage.LAYERS and b.current_layer() == WorkPlan.FAIL_AT_LAYER \
			and b.layers[WorkPlan.FAIL_AT_LAYER] >= WorkPlan.FAIL_AT_PROGRESS:
		data["fail_started"] = true
		data["furious"] = true
		data.erase("work")
		_replace_rest(run, WorkPlan.failure_beats(StringName(run["world"])))


func _wait_ok(run: Dictionary, bt: Dictionary) -> bool:
	var site := worlds.site(StringName(run["world"]))
	match StringName(bt.get("until", &"")):
		&"arrived":
			for h in _run_hands(run, bt):
				if h.presence.y < 0.6 or h.error() > ARRIVE_DIST * maxf(1.0, h.speed()):
					return false
			return true
		&"stage":
			return site.build.stage_done()
		&"repaired":
			return site.build.crack <= float(run["data"].get("repair_limit", 0.0)) + 0.002
		&"dismantled":
			return site.build.core <= 0.0
		&"edited":
			return artifact.edit_done()
		&"applied":
			return _applied
	return true


# ================================================================== ops


func _op(run: Dictionary, bt: Dictionary, src: int) -> void:
	var op: StringName = bt["op"]
	var world: StringName = bt.get("world", run["world"])
	match op:
		&"done":
			run["done"] = true
		&"gaze":
			_gaze_beat[src] = {"at": bt.get("at", &"world"), "world": world, "until": _clock + float(bt.get("secs", 2.0)),
				"weight": float(bt.get("weight", 1.0)), "scan": bool(bt.get("scan", false)), "run": run}
		&"attend":
			var kind := maxi(MikuMind.FOCUS_IDS.find(StringName(bt.get("kind", &"work"))), 0)
			var secs := float(bt.get("secs", 2.0))
			var fid: StringName = world if kind == MikuMind.Focus.WORLD or kind == MikuMind.Focus.WORK \
				else StringName(bt.get("kind", &""))
			if secs > 0.0:
				mind.attend(kind as MikuMind.Focus, fid, secs)
		&"turn":
			_turn_beat[src] = {"at": bt.get("at", &""), "world": world, "amount": float(bt.get("amount", 0.4)),
				"angle": float(bt.get("angle", 0.0)), "until": _clock + float(bt.get("secs", 2.0)), "run": run}
		&"pose":
			var key := StringName(("m_" if src == 0 else "o_") + String(bt.get("key", &"beat")))
			_poses[key] = {"v": [float(bt.get("lean", 0.0)), float(bt.get("side", 0.0)), float(bt.get("lift", 0.0)),
				float(bt.get("raise", 0.0)), float(bt.get("fwd", 0.0)), float(bt.get("tilt", 0.0)), float(bt.get("nod", 0.0))],
				"until": _clock + float(bt.get("secs", 1.0))}
		&"breath":
			_breath_beat = {"depth": float(bt.get("depth", 1.0)), "rate": float(bt.get("rate", 1.0)),
				"until": _clock + float(bt.get("secs", 2.0))}
		&"arm":
			_op_arm(run, bt, src, world)
		&"wave":
			for s in _sides(run, StringName(bt.get("side", &"lead")), src):
				_wave[s] = {"kind": bt.get("kind", &"tap"), "until": _clock + float(bt.get("secs", 1.5)), "t0": _clock}
		&"summon":
			_op_summon(run, int(bt.get("n", 1)), StringName(bt.get("near", &"miku")), world, StringName(bt.get("role", &"")))
		&"cast":
			_op_cast(run, bt)
		&"pull":
			var drive := lerpf(1.0, 1.9, mind.rigidity())
			for h in _run_hands(run, bt):
				h.drive = drive
				threads.pull_hand(h, float(bt.get("force", 0.6)))
		&"send":
			_op_send(run, bt, world)
		&"mirror":
			run["data"]["mirror"] = {"gain": float(bt.get("gain", 3.0)), "until": _clock + float(bt.get("secs", 3.0)),
				"a0": body.hand_position(0), "a1": body.hand_position(1)}
		&"relax":
			if bt.get("all", false):
				threads.relax_all()
			else:
				threads_relax(run, int(bt.get("except", -1)))
		&"release":
			_op_release(run, bool(bt.get("all", false)))
		&"stage":
			var site := worlds.site(world)
			var s: WorldBuild.Stage = bt.get("s", WorldBuild.Stage.GATHER)
			site.build.begin(s)
			run["data"]["stage"] = s
		&"work":
			run["data"]["work"] = {"rate": float(bt.get("rate", 0.2))}
			run["data"]["mirror"] = {"gain": WORK_MIRROR_GAIN, "until": 1.0e9,
				"a0": body.hand_position(0), "a1": body.hand_position(1)}
		&"work_stop":
			run["data"].erase("work")
			run["data"].erase("repair")
			run["data"].erase("dismantle")
			run["data"].erase("mirror")
			worlds.site(world).via = Vector3.INF
		&"fault":
			_op_fault(run, bt, world)
		&"repair":
			run["data"]["repair"] = {"rate": float(bt.get("rate", 0.2))}
			run["data"]["repair_limit"] = float(bt.get("limit", 0.0))
		&"dismantle":
			worlds.site(world).build.begin_dismantle()
			run["data"]["dismantle"] = {"rate": float(bt.get("rate", 0.5))}
		&"success":
			mind.on_success(float(bt.get("mag", 1.0)))
		&"mood":
			mind.force_mood(StringName(bt.get("to", &"")))
		&"artifact":
			_op_artifact(run, StringName(bt.get("state", &"")))
		&"commit":
			_applied = false
			file_committed.emit(run["args"].duplicate())
		&"self_react":
			_splice(run, ActionScript.self_reaction(_appearance_changed))
		&"particles":
			var site2 := worlds.site(world)
			match StringName(bt.get("kind", &"form")):
				&"form":
					particles.form(site2.global_position, site2.radius * 1.2)
				&"fragments":
					particles.fragments(site2.crack_point(), site2.global_transform.basis * site2.crack_direction(),
						float(bt.get("strength", 1.0)))
		&"next_stage":
			_op_next_stage(run, bt)


func _op_arm(run: Dictionary, bt: Dictionary, src: int, world: StringName) -> void:
	var g: StringName = bt.get("g", &"rest")
	for s in _sides(run, StringName(bt.get("side", &"lead")), src):
		if g == &"rest":
			if _arm_spec[s].get("src", -1) == src:
				_arm_spec[s] = {}
			continue
		_arm_spec[s] = {"g": g, "at": bt.get("at", &"world"), "world": world, "speed": float(bt.get("speed", 1.0)),
			"until": _clock + float(bt.get("secs", 1.0e9)), "rhythm": bool(bt.get("rhythm", false)) or g == Gestures.CONDUCT \
				and bt.has("sway"), "src": src, "run": run}


func _op_summon(run: Dictionary, n: int, near: StringName, world: StringName, role: StringName) -> void:
	var list: Array[PuppetHand] = run["hands"]
	_adopt_idle_hands(run)
	var lead_left: bool = int(run["lead"]) == 0
	var basis := body.body_basis()
	var i := 0
	while list.size() < n:
		var h := hands.acquire(i % 2 == 1)
		var at := Vector3.ZERO
		if near == &"world":
			var site := worlds.site(world)
			var from := body.chest_position()
			var to := site.global_position
			var k := float(list.size())
			at = from.lerp(to, 0.55) + basis.y * (0.9 + 0.25 * k) + basis.x * (sin(k * 2.1) * 1.2)
		else:
			at = global_transform * LivingLayout.summon_point(list.size(), lead_left)
		var face := (body.chest_position() - at).normalized()
		h.summon(at, basis.y, -face, &"relaxed")
		h.set_meta(&"role", role)
		list.append(h)
		i += 1
	if role != &"" and not list.is_empty():
		list[list.size() - 1].set_meta(&"role", role)


func _op_cast(run: Dictionary, bt: Dictionary) -> void:
	var extra := int(bt.get("extra", 0))
	var speed := mind.tempo()
	var lead: int = run["lead"]
	var k := 0
	for h in _run_hands(run, bt):
		var alive := false
		for t in threads.threads:
			if t["hand"] == h and (t["cycle"] as ThreadCycle).is_alive():
				alive = true
		if alive:
			k += 1
			continue
		var side := lead if k % 2 == 0 else 1 - lead
		if bt.has("side"):
			side = lead if bt["side"] == &"lead" else 1 - lead
		var finger: int = [1, 2, 3, 1][k % 4]
		threads.cast(side, finger, h, -1, 0.0, speed)
		for e in extra:
			threads.cast(side, [2, 3, 0][e % 3], h, 1 + (e % 4), 0.0, speed * 1.2)
		k += 1


func _op_send(run: Dictionary, bt: Dictionary, world: StringName) -> void:
	var list := _run_hands(run, bt)
	var n := list.size()
	var site := worlds.site(world)
	var basis := body.body_basis()
	var places: Dictionary = run["data"].get("places", {})
	var stage: WorldBuild.Stage = run["data"].get("stage", WorldBuild.Stage.GATHER)
	var furious: bool = run["data"].get("furious", false) and mind.mood == MikuMind.Mood.ANGRY
	for i in n:
		var h: PuppetHand = list[i]
		var place := StringName(bt.get("place", &"work"))
		var pos := Vector3.ZERO
		var point := Vector3.FORWARD
		var palm := Vector3.DOWN
		var pose: StringName = &"open"
		match place:
			&"present":
				var spread := (float(i) - float(n - 1) * 0.5)
				pos = body.chest_position() + basis.z * 2.6 + basis.y * (0.7 + 0.15 * absf(spread)) \
					+ basis.x * spread * 1.15 * (1.0 if int(run["lead"]) == 0 else -1.0)
				palm = -basis.z
				point = (basis.y * 0.9 + basis.x * spread * 0.2).normalized()
				pose = &"open"
			&"work":
				var wp := LivingLayout.work_place(site.global_position, site.radius, i, n, float(bt.get("dist", 1.55)))
				pos = wp[0]
				point = wp[1]
				palm = wp[2]
				pose = _stage_pose(stage, furious)
			&"crack":
				var cp := site.crack_point()
				var cn := (cp - site.global_position).normalized()
				var lat := cn.cross(Vector3.UP).normalized()
				pos = cp + cn * site.radius * float(bt.get("dist", 0.8)) + lat * (float(i) - float(n - 1) * 0.5) * site.radius * 0.9
				palm = -cn
				point = (Vector3.UP * 0.6 + lat * (0.4 if i % 2 == 0 else -0.4)).normalized()
				pose = &"smooth"
			&"card_hold":
				var spot := _target(run, &"file_spot", world)
				pos = spot + Vector3.DOWN * ConfigArtifact.HOLD_OFFSET + (spot - body.chest_position()).normalized() * -0.05
				palm = Vector3.UP
				point = (basis.z * 0.8 - basis.x * 0.3).normalized()
				pose = &"hold"
			&"card_edit":
				var spot2 := artifact.global_position if artifact.is_present() else _target(run, &"file_spot", world)
				var side := basis.x * (1.0 if int(run["lead"]) == 0 else -1.0)
				pos = spot2 + side * 0.75 + basis.z * 0.35 + Vector3.UP * 0.1
				palm = -side
				point = (-side * 0.6 + basis.z * -0.2 + Vector3.UP * 0.2).normalized()
				pose = &"point"
		places[h] = {"pos": pos, "point": point, "palm": palm, "pose": pose, "kind": place}
		h.set_goal(pos, point, palm, pose)
	run["data"]["places"] = places


func _op_release(run: Dictionary, all: bool) -> void:
	var list: Array[PuppetHand] = []
	if all:
		list = hands.active_hands()
	else:
		list = (run["hands"] as Array[PuppetHand]).duplicate()
	for h in list:
		threads.relax_hand(h)
		hands.release(h)
	(run["hands"] as Array[PuppetHand]).clear()
	if run["data"].has("places"):
		(run["data"]["places"] as Dictionary).clear()


func _op_fault(run: Dictionary, bt: Dictionary, world: StringName) -> void:
	var site := worlds.site(world)
	site.build.fault(StringName(bt.get("kind", &"crack")), float(bt.get("amount", 0.5)))
	var sev := float(bt.get("severity", 0.0))
	particles.fragments(site.crack_point(), site.global_transform.basis * site.crack_direction(), 0.6 + sev * 1.5)
	if sev > 0.0:
		mind.on_failure(sev)
		agenda.interrupt()


func _op_artifact(run: Dictionary, state: StringName) -> void:
	match state:
		&"appear":
			var spot := _target(run, &"file_spot", run["world"])
			artifact.appear(spot, (_user_point() - spot).normalized())
			_applied = false
		&"held":
			for h in run["hands"] as Array[PuppetHand]:
				if h.get_meta(&"role", &"") == &"holder":
					artifact.hold(h)
					return
			var list: Array[PuppetHand] = run["hands"]
			if not list.is_empty():
				artifact.hold(list[0])
		&"edit":
			artifact.begin_edit()
		&"valid":
			artifact.validate()
		&"reject":
			artifact.reject()
		&"vanish":
			artifact.vanish()


func _op_next_stage(run: Dictionary, bt: Dictionary) -> void:
	var world: StringName = run["world"]
	var site := worlds.site(world)
	var data: Dictionary = run["data"]
	var furious: bool = bt.get("furious", data.get("furious", false))
	data["furious"] = furious
	var s: WorldBuild.Stage
	if bt.has("from"):
		s = bt["from"]
	elif site.build.stage == WorldBuild.Stage.DORMANT:
		s = WorldBuild.Stage.GATHER
	elif site.build.stage_done():
		s = WorkPlan.next_stage(site.build.stage)
	else:
		s = site.build.stage
	if s == WorldBuild.Stage.STABLE or site.build.is_stable():
		mind.end_task(true)
		_replace_rest(run, WorkPlan.finish_beats(world, data.get("fail_started", false)))
		return
	_replace_rest(run, WorkPlan.stage_beats(s, world, furious and mind.mood == MikuMind.Mood.ANGRY))


# ================================================================== hands & world


func threads_relax(run: Dictionary, except: int) -> void:
	var list: Array[PuppetHand] = run["hands"]
	for i in list.size():
		if i != except:
			threads.relax_hand(list[i])


## Hands of the run, filtered by beat args `only` (role) / `only_index`.
func _run_hands(run: Dictionary, bt: Dictionary) -> Array[PuppetHand]:
	var list: Array[PuppetHand] = run["hands"]
	if bt.has("only_index"):
		var i := int(bt["only_index"])
		var one: Array[PuppetHand] = []
		if i < list.size():
			one.append(list[i])
		return one
	if bt.has("only"):
		var out: Array[PuppetHand] = []
		for h in list:
			if h.get_meta(&"role", &"") == bt["only"]:
				out.append(h)
		return out
	return list


## Hands already out and not used by another run join this run (continuity: the hands she
## summoned keep serving her).
func _adopt_idle_hands(run: Dictionary) -> void:
	var list: Array[PuppetHand] = run["hands"]
	for h in hands.active_hands():
		if h.goal_presence <= 0.0 or list.has(h):
			continue
		var used := false
		for other in [_main, _overlay]:
			if not is_same(other, run) and not other.is_empty() and (other["hands"] as Array).has(h):
				used = true
		if not used:
			list.append(h)


func _drive_hands() -> void:
	for h in hands.hands:
		if h.active:
			h.pull = threads.tension_on(h)
	if _main.is_empty():
		return
	var data: Dictionary = _main["data"]
	var places: Dictionary = data.get("places", {})
	var mirror: Dictionary = data.get("mirror", {})
	var mirroring := not mirror.is_empty() and _clock < float(mirror["until"])
	var site := worlds.site(StringName(_main["world"]))
	var basis := body.body_basis()
	for h: PuppetHand in places:
		if not is_instance_valid(h) or not h.active:
			continue
		var p: Dictionary = places[h]
		var pos: Vector3 = p["pos"]
		if mirroring:
			# The hand follows her hand on its side (her left drives the hands on her left).
			var s := 0 if (h.global_position - body.chest_position()).dot(basis.x) >= 0.0 else 1
			var a0: Vector3 = mirror["a0"] if s == 0 else mirror["a1"]
			pos += (body.hand_position(s) - a0) * float(mirror["gain"])
		if p["kind"] == &"work" and data.has("work") and site.build.stage == WorldBuild.Stage.CORE:
			pos = pos.lerp(site.global_position, 0.28 * site.build.core)
		if p["kind"] == &"card_edit" and artifact.state == ConfigArtifact.State.EDIT:
			var lat := basis.x
			pos += lat * sin(_clock * 7.0) * 0.07 + Vector3.UP * (0.12 - artifact.edit * 0.3) + basis.z * cos(_clock * 7.0) * 0.03
		h.set_goal(pos, p["point"], p["palm"], p["pose"])


func _drive_work(dt: float) -> void:
	_particle_clock += dt
	if _main.is_empty() or _main["action"] != ActionScript.WORK:
		return
	var data: Dictionary = _main["data"]
	if not (data.has("work") or data.has("repair") or data.has("dismantle")):
		return
	var site := worlds.site(StringName(_main["world"]))
	var list: Array[PuppetHand] = _main["hands"]
	var places: Dictionary = data.get("places", {})
	var contrib := 0.0
	var nearest: PuppetHand = null
	var near_d := INF
	for h in list:
		if not h.active or not places.has(h):
			continue
		var ten := threads.tension_on(h)
		var place_pos: Vector3 = (places[h] as Dictionary)["pos"]
		if ten > 0.15 and (h.global_position - place_pos).length() < WORK_DIST + site.radius * 0.6:
			contrib += ten
			var d := (h.global_position - body.chest_position()).length()
			if d < near_d:
				near_d = d
				nearest = h
	var n := maxf(float(list.size()), 1.0)
	var k := clampf(contrib / (n * 0.6), 0.0, 1.4)
	if agenda.current == MicroAgenda.HESITATE:
		k *= 0.2
	site.via = nearest.global_position + nearest.palm_s.y * site.radius * 0.35 if nearest != null else Vector3.INF
	if data.has("work"):
		site.build.work(float(data["work"]["rate"]) * dt * k)
	if data.has("repair"):
		var amount := float(data["repair"]["rate"]) * dt * k
		var limit := float(data.get("repair_limit", 0.0))
		site.build.crack = maxf(site.build.crack - amount, limit)
		site.build.imbalance = maxf(site.build.imbalance - amount, 0.0)
		site.build.energy = minf(site.build.energy + amount * 2.0, 1.0)
	if data.has("dismantle"):
		site.build.dismantle(float(data["dismantle"]["rate"]) * dt * k)
	# Particles only where the hands are doing something now.
	if k > 0.05 and _particle_clock > 0.28:
		_particle_clock = 0.0
		if data.has("dismantle"):
			particles.fragments(site.global_position + Vector3.UP * site.radius * 0.6, Vector3.UP, 0.5 * k)
		elif site.build.stage == WorldBuild.Stage.CORE and data.has("work"):
			particles.compress(site.global_position, site.radius * 0.55, k)
		var live: Array[int] = []
		for i in threads.threads.size():
			var c := threads.cycle(i)
			if c.is_alive() and c.tension.y > 0.4:
				live.append(i)
		if not live.is_empty():
			_energy_rr = (_energy_rr + 1) % live.size()
			particles.energy(live[_energy_rr], k)


## Hands left without a task are let go (a flick of her hand) after HAND_IDLE_RELEASE s.
func _idle_hands(dt: float) -> void:
	if not _main.is_empty() or not _queue.is_empty() or hands.active_count() == 0:
		_hand_idle = 0.0
		return
	_hand_idle += dt
	if _hand_idle >= HAND_IDLE_RELEASE:
		_hand_idle = 0.0
		perform(ActionScript.DISCARD, {})


# ================================================================== body


func _agenda_context() -> Dictionary:
	var working: bool = not _main.is_empty() and _main["action"] == ActionScript.WORK
	var site := worlds.site(work_world)
	return {"working": working, "hands": hands.active_count(), "failed": site != null and site.build.is_broken(),
		"busy": not _main.is_empty() and not working}


func _compose_body() -> void:
	var m: int = mind.mood
	var stiff := mind.rigidity()
	body.set_character(stiff, mind.tempo())
	var micro := agenda.current
	var mp := agenda.progress()
	# Posture: mood + beats + micro-behaviour.
	var v := _pv
	var base: Array = MOOD_POSTURE[m]
	for i in 7:
		v[i] = float(base[i])
	for key: StringName in _poses.keys():
		var p: Dictionary = _poses[key]
		if _clock > float(p["until"]):
			_poses.erase(key)
			continue
		for i in 7:
			v[i] += float((p["v"] as Array)[i])
	var bell := sin(PI * mp)
	match micro:
		MicroAgenda.CORRECT_POSTURE:
			v[2] += 0.25 * bell
			v[3] -= 0.2 * bell
			v[4] -= 0.25 * bell
		MicroAgenda.HESITATE:
			v[6] -= 0.05 * bell
			v[0] -= 0.04 * bell
		MicroAgenda.CONTINUE:
			v[6] += 0.07 * bell
		MicroAgenda.OBSERVE_HAND, MicroAgenda.TRACK_OBJECT:
			v[5] += 0.06 * bell
		MicroAgenda.BREATHE_DEEP:
			v[2] += 0.12 * bell
	body.set_posture(v[0], v[1], v[2], v[3], v[4], v[5], v[6])
	# Breath.
	var br: Array = MOOD_BREATH[m]
	var rate := float(br[0])
	var depth := float(br[1])
	if micro == MicroAgenda.BREATHE_DEEP:
		depth *= 1.0 + 1.1 * bell
		rate *= 0.8
	elif micro == MicroAgenda.HESITATE:
		depth *= 0.3
	if not _breath_beat.is_empty():
		if _clock > float(_breath_beat["until"]):
			_breath_beat = {}
		else:
			depth = float(_breath_beat["depth"])
			rate *= float(_breath_beat["rate"])
	body.set_breath(rate, depth)
	# Weight: shifts at each shift_weight behaviour (alternating), none when rigid.
	if micro == MicroAgenda.SHIFT_WEIGHT and agenda.elapsed < 0.05:
		_weight_side = -_weight_side
	body.set_weight(_weight_side * (1.0 - stiff) * (0.6 if mind.mood == MikuMind.Mood.FOCUSED else 1.0))
	# Gaze and turn.
	body.set_gaze(_gaze_target(micro, mp))
	body.set_turn(_turn_target())
	# Arms.
	var basis := body.body_basis()
	for s in 2:
		var busy := false
		var spec: Dictionary = _arm_spec[s]
		if not spec.is_empty() and _clock > float(spec["until"]):
			_arm_spec[s] = {}
			spec = {}
		var g: StringName = Gestures.REST_BY_MOOD[m]
		var at := Vector3.ZERO
		var speed := 1.0
		var ph := 0.0
		if not spec.is_empty():
			g = spec["g"]
			at = _target(spec["run"], spec["at"], spec["world"])
			speed = spec["speed"]
			ph = _phase if spec["rhythm"] else 0.0
			busy = true
		else:
			var micro_g := _micro_arm(s, micro)
			if micro_g != &"":
				g = micro_g
				at = _target({}, &"world", work_world)
				ph = mp * TAU
			else:
				at = _target({}, &"world", work_world)
		if g == Gestures.FREEZE:
			continue
		Gestures.goal(g, body.shoulder(s), body.arm_reach(s), at, basis, 1.0 if s == 0 else -1.0, ph,
			body.chest_position(), body.head_position(), _goal)
		body.set_arm(s, _goal.pos, _goal.palm, _goal.point, _goal.pole, _goal.pose, speed * _goal.speed)
		_finger_wave(s, micro, busy)


func _micro_arm(s: int, micro: StringName) -> StringName:
	var free := _free_side()
	match micro:
		MicroAgenda.OBSERVE_HAND:
			return Gestures.SELF if s == free and hands.active_count() == 0 else &""
		MicroAgenda.ADJUST:
			return Gestures.PINCH if s == _lead_for(work_world) else &""
	return &""


func _finger_wave(s: int, micro: StringName, busy: bool) -> void:
	var w := _wave[s]
	var kind: StringName = &""
	var t0 := 0.0
	if not w.is_empty() and _clock <= float(w["until"]):
		kind = w["kind"]
		t0 = float(w["t0"])
	elif micro == MicroAgenda.FINGERS and (s == _free_side() or not busy):
		kind = &"ripple"
		t0 = _clock - agenda.elapsed
	elif mind.mood == MikuMind.Mood.FRUSTRATED and not busy:
		kind = &"tap"
	for i in 5:
		var x := 0.0
		var t := _clock - t0
		match kind:
			&"ripple":
				x = 0.22 * sin(t * 3.2 - float(i) * 0.7)
			&"tap":
				x = 0.25 * maxf(sin(t * 9.0 - float(i) * 1.1), 0.0) if i > 0 else 0.0
			&"beckon":
				x = 0.35 * (0.5 + 0.5 * sin(t * 6.0)) if i > 0 else 0.0
		_wave_buf[i] = x
	body.set_finger_wave(s, _wave_buf)


func _gaze_target(micro: StringName, mp: float) -> Vector3:
	var target := Vector3.ZERO
	var found := false
	for src in [1, 0]:
		var g: Dictionary = _gaze_beat[src]
		if g.is_empty():
			continue
		if _clock > float(g["until"]):
			_gaze_beat[src] = {}
			continue
		var p := _target(g["run"], g["at"], g["world"])
		if g["scan"]:
			var site := worlds.site(StringName(g["world"]))
			var r := site.radius if site != null else 0.5
			p += Vector3(sin(_clock * 0.9) * r * 0.5, cos(_clock * 0.63) * r * 0.3, 0.0)
		var w: float = g["weight"]
		if w < 1.0:
			var base := _attention_point(micro, mp)
			p = base.lerp(p, w)
		target = p
		found = true
		break
	if not found:
		target = _attention_point(micro, mp)
	# Micro-saccades: small fixation jumps (none when composure is lost: the locked stare).
	if _clock >= _saccade_at:
		_saccade_at = _clock + _noise.randf_range(0.5, 1.7)
		var d := (target - body.eye_position()).length()
		_saccade = Vector3(_noise.randf_range(-1, 1), _noise.randf_range(-0.6, 0.6), 0.0) * d * 0.025
	return target + _saccade * (1.0 - mind.rigidity())


## Where the attention puts the eyes without a gaze beat: the micro-behaviour, then the focus.
func _attention_point(micro: StringName, mp: float) -> Vector3:
	match micro:
		MicroAgenda.TRACK_OBJECT:
			# A drifting fragment of a dormant world's cloud.
			var site := worlds.site(_other_world(work_world))
			var ang := _clock * 0.35
			return site.global_position + Vector3(cos(ang), 0.25 * sin(ang * 1.3), sin(ang)) * site.radius * 1.9
		MicroAgenda.CHECK_WORLD:
			return worlds.site(_other_world(work_world)).global_position
		MicroAgenda.OBSERVE_HAND:
			var hs := hands.active_hands()
			if not hs.is_empty():
				return hs[0].global_position
			return body.hand_position(_free_side())
		MicroAgenda.FINGERS:
			if mp > 0.3 and mp < 0.7:
				return body.hand_position(_free_side())
		MicroAgenda.LOOK_AT_WORK, MicroAgenda.ADJUST, MicroAgenda.HOLD:
			return worlds.site(work_world).global_position
	match mind.focus_kind():
		MikuMind.Focus.USER:
			return _user_point()
		MikuMind.Focus.WORLD, MikuMind.Focus.WORK:
			var id := mind.focus_id()
			return worlds.site(id if worlds.has_world(id) else work_world).global_position
		MikuMind.Focus.HAND:
			var hs2 := hands.active_hands()
			if not hs2.is_empty():
				return hs2[0].global_position
		MikuMind.Focus.FILE:
			if artifact.is_present():
				return artifact.global_position
		MikuMind.Focus.SELF:
			return body.hand_position(_free_side())
	# Nothing in particular: the world she cares for, softly.
	return worlds.site(work_world).global_position + Vector3.UP * 0.4


func _turn_target() -> float:
	for src in [1, 0]:
		var t: Dictionary = _turn_beat[src]
		if t.is_empty():
			continue
		if _clock > float(t["until"]):
			_turn_beat[src] = {}
			continue
		if StringName(t["at"]) == &"":
			return float(t["angle"])
		var p := _target(t["run"], t["at"], t["world"])
		var d := global_transform.affine_inverse() * p
		return clampf(atan2(d.x, d.z), -1.2, 1.2) * float(t["amount"])
	return 0.0


## World point of a target keyword.
func _target(run: Dictionary, at: StringName, world: StringName) -> Vector3:
	var basis := body.body_basis()
	match at:
		&"user":
			return _user_point()
		&"world":
			var site := worlds.site(world) if worlds.has_world(world) else worlds.site(work_world)
			return site.global_position
		&"crack":
			return worlds.site(world).crack_point()
		&"hands":
			var list: Array = run.get("hands", [])
			if list.is_empty():
				list = hands.active_hands()
			if list.is_empty():
				return body.chest_position() + basis.z * 2.5
			var c := Vector3.ZERO
			for h in list:
				c += (h as PuppetHand).global_position
			return c / float(list.size())
		&"summon":
			var lead_left: bool = int(run.get("lead", 1)) == 0
			return global_transform * LivingLayout.summon_point(0, lead_left)
		&"file":
			return artifact.global_position if artifact.is_present() else _target(run, &"file_spot", world)
		&"file_spot":
			return body.chest_position() + basis.z * 1.5 + basis.y * 0.25 \
				+ basis.x * (0.35 if int(run.get("lead", 1)) == 0 else -0.35)
		&"think":
			return body.eye_position() + basis.z * 2.0 - basis.y * 1.1 - basis.x * 0.9
		&"own_hand":
			return body.hand_position(int(run.get("lead", 1)))
		&"own_shoulder":
			return body.shoulder(int(run.get("lead", 1))) + basis.y * 0.05
		&"self_low":
			return body.chest_position() - basis.y * 1.3 + basis.z * 0.5
		&"inward":
			return body.eye_position() + basis.z * 1.5 - basis.y * 0.7
	return body.eye_position() + basis.z * 4.0


func _user_point() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam != null else LivingLayout.USER_FALLBACK


## The arm on the side of `world` leads (0 = her left, +X).
func _lead_for(world: StringName) -> int:
	var c := LivingLayout.world_center(world)
	return 0 if (c - global_position).x >= 0.0 else 1


## The arm the main action does not use (else the one away from the work).
func _free_side() -> int:
	for s in 2:
		if _arm_spec[s].is_empty():
			return s
	return 1 - _lead_for(work_world)


func _sides(run: Dictionary, side: StringName, src: int) -> Array[int]:
	var lead: int = run.get("lead", 1)
	match side:
		&"both":
			return [0, 1]
		&"other":
			return [1 - lead]
		&"free":
			for s in 2:
				if _arm_spec[s].is_empty() or _arm_spec[s].get("src", -1) == src:
					if not (src == 1 and s == lead and not _main.is_empty()):
						return [s]
			return []
	return [lead]


func _other_world(id: StringName) -> StringName:
	var ids := LivingLayout.world_ids()
	var i := ids.find(id)
	return ids[(i + 1 + int(_clock / 9.0) % (ids.size() - 1)) % ids.size()] if i >= 0 else ids[1]


static func _stage_pose(stage: WorldBuild.Stage, furious: bool) -> StringName:
	if furious:
		return &"claw"
	match stage:
		WorldBuild.Stage.GATHER:
			return &"open"
		WorldBuild.Stage.CORE:
			return &"cup"
		WorldBuild.Stage.LAYERS:
			return &"smooth"
		WorldBuild.Stage.ADJUST:
			return &"pinch"
	return &"open"


# ================================================================== camera & signals


func _update_focus() -> void:
	var kind: StringName = &"miku"
	var t_mood := mind.time_in_mood
	var m := mind.mood
	var working: bool = not _main.is_empty() and _main["action"] == ActionScript.WORK
	var n_hands := hands.active_count()
	if (m == MikuMind.Mood.ANGRY and t_mood < 2.6) or (m == MikuMind.Mood.FRUSTRATED and t_mood < 1.8) \
			or (m == MikuMind.Mood.RECOVERING and t_mood < 3.0):
		kind = &"emotion"
	elif not _overlay.is_empty() and _overlay["action"] == ActionScript.LOOK_AT_USER:
		kind = &"user"
	elif artifact.is_present():
		kind = &"file"
	elif n_hands >= 3:
		kind = &"wide"
	elif working:
		kind = &"work"
	elif n_hands >= 1:
		kind = &"puppet"
	if _last_focus_kind != &"" and kind != _last_focus_kind and _clock - _focus_since < FOCUS_HOLD \
			and kind != &"emotion" and kind != &"user":
		kind = _last_focus_kind
	if kind != _last_focus_kind:
		_last_focus_kind = kind
		_focus_since = _clock
	var pts: PackedVector3Array = _focus["points"]
	pts.clear()
	pts.append(body.head_position())
	pts.append(body.chest_position())
	match kind:
		&"miku":
			pts.append(body.to_world(Vector3(0.0, -2.6, 0.0)))
		&"puppet", &"wide":
			for h in hands.active_hands():
				pts.append(h.global_position)
			if kind == &"wide":
				var s := worlds.site(work_world)
				pts.append(s.global_position)
		&"work":
			var s2 := worlds.site(work_world)
			pts.append(s2.global_position + Vector3.UP * s2.radius)
			pts.append(s2.global_position - Vector3.UP * s2.radius)
		&"file":
			pts.append(artifact.global_position)
		&"emotion", &"user":
			pass
	_focus["points"] = pts
	_focus["kind"] = kind
	_focus["since"] = _clock - _focus_since


## Mood changes come from events (failures, tasks) and from time: announced once per change.
func _emit_mood() -> void:
	if mind.mood != _last_mood:
		_last_mood = mind.mood
		agenda.interrupt()
		mood_changed.emit(mind.mood_id())


func _emit_attention() -> void:
	var k: StringName = MikuMind.FOCUS_IDS[mind.focus_kind()]
	var key := StringName(String(k) + ":" + String(mind.focus_id()))
	if key != _last_attention:
		_last_attention = key
		attention_changed.emit(k, mind.focus_id())
