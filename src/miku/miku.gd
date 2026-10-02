class_name Miku
extends Node3D
## MIKU, the living character of the prototype (Loop 5, ADR-015/016). Owner: animator.
## Runtime of the character: her mind (MikuMind: mood, composure, attention, task), the agenda of
## micro-behaviours (MicroAgenda), the execution of the actions of the vocabulary as movement
## (ActionScript / WorkPlan beats), and what she controls — puppet hands (HandPool), intent
## threads (IntentThreads), the work worlds (WorkWorld), the causal particles and the
## configuration artifact. Real-time state driven by MotionClock (deterministic under the Movie
## Maker); never a function of Simulation.time; no seek (reset = recompose).
##
## Three channels of beats:
##   TASK     the work on a world (background): stages, failure, tear-down, rebuild. Started by
##            WORK, by target_world (if nobody gives a plan) or by the roteiro's `living.*` events.
##   MAIN     the foreground actions of the vocabulary, one at a time (queue). While one runs the
##            task is suspended (her hands hold, the matter waits) and resumes after it.
##   OVERLAY  eyes, head and a free arm over the others: LOOK_AT_USER, ACKNOWLEDGE, the reaction
##            to the user's call, the look at a pointed world, FRUSTRATED/ANGRY/RECOVER during work.
##
## API (interaction system, docs/AGENT.md):
##   perform(action, args := {}) -> bool  one of ActionScript.VOCABULARY, arguments of the
##       interaction system's ActionVocabulary (normalised by ActionScript.normalize; extra dev
##       args: WORK {fail: bool}, EDIT_FILE {patch}). Exactly ONE action_finished(action) per
##       accepted perform. WORK returns once she is engaged (the work goes on in the task).
##   notice_user()            the user called her: reaction by mood (curious, brief, curt, cold)
##   target_world(id)         the user pointed at a world: she looks, acknowledges; if no plan
##                            arrives within PLAN_GRACE s she points and works on it herself
##   apply_config(values)     whole configuration at binding (silent)
##   on_config_changed(path, old, new)   one validated change, after EDIT_FILE: the artifact
##                            validates, her body/personality take it (she reacts in INSPECT(self))
##   inspect_state() -> Dictionary  (group `dev_inspect`)
##   world_ids(), mood(), current_action(), is_busy(), story_focus()
## Correlated actions (docs/contracts/loop-05-round2.md, Bloco 1):
##   perform(action, {request_id: int (> 0 from the InteractionRouter, 0 = her own), step: int, ...})
##   action_event(request_id, action, phase, info): phase &"accepted" (info.estimate) -> &"started"
##       -> &"progress" (info.t 0..1, info.stage = causal stage reached) -> exactly ONE terminal
##       &"finished" | &"failed" (info.reason) | &"cancelled" (info.reason) per accepted perform.
##       Every info carries `step`.
##   estimate_duration(action, args) -> float   honest real seconds from now (queue included)
##   cancel(request_id) -> int   cancels that request's actions (queued, running, followers, the
##       task it started) with &"cancelled", and dissolves its hands, threads and artifact.
##   A user plan's first step (LOOK_AT_USER / LOOK_AT_WORLD with request_id > 0) never waits: it
##       starts in the same frame and the eyes move at once (overlay when the main channel is busy).
##   inspect_state().causality: per request/action timeline of the causal chain (game seconds of
##       her clock): intent, anticipation, gesture, thread, hand, matter, result (CAUSAL_STAGES).
## Signals: action_started(action), action_finished(action) (compatibility: one per accepted
##   perform, also when it fails or is cancelled), action_event(...), mood_changed(state),
##   attention_changed(kind, id), file_committed(args).
## Roteiro: Simulation.event_emitted `living.hands|work_order|work_step|work_failed|
## work_dismantled|work_recovered|world_complete` (LivingScript) drive the task.
## Entity `miku` (pick body in MikuBody); worlds `world_vesper|calyx|orrin` (WorkWorld).
## Composition: siblings in groups HandPool.GROUP, IntentThreads.GROUP, WorkWorld.GROUP,
## CausalParticles.GROUP are used when present; anything missing is created as a child.

signal action_started(action: StringName)
signal action_finished(action: StringName)
signal action_event(request_id: int, action: StringName, phase: StringName, info: Dictionary)
signal mood_changed(state: StringName)
signal attention_changed(kind: StringName, id: StringName)
signal file_committed(args: Dictionary)

const GROUP := &"living_miku"
const INSPECT_GROUP := &"dev_inspect"
const ENTITY := &"miku"
## Beat sources (channels) and their priority on the body (overlay > main > task).
## Internal overlays (perception, not actions of the vocabulary: no signals of their own).
const NOTICE := &"_NOTICE_USER"
const TARGET := &"_TARGET_WORLD"
const SELF_REACT := &"_SELF"
const SRC_TASK := 0
const SRC_OVERLAY := 1
const SRC_MAIN := 2
const PRIORITY: Array[int] = [SRC_OVERLAY, SRC_MAIN, SRC_TASK]
## A hand is "in place" this close to its goal (units).
const ARRIVE_DIST := 0.38
## A hand works the world when this close to its place and pulled.
const WORK_DIST := 0.7
## Hands summoned and left idle are released (with a gesture) after this many seconds.
const HAND_IDLE_RELEASE := 7.0
## Seconds target_world waits for a plan before she starts the work herself.
const PLAN_GRACE := 1.2
## Longest frame step (s). Large on purpose: on a slow (software) renderer a frame can take
## 0.3–0.5 s and the character must still keep real time (the springs sub-step: no jump).
const MAX_DT := 0.5
## Rhythm of the working gestures (s per cycle at tempo 1).
const RHYTHM_PERIOD := 1.9
## Hands mirror her hand's displacement by this gain while working (and `mirror` beats).
const WORK_MIRROR_GAIN := 1.6
## Seconds a camera story focus is held at least (no restless camera).
const FOCUS_HOLD := 2.2

## Phases of action_event.
const PH_ACCEPTED := &"accepted"
const PH_STARTED := &"started"
const PH_PROGRESS := &"progress"
const PH_FINISHED := &"finished"
const PH_FAILED := &"failed"
const PH_CANCELLED := &"cancelled"
const TERMINAL: Array[StringName] = [PH_FINISHED, PH_FAILED, PH_CANCELLED]
## The causal chain, in order (inspect_state().causality[i].t keys). A stage that applies is
## stamped once, the first time it happens; `result` is the end of the run.
const CAUSAL_STAGES: Array[StringName] = [&"intent", &"anticipation", &"gesture", &"thread", &"hand",
	&"matter", &"result"]
## Timeline entries kept for the inspector.
const TIMELINE_MAX := 48
## Expected extra seconds a `wait` beat holds an action (estimate_duration), by condition, at
## tempo 1; measured on the runtime (tests/unit/test_animation_living_protocol.gd).
const WAIT_ESTIMATE := {&"arrived": 1.45, &"edited": 2.5, &"applied": 0.3}
## A user plan's first look starts within this many seconds of its perform (contract: 0.3 s).
const ACK_LATENCY := 0.3

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

var _task: Dictionary = {}
var _main: Dictionary = {}
var _overlay: Dictionary = {}
var _queue: Array[Dictionary] = []
var _overlay_queue: Array[Dictionary] = []
var _clock := 0.0
var _last_now := -1.0
var _phase := 0.0
## Body channels written by beats, per source.
var _gaze_beat: Array[Dictionary] = [{}, {}, {}]
var _turn_beat: Array[Dictionary] = [{}, {}, {}]
var _arm_specs: Array = [[{}, {}], [{}, {}], [{}, {}]]
var _breath_beat: Dictionary = {}
var _poses: Dictionary = {}
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
var _pending_target: StringName = &""
var _pending_at := 0.0
var _last_focus_kind: StringName = &""
var _focus := {"kind": &"miku", "points": PackedVector3Array(), "since": 0.0}
var _focus_since := 0.0
var _particle_clock := 0.0
var _energy_rr := 0
var _last_attention := &""
var _bound := false
var _last_mood: MikuMind.Mood = MikuMind.Mood.CALM
## Roteiro events received (inspection / tests).
var _events_seen := 0
## Causal timelines (inspect_state().causality), oldest first.
var _timeline: Array[Dictionary] = []


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
	add_to_group(INSPECT_GROUP)
	set_meta(&"audio_anchor", &"miku")
	body.add_to_group(SessionState.entity_group(ENTITY))
	body.set_meta(&"focus_bounds", AABB(Vector3(-1.0, -4.2, -0.8), Vector3(2.0, 6.0, 1.6)))
	if not Simulation.event_emitted.is_connected(_on_sim_event):
		Simulation.event_emitted.connect(_on_sim_event)
	_last_now = MotionClock.now()


func _exit_tree() -> void:
	if Simulation.event_emitted.is_connected(_on_sim_event):
		Simulation.event_emitted.disconnect(_on_sim_event)


# ================================================================== API


## Performs an action of the vocabulary. Returns false for an unknown action (no signal then).
## args.request_id (> 0: the InteractionRouter's request; 0 = her own) and args.step (index in
## the plan) correlate the action_event phases; exactly one terminal per accepted perform.
func perform(action: StringName, args := {}) -> bool:
	if not ActionScript.is_action(action):
		push_warning("Miku: unknown action %s" % action)
		return false
	_bind()
	_pending_target = &""
	var a := ActionScript.normalize(action, args, world_ids())
	var tag := _tag(action, a)
	_emit_phase(tag, PH_ACCEPTED, {"estimate": snappedf(estimate_duration(action, a), 0.01)})
	# A user plan's first look is the immediate acknowledgement: it never waits in a queue.
	var user_look := int(tag["request_id"]) > 0 and action in [ActionScript.LOOK_AT_USER, ActionScript.LOOK_AT_WORLD]
	# The perception of the user's call / pointing is already playing: the plan's look joins it
	# (finished when it ends) and an acknowledgement waits for it — the reaction is never cut.
	var reacting: bool = not _overlay.is_empty() and _overlay["action"] in [NOTICE, TARGET]
	if reacting and ((action == ActionScript.LOOK_AT_USER and _overlay["action"] == NOTICE)
			or (action == ActionScript.LOOK_AT_WORLD and _overlay["action"] == TARGET)):
		(_overlay["followers"] as Array).append(tag)
		_begin_tag(tag, &"follower")
		return true
	if action in ActionScript.OVERLAY or (user_look and not _main.is_empty()):
		if reacting and not user_look:
			_overlay_queue.append({"tag": tag, "args": a})
		else:
			_start_overlay(tag, a)
		return true
	if not _task.is_empty() and action in [ActionScript.FRUSTRATED, ActionScript.ANGRY, ActionScript.RECOVER]:
		_start_overlay(tag, a)
		return true
	if action == ActionScript.DISCARD and not _main.is_empty() \
			and _main["action"] in [ActionScript.EDIT_FILE, ActionScript.GRAB_FILE]:
		_finish_run(_main, SRC_MAIN, PH_CANCELLED, "discarded")
		_main = {}
	if _main.is_empty():
		_start_main(tag, a)
	else:
		_queue.append({"tag": tag, "args": a})
	return true


## Honest estimate (real seconds from now) of how long `action` with `args` would take if it were
## performed now: the wait for the channel it would join (the running action and the queue), its
## beats at her current tempo and the expected holds of its `wait` beats.
func estimate_duration(action: StringName, args := {}) -> float:
	if not ActionScript.is_action(action):
		return 0.0
	_bind()
	var a := ActionScript.normalize(action, args, world_ids())
	var own := _beats_estimate(_beats_for(action, a), 0.0, 0.0)
	var rid := int(a.get("request_id", 0))
	var user_look := rid > 0 and action in [ActionScript.LOOK_AT_USER, ActionScript.LOOK_AT_WORLD]
	var reacting: bool = not _overlay.is_empty() and _overlay["action"] in [NOTICE, TARGET]
	if reacting and ((action == ActionScript.LOOK_AT_USER and _overlay["action"] == NOTICE)
			or (action == ActionScript.LOOK_AT_WORLD and _overlay["action"] == TARGET)):
		return _run_remaining(_overlay)
	if action in ActionScript.OVERLAY or (user_look and not _main.is_empty()):
		if reacting and not user_look:
			var lead := _run_remaining(_overlay)
			for q: Dictionary in _overlay_queue:
				lead += _beats_estimate(_beats_for(q["tag"]["action"], q["args"]), 0.0, 0.0)
			return lead + own
		return own
	if not _task.is_empty() and action in [ActionScript.FRUSTRATED, ActionScript.ANGRY, ActionScript.RECOVER]:
		return own
	if _main.is_empty() or (action == ActionScript.DISCARD
			and _main["action"] in [ActionScript.EDIT_FILE, ActionScript.GRAB_FILE]):
		return own
	var wait := _run_remaining(_main)
	for q: Dictionary in _queue:
		wait += _beats_estimate(_beats_for(q["tag"]["action"], q["args"]), 0.0, 0.0)
	return wait + own


## Cancels every action of `request_id` — queued, running (main / overlay / joined look) and the
## work task it started — each ending with action_event(..., &"cancelled"); the hands it
## summoned dissolve (their threads relax) and its configuration artifact vanishes. Returns the
## number of actions cancelled.
func cancel(request_id: int) -> int:
	_bind()
	var n := 0
	for i in range(_queue.size() - 1, -1, -1):
		var q: Dictionary = _queue[i]
		if int(q["tag"]["request_id"]) == request_id:
			_queue.remove_at(i)
			_terminal(q["tag"], PH_CANCELLED, "cancelled")
			n += 1
	for i in range(_overlay_queue.size() - 1, -1, -1):
		var oq: Dictionary = _overlay_queue[i]
		if int(oq["tag"]["request_id"]) == request_id:
			_overlay_queue.remove_at(i)
			_terminal(oq["tag"], PH_CANCELLED, "cancelled")
			n += 1
	if not _overlay.is_empty():
		var fs: Array = _overlay["followers"]
		for i in range(fs.size() - 1, -1, -1):
			if int(fs[i]["request_id"]) == request_id:
				var f: Dictionary = fs[i]
				fs.remove_at(i)
				_terminal(f, PH_CANCELLED, "cancelled")
				n += 1
		if int(_overlay["tag"]["request_id"]) == request_id and _overlay["action"] in ActionScript.VOCABULARY:
			_finish_run(_overlay, SRC_OVERLAY, PH_CANCELLED, "cancelled")
			_overlay = {}
			n += 1
			_next_overlay()
	if not _main.is_empty() and int(_main["tag"]["request_id"]) == request_id:
		_finish_run(_main, SRC_MAIN, PH_CANCELLED, "cancelled")
		_main = {}
		n += 1
		_next_main()
	if not _task.is_empty() and int(_task["tag"]["request_id"]) == request_id:
		_finish_run(_task, SRC_TASK, PH_CANCELLED, "cancelled")
		_task = {}
	_release_request(request_id)
	return n


## The user called her (click on MIKU, "Miku, ..."): she reacts according to her state.
func notice_user() -> Dictionary:
	_bind()
	var r := mind.user_call()
	agenda.interrupt()
	_start_overlay_beats(_tag(NOTICE, {}), {"reaction": r["reaction"]}, ActionScript.user_reaction(r))
	return r


## The user pointed at a world: she looks at it and acknowledges at once; the work follows the
## interaction system's plan (LOOK_AT_WORLD, POINT, SUMMON_HANDS, WORK) or, if none arrives within
## PLAN_GRACE s, her own (POINT, then the work).
func target_world(id: StringName) -> bool:
	_bind()
	if worlds == null or not worlds.has_world(id):
		return false
	mind.user_points(id)
	agenda.interrupt()
	_start_overlay_beats(_tag(TARGET, {}), {"world": id}, ActionScript.world_target_reaction(id))
	_pending_target = id
	_pending_at = _clock + PLAN_GRACE
	return true


## Whole configuration (interaction system binding): personality and appearance, silently.
func apply_config(values: Dictionary) -> PackedStringArray:
	var changed := params.apply(values)
	body.set_appearance(params.appearance)
	_applied = true
	if not changed.is_empty():
		_appearance_changed = false
		for k in changed:
			if k.begins_with("appearance."):
				_appearance_changed = true
	return changed


## One validated change ("section.key", values as floats) applied by the interaction system
## after EDIT_FILE: the card shows the validation; her body / mind take the new value.
func on_config_changed(path: String, _old_value: Variant, new_value: Variant) -> void:
	var parts := path.split(".")
	if parts.size() != 2 or not (new_value is float or new_value is int):
		return
	var changed := params.apply({parts[0]: {parts[1]: float(new_value)}})
	body.set_appearance(params.appearance)
	_appearance_changed = parts[0] == "appearance"
	_applied = true
	artifact.edit_row = _config_row(path)
	if artifact.is_present():
		artifact.validate()
	if changed.is_empty():
		return


## State for the dev inspector (group `dev_inspect`).
func inspect_state() -> Dictionary:
	var hs := []
	for h in hands.active_hands() if hands != null else []:
		var ph := h as PuppetHand
		hs.append({"index": ph.index, "role": String(ph.get_meta(&"role", &"")), "pos": ph.global_position,
			"goal": ph.goal_pos, "pull": snappedf(ph.pull, 0.01), "presence": snappedf(ph.presence.y, 0.01),
			"error": snappedf(ph.error(), 0.01)})
	var ts := []
	if threads != null:
		for i in threads.threads.size():
			var c := threads.cycle(i)
			if c.is_alive():
				ts.append({"id": i, "phase": ThreadCycle.Phase.keys()[c.phase], "tension": snappedf(c.tension.y, 0.01),
					"presence": snappedf(c.presence.y, 0.01)})
	var ws := {}
	if worlds != null:
		for id: StringName in worlds.sites:
			var b := (worlds.sites[id] as WorkSite).build
			ws[id] = {"stage": b.stage_id(), "progress": snappedf(b.progress(), 0.01), "crack": snappedf(b.crack, 0.01),
				"imbalance": snappedf(b.imbalance, 0.01), "collapsed": snappedf(b.collapsed, 0.01)}
	return {"mood": mind.mood_id(), "composure": snappedf(mind.composure, 0.01),
		"frustration": snappedf(mind.frustration, 0.01), "arousal": snappedf(mind.arousal, 0.01),
		"attention": MikuMind.FOCUS_IDS[mind.focus_kind()], "attention_id": mind.focus_id(),
		"task": mind.task, "task_world": _task.get("world", &""), "action": current_action(),
		"overlay": _overlay.get("action", &""), "queue": _queue.size(), "micro": agenda.current,
		"hands": hs, "threads": ts, "worlds": ws, "artifact": artifact.state_id(),
		"camera_focus": _focus["kind"], "events": _events_seen, "rig": "mannequin" if body.using_fallback else "MikuRig",
		"body": body.inspect_state(), "clock": snappedf(_clock, 0.001), "causality": causality()}


## Causal timelines, oldest first: [{request_id, step, action, channel (main | overlay | follower
## | task), stage (work stage of a task entry, else ""), phase ("" while running, else the
## terminal), t: {intent, anticipation, gesture, thread, hand, matter, result} (game seconds of
## her clock, only the stages that happened)}]. A copy (safe to keep).
func causality() -> Array:
	var out := []
	for e in _timeline:
		out.append({"request_id": e["request_id"], "step": e["step"], "action": String(e["action"]),
			"channel": String(e["channel"]), "stage": String(e["stage"]), "phase": String(e["phase"]),
			"t": (e["t"] as Dictionary).duplicate()})
	return out


func world_ids() -> Array[StringName]:
	return LivingLayout.world_ids()


func mood() -> StringName:
	return mind.mood_id()


## Action running on the main channel (&"" when none).
func current_action() -> StringName:
	return _main.get("action", &"")


## True while a foreground action runs or waits (the background work does not count).
func is_busy() -> bool:
	return not _main.is_empty() or not _queue.is_empty()


## True while she works on a world (the task channel).
func is_working() -> bool:
	return not _task.is_empty()


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
	if _pending_target != &"" and _clock >= _pending_at:
		var id := _pending_target
		_pending_target = &""
		_start_task(id, {"point_first": true})
	if _main.is_empty():
		_step_run(_task, dt, SRC_TASK)
	_step_run(_main, dt, SRC_MAIN)
	_step_run(_overlay, dt, SRC_OVERLAY)
	_emit_mood()
	if not _main.is_empty() and _main["done"]:
		_finish_run(_main, SRC_MAIN)
		_main = {}
		_next_main()
	if not _task.is_empty() and _task["done"]:
		_finish_run(_task, SRC_TASK)
		_task = {}
	if not _overlay.is_empty() and _overlay["done"]:
		_finish_run(_overlay, SRC_OVERLAY)
		_overlay = {}
		_next_overlay()
	_idle_hands(dt)
	agenda.step(dt, mind, _agenda_context())
	_compose_body()
	body.step(dt)
	_drive_hands()
	hands.step(dt)
	_stamp_hands(_task)
	_stamp_hands(_main)
	_stamp_hands(_overlay)
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


# ================================================================== roteiro events


## `living.*` events of the Simulation (LivingScript): the work order and its outcomes. MIKU
## reacts; the events never pose her.
func _on_sim_event(e: SimEvent) -> void:
	var type := String(e.type)
	if not type.begins_with("living."):
		return
	_bind()
	_events_seen += 1
	var p := e.payload
	var world := StringName(str(p.get("world", work_world)))
	if not worlds.has_world(world):
		world = work_world
	match type:
		"living.hands":
			if not _task.is_empty():
				return
			var n := int(p.get("count", 0))
			if n <= 0:
				perform(ActionScript.DISCARD, {})
			elif n == 1:
				perform(ActionScript.SUMMON_HAND, {})
			else:
				perform(ActionScript.SUMMON_HANDS, {"count": n})
		"living.work_order":
			_start_task(world, {"events": true})
		"living.work_step":
			_task_event(world, WorkPlan.step_beats(int(p.get("step", 0)), int(p.get("attempt", 1)),
				int(p.get("hands", 2)), world, mind.mood == MikuMind.Mood.ANGRY or int(p.get("attempt", 1)) >= 3))
		"living.work_failed":
			_task_event(world, WorkPlan.fail_event_beats(int(p.get("attempt", 1)), world))
		"living.work_dismantled":
			_task_event(world, WorkPlan.dismantle_event_beats(int(p.get("hands", 6)), world))
		"living.work_recovered":
			_task_event(world, WorkPlan.recovered_event_beats(world, 2))
		"living.world_complete":
			_task_event(world, WorkPlan.complete_event_beats(world))


## Gives the task (started now if needed, in event mode) the beats of a roteiro event.
func _task_event(world: StringName, beats: Array[Dictionary]) -> void:
	if _task.is_empty() or StringName(_task["world"]) != world:
		_start_task(world, {"events": true})
	_replace_rest(_task, beats)


# ================================================================== runs


func _new_run(tag: Dictionary, args: Dictionary, beats: Array[Dictionary], channel: StringName) -> Dictionary:
	var sorted := beats.duplicate()
	sorted.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["t"]) < float(y["t"]))
	var world: StringName = args.get("world", work_world)
	if worlds != null and not worlds.has_world(world):
		world = work_world
	return {"action": tag["action"], "tag": tag, "args": args, "beats": sorted, "next": 0, "t": 0.0, "wait": 0.0,
		"done": false, "hands": [] as Array[PuppetHand], "world": world, "data": {}, "lead": _lead_for(world),
		"followers": [], "entry": _open_entry(tag, channel, &""), "failed": ""}


## Beats `action` would play now (pure: no side effect; WORK = the engagement on the main channel).
func _beats_for(action: StringName, args: Dictionary) -> Array[Dictionary]:
	if action == ActionScript.WORK:
		var has_world := args.has("world") and worlds.has_world(StringName(args["world"]))
		return _work_engage_beats(StringName(args["world"]) if has_world else work_world)
	if action == ActionScript.EDIT_FILE:
		return ActionScript.edit_beats(not artifact.is_present(), bool(args.get("keep", false)),
			bool(args.get("router", false)))
	return ActionScript.beats(action, args)


func _start_main(tag: Dictionary, args: Dictionary) -> void:
	var action: StringName = tag["action"]
	if action == ActionScript.WORK:
		_engage_work(tag, args)
	var beats := _beats_for(action, args)
	_main = _new_run(tag, args, beats, &"main")
	if action == ActionScript.EDIT_FILE or action == ActionScript.GRAB_FILE:
		_applied = false
	if action in [ActionScript.SUMMON_HAND, ActionScript.SUMMON_HANDS] and not args.has("role"):
		_adopt_idle_hands(_main)
	agenda.interrupt()
	_begin_tag(tag, &"main")


## The next queued foreground action starts (if any).
func _next_main() -> void:
	if _main.is_empty() and not _queue.is_empty():
		var q: Dictionary = _queue.pop_front()
		_start_main(q["tag"], q["args"])


func _next_overlay() -> void:
	if _overlay.is_empty() and not _overlay_queue.is_empty():
		var oq: Dictionary = _overlay_queue.pop_front()
		_start_overlay(oq["tag"], oq["args"])


## WORK on the main channel: start / switch / resume the task (the task belongs to WORK's request);
## the engagement beats (_work_engage_beats) end WORK once she is at it.
func _engage_work(tag: Dictionary, args: Dictionary) -> void:
	var has_world := args.has("world") and worlds.has_world(StringName(args["world"]))
	var world: StringName = StringName(args["world"]) if has_world else work_world
	if _task.is_empty():
		if has_world or not worlds.site(world).build.is_stable():
			_start_task(world, args, tag)
	elif StringName(_task["world"]) != world and has_world:
		_switch_task(world)


## She looks at the world and turns to it, so WORK finishes once she is at it.
func _work_engage_beats(world: StringName) -> Array[Dictionary]:
	var B := ActionScript
	return [B.b(0.0, &"gaze", {"at": &"world", "world": world, "secs": 1.0}),
		B.b(0.05, &"turn", {"at": &"world", "world": world, "amount": 0.4, "secs": 1.0}),
		B.b(0.7, &"done")]


## Starts the work on `world` (task channel). args: fail (planned failure), events (stages come
## from the roteiro), point_first (she points at it first). `tag`: the request that started it
## (WORK's), else her own.
func _start_task(world: StringName, args: Dictionary, tag := {}) -> void:
	if not _task.is_empty():
		if StringName(_task["world"]) == world:
			if args.get("events", false):
				_task["data"]["events"] = true
			return
		_switch_task(world)
		return
	work_world = world
	var beats: Array[Dictionary] = []
	if args.get("events", false):
		var B := ActionScript
		beats = [B.b(0.0, &"gaze", {"at": &"world", "world": world, "secs": 2.0}),
			B.b(0.0, &"turn", {"at": &"world", "world": world, "amount": 0.4, "secs": 999.0}),
			B.b(0.2, &"pose", {"lean": 0.06, "secs": 999.0, "key": &"stage"})]
	elif args.get("point_first", false):
		beats = _point_then_work(world)
	else:
		beats = [ActionScript.b(0.0, &"next_stage")]
	var t: Dictionary = tag if not tag.is_empty() else _tag(ActionScript.WORK, {})
	_task = _new_run(t, {"world": world}, beats, &"task")
	_task["data"]["fail"] = bool(args.get("fail", false))
	_task["data"]["events"] = bool(args.get("events", false))
	mind.begin_task(&"build", world)
	_adopt_idle_hands(_task)


func _start_overlay(tag: Dictionary, args: Dictionary) -> void:
	_start_overlay_beats(tag, args, ActionScript.beats(tag["action"], args))


func _start_overlay_beats(tag: Dictionary, args: Dictionary, beats: Array[Dictionary]) -> void:
	if not _overlay.is_empty():
		_finish_run(_overlay, SRC_OVERLAY, PH_CANCELLED, "preempted")
	_overlay = _new_run(tag, args, beats, &"overlay")
	_gaze_beat[SRC_OVERLAY] = {}
	_turn_beat[SRC_OVERLAY] = {}
	_begin_tag(tag, &"overlay")


## Ends a run: its channels are cleared and its owner (and the looks that joined it) get their
## terminal phase — `finished`, or `failed` when a critical wait timed out, or the given one.
func _finish_run(run: Dictionary, src: int, phase := PH_FINISHED, reason := "") -> void:
	if src == SRC_TASK:
		mind.end_task(false)
		for s in worlds.sites.values():
			(s as WorkSite).via = Vector3.INF
		_poses.erase(&"s_stage")
	_turn_beat[src] = {}
	_gaze_beat[src] = {}
	_arm_specs[src] = [{}, {}]
	var ph := phase
	var why := reason
	if ph == PH_FINISHED and String(run.get("failed", "")) != "":
		ph = PH_FAILED
		why = String(run["failed"])
	_close_entry(run["entry"], ph)
	# The task is a background channel (WORK's perform got its own terminal); internal overlays
	# (perception, the self-reaction) are not actions either (_terminal ignores them).
	if src != SRC_TASK:
		_terminal(run["tag"], ph, why)
	for f: Dictionary in run.get("followers", []):
		_terminal(f, ph, why)


# ================================================================== protocol & causality


## Correlation tag of one perform: {action, request_id, step, ended, entry}.
func _tag(action: StringName, args: Dictionary) -> Dictionary:
	return {"action": action, "request_id": maxi(int(args.get("request_id", 0)), 0), "step": int(args.get("step", 0)),
		"ended": false, "entry": {}}


func _emit_phase(tag: Dictionary, phase: StringName, info := {}) -> void:
	if not tag["action"] in ActionScript.VOCABULARY:
		return
	var i := info.duplicate()
	i["step"] = tag["step"]
	action_event.emit(int(tag["request_id"]), tag["action"], phase, i)


## The action starts now (channel: main, overlay or follower — a look that joins her reaction,
## already under way: its eyes are moving, so its anticipation is now).
func _begin_tag(tag: Dictionary, channel: StringName) -> void:
	if channel == &"follower":
		tag["entry"] = _open_entry(tag, channel, &"")
		_stamp_entry(tag["entry"], &"anticipation")
	_emit_phase(tag, PH_STARTED, {"channel": channel})
	if tag["action"] in ActionScript.VOCABULARY:
		action_started.emit(tag["action"])


## Exactly one terminal per accepted perform (idempotent).
func _terminal(tag: Dictionary, phase: StringName, reason: String) -> void:
	if tag.get("ended", false):
		return
	tag["ended"] = true
	_close_entry(tag["entry"], phase)
	if not tag["action"] in ActionScript.VOCABULARY:
		return
	var info := {}
	if reason != "":
		info["reason"] = reason
	_emit_phase(tag, phase, info)
	action_finished.emit(tag["action"])


func _open_entry(tag: Dictionary, channel: StringName, stage: StringName) -> Dictionary:
	var e := {"request_id": int(tag["request_id"]), "step": int(tag["step"]), "action": tag["action"],
		"channel": channel, "stage": stage, "phase": &"", "t": {&"intent": snappedf(_clock, 0.001)}}
	_timeline.append(e)
	if _timeline.size() > TIMELINE_MAX:
		_timeline.pop_front()
	return e


func _close_entry(e: Dictionary, phase: StringName) -> void:
	if e.is_empty() or e["phase"] != &"":
		return
	_stamp_entry(e, &"result")
	e["phase"] = phase


## Stamps causal stage `stage` of entry `e` (first time only, while the entry is open).
func _stamp_entry(e: Dictionary, stage: StringName) -> bool:
	if e.is_empty() or e["phase"] != &"" or (e["t"] as Dictionary).has(stage):
		return false
	e["t"][stage] = snappedf(_clock, 0.001)
	return true


## Stamps a stage of `run` and reports its progress to the owner of the action.
func _stamp(run: Dictionary, stage: StringName) -> void:
	if not _stamp_entry(run["entry"], stage):
		return
	var tag: Dictionary = run["tag"]
	if tag.get("ended", false) or run["entry"]["channel"] == &"task":
		return
	_emit_phase(tag, PH_PROGRESS, {"t": snappedf(_run_progress(run), 0.01), "stage": stage})


## Causal stage a beat op marks (anticipation, gesture, thread) or &"".
static func _op_stage(bt: Dictionary) -> StringName:
	match StringName(bt["op"]):
		&"gaze", &"breath":
			return &"anticipation"
		&"arm":
			var g: StringName = bt.get("g", &"rest")
			if g == Gestures.WINDUP:
				return &"anticipation"
			return &"" if g == &"rest" or g == Gestures.FREEZE else &"gesture"
		&"turn", &"pose", &"wave":
			return &"gesture"
		&"cast", &"pull":
			return &"thread"
	return &""


## `hand`: the first frame one of the run's hands answers the pull this run gave it.
func _stamp_hands(run: Dictionary) -> void:
	if run.is_empty() or not run["data"].get("pulled", false) or (run["entry"]["t"] as Dictionary).has(&"hand"):
		return
	for h: PuppetHand in run["hands"]:
		# Moving under the pull, or holding its place with it (already there: it works now).
		if is_instance_valid(h) and h.active and h.pull > HandDynamics.SLACK \
				and (h.speed() > 0.05 or (h.presence.y > 0.6 and h.error() < WORK_DIST)):
			_stamp(run, &"hand")
			return


## 0..1 progress of a run through its beats.
func _run_progress(run: Dictionary) -> float:
	var end := _beats_end(run["beats"])
	return clampf(float(run["t"]) / end, 0.0, 1.0) if end > 0.0 else 0.0


static func _beats_end(beats: Array) -> float:
	var end := 0.0
	for x: Dictionary in beats:
		end = maxf(end, float(x["t"]))
	return end


## Real seconds `beats` take from beat time `from` at her current tempo, plus the expected holds of
## their waits not passed yet (`waited` = seconds already spent in the current wait).
func _beats_estimate(beats: Array, from: float, waited: float) -> float:
	var end := _beats_end(beats)
	var tempo := maxf(mind.tempo(), 0.1)
	var holds := 0.0
	for x: Dictionary in beats:
		if x["op"] != &"wait" or float(x["t"]) < from:
			continue
		var exp_s := float(WAIT_ESTIMATE.get(StringName(x.get("until", &"")), 0.5)) / sqrt(tempo)
		holds += minf(exp_s, float(x.get("timeout", 5.0)))
	return maxf(end - from, 0.0) / tempo + maxf(holds - waited, 0.0)


func _run_remaining(run: Dictionary) -> float:
	if run.is_empty():
		return 0.0
	return _beats_estimate(run["beats"], float(run["t"]), float(run["wait"]))


## Dissolves what belonged to a cancelled request: the hands it summoned (their threads relax)
## and the configuration artifact it called.
func _release_request(request_id: int) -> void:
	for h in hands.active_hands():
		if int(h.get_meta(&"request_id", -1)) != request_id or h.goal_presence <= 0.0:
			continue
		threads.relax_hand(h)
		hands.release(h)
		for run: Dictionary in [_task, _main, _overlay]:
			if run.is_empty():
				continue
			(run["hands"] as Array).erase(h)
			var places: Dictionary = run["data"].get("places", {})
			places.erase(h)
	if artifact.is_present() and int(artifact.get_meta(&"request_id", -1)) == request_id:
		artifact.vanish()


func _step_run(run: Dictionary, dt: float, src: int) -> void:
	if run.is_empty() or run["done"]:
		return
	run["t"] = float(run["t"]) + dt * mind.tempo()
	if src == SRC_TASK:
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
				# A wait the action cannot do without timed out: it goes on, and ends as failed.
				if bool(bt.get("critical", false)) and String(run["failed"]) == "":
					run["failed"] = "timeout:%s" % String(bt.get("until", &""))
			run["wait"] = 0.0
			run["next"] = int(run["next"]) + 1
			continue
		run["next"] = int(run["next"]) + 1
		_op(run, bt, src)
		if run["done"]:
			return
		beats = run["beats"]
	# A task driven by the roteiro waits for its next event; others end with their beats.
	if int(run["next"]) >= (run["beats"] as Array).size():
		if not (src == SRC_TASK and run["data"].get("events", false)):
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
	run["wait"] = 0.0


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


func _switch_task(id: StringName) -> void:
	_task["data"]["switch_to"] = id


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
	data["events"] = false
	data["furious"] = false
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
		&"layer":
			var k := int(bt.get("layer", 0))
			return site.build.layers[clampi(k, 0, WorldBuild.LAYER_COUNT - 1)] >= 1.0
		&"repaired":
			return site.build.crack <= float(run["data"].get("repair_limit", 0.0)) + 0.002
		&"dismantled":
			var down: int = run["data"].get("dismantle_floor", WorldBuild.LAYER_COUNT)
			if down >= WorldBuild.LAYER_COUNT:
				return site.build.core <= 0.0
			return site.build.layers[down] <= 0.0
		&"edited":
			return artifact.edit_done()
		&"applied":
			return _applied
	return true


# ================================================================== ops


func _op(run: Dictionary, bt: Dictionary, src: int) -> void:
	var op: StringName = bt["op"]
	var world: StringName = bt.get("world", run["world"])
	if op == &"stage" and src == SRC_TASK:
		# Each stage of the work is its own causal sentence (a new timeline entry).
		_close_entry(run["entry"], PH_FINISHED)
		run["entry"] = _open_entry(run["tag"], &"task", StringName(WorldBuild.Stage.keys()[bt.get("s", 0)]))
		run["data"].erase("pulled")
	var stage := _op_stage(bt)
	if stage != &"":
		_stamp(run, stage)
	if op == &"pull":
		run["data"]["pulled"] = true
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
			var key := StringName(["s_", "o_", "m_"][src] + String(bt.get("key", &"beat")))
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
			_op_summon(run, bt, world)
		&"cast":
			_op_cast(run, bt, src)
		&"pull":
			var drive := lerpf(1.0, 1.9, mind.rigidity() * params.value(&"behaviour", "aggression_peak") / 0.7)
			var lead: int = run["lead"]
			for h in _run_hands(run, bt):
				h.drive = drive
				# Nothing pulls without a thread: a hand whose thread has faded gets a new one.
				if not threads.has_live_thread(h):
					threads.cast(lead, 1, h, -1, 0.0, mind.tempo())
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
			_op_release(run, bool(bt.get("all", false)), int(bt.get("keep", 0)))
		&"stage":
			var site := worlds.site(world)
			var s: WorldBuild.Stage = bt.get("s", WorldBuild.Stage.GATHER)
			if site.build.stage != s:
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
			_op_fault(bt, world)
		&"repair":
			run["data"]["repair"] = {"rate": float(bt.get("rate", 0.2))}
			run["data"]["repair_limit"] = float(bt.get("limit", 0.0))
		&"dismantle":
			worlds.site(world).build.begin_dismantle()
			run["data"]["dismantle"] = {"rate": float(bt.get("rate", 0.5))}
			run["data"]["dismantle_floor"] = int(bt.get("down_to", WorldBuild.LAYER_COUNT))
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
	# Lost composure: no open-palm courtesies; the arm stays where her control needs it.
	if g == Gestures.PALM_UP and src == SRC_OVERLAY and mind.mood == MikuMind.Mood.ANGRY:
		return
	for s in _sides(run, StringName(bt.get("side", &"lead")), src):
		var specs: Array = _arm_specs[src]
		if g == &"rest":
			specs[s] = {}
			continue
		specs[s] = {"g": g, "at": bt.get("at", &"world"), "world": world, "speed": float(bt.get("speed", 1.0)),
			"until": _clock + float(bt.get("secs", 1.0e9)), "rhythm": bool(bt.get("rhythm", false)) or (g == Gestures.CONDUCT \
				and bt.has("sway")), "run": run}


func _op_summon(run: Dictionary, bt: Dictionary, world: StringName) -> void:
	var n := int(bt.get("n", 1))
	var near := StringName(bt.get("near", &"miku"))
	var role := StringName(bt.get("role", &""))
	var list: Array[PuppetHand] = run["hands"]
	if not bt.get("fresh", false):
		_adopt_idle_hands(run)
	var lead_left: bool = int(run["lead"]) == 0
	var basis := body.body_basis()
	if bt.get("trim", false):
		# A step that asks for fewer hands lets the others go (they dissolve where they are).
		while list.size() > n:
			var extra: PuppetHand = list.pop_back()
			threads.relax_hand(extra)
			hands.release(extra)
	var added := 0
	var target := n if not bt.get("fresh", false) else _count_role(list, role) + n
	var have := list.size() if not bt.get("fresh", false) else _count_role(list, role)
	while have < target:
		var h := hands.acquire(added % 2 == 1)
		var at := Vector3.ZERO
		var k := float(list.size())
		if near == &"world":
			var site := worlds.site(world)
			at = body.chest_position().lerp(site.global_position, 0.55) + basis.y * (0.9 + 0.25 * k) \
				+ basis.x * (sin(k * 2.1) * 1.2)
		else:
			at = global_transform * LivingLayout.summon_point(list.size(), lead_left)
		var face := (body.chest_position() - at).normalized()
		h.summon(at, basis.y, -face, &"relaxed")
		h.set_meta(&"role", role)
		h.set_meta(&"request_id", int(run["tag"]["request_id"]))
		list.append(h)
		added += 1
		have += 1


func _count_role(list: Array[PuppetHand], role: StringName) -> int:
	var n := 0
	for h in list:
		if h.get_meta(&"role", &"") == role:
			n += 1
	return n


func _op_cast(run: Dictionary, bt: Dictionary, src: int) -> void:
	var extra := int(bt.get("extra", 0))
	var speed := mind.tempo()
	var lead: int = run["lead"]
	var k := 0
	var forced: Array[int] = []
	if bt.has("side"):
		forced = _sides(run, StringName(bt["side"]), src)
	for h in _run_hands(run, bt):
		var alive := false
		for t in threads.threads:
			if t["hand"] == h and (t["cycle"] as ThreadCycle).is_alive():
				alive = true
		if alive:
			k += 1
			continue
		var side := lead if k % 2 == 0 else 1 - lead
		if not forced.is_empty():
			side = forced[0]
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
	var furious := mind.mood == MikuMind.Mood.ANGRY
	var lead_sx := 1.0 if int(run["lead"]) == 0 else -1.0
	for i in n:
		var h: PuppetHand = list[i]
		var place := StringName(bt.get("place", &"work"))
		var pos := Vector3.ZERO
		var point := Vector3.FORWARD
		var palm := Vector3.DOWN
		var pose: StringName = &"open"
		var spread := (float(i) - float(n - 1) * 0.5)
		match place:
			&"present", &"hover":
				# At her sides, never before her: alternating sides from her lead, rising in rows.
				var side_x := lead_sx * (1.0 if i % 2 == 0 else -1.0)
				var row := float(i / 2)
				pos = body.chest_position() + basis.x * side_x * (2.1 + row * 1.25) + basis.z * (1.3 + row * 0.3) \
					+ basis.y * (0.5 + row * 0.55)
				if place == &"hover":
					pos += basis.y * 0.6 - basis.z * 0.4
				palm = (-basis.x * side_x * 0.8 - basis.z * 0.2).normalized()
				point = (basis.y * 0.9 + basis.z * 0.2).normalized()
				pose = &"open" if place == &"present" else &"relaxed"
			&"ready":
				var sx := 1.0 if h.left else -1.0
				pos = body.chest_position() + basis.x * sx * 1.6 + basis.z * 1.0 + basis.y * 0.3
				palm = (-basis.x * sx * 0.7 - basis.z * 0.3).normalized()
				point = (basis.y * 0.8 + basis.z * 0.4).normalized()
				pose = &"relaxed"
			&"work", &"approach":
				var d := float(bt.get("dist", 1.55 if place == &"work" else 2.4))
				var wp := LivingLayout.work_place(site.global_position, site.radius, i, n, d)
				pos = wp[0]
				point = wp[1]
				palm = wp[2]
				pose = _stage_pose(stage, furious) if place == &"work" else &"relaxed"
			&"crack":
				var cp := site.crack_point()
				var cn := (cp - site.global_position).normalized()
				var lat := cn.cross(Vector3.UP).normalized()
				pos = cp + cn * site.radius * float(bt.get("dist", 0.8)) + lat * spread * site.radius * 0.9
				palm = -cn
				point = (Vector3.UP * 0.6 + lat * (0.4 if i % 2 == 0 else -0.4)).normalized()
				pose = &"smooth"
			&"card_hold":
				var spot := _target(run, &"file_spot", world)
				pos = spot + Vector3.DOWN * ConfigArtifact.HOLD_OFFSET
				palm = Vector3.UP
				point = (basis.z * 0.8 - basis.x * 0.3).normalized()
				pose = &"hold"
			&"card_edit":
				var spot2 := artifact.global_position if artifact.is_present() else _target(run, &"file_spot", world)
				var side := basis.x * lead_sx
				pos = spot2 + side * 0.75 + basis.z * 0.35 + Vector3.UP * 0.1
				palm = -side
				point = (-side * 0.6 + basis.z * -0.2 + Vector3.UP * 0.2).normalized()
				pose = &"point"
		places[h] = {"pos": pos, "point": point, "palm": palm, "pose": pose, "kind": place}
		h.set_goal(pos, point, palm, pose)
	run["data"]["places"] = places


func _op_release(run: Dictionary, all: bool, keep: int) -> void:
	var list: Array[PuppetHand] = []
	if all:
		list = hands.active_hands()
	else:
		list = (run["hands"] as Array[PuppetHand]).duplicate()
	var kept: Array[PuppetHand] = []
	for h in list:
		if kept.size() < keep and (run["hands"] as Array).has(h):
			kept.append(h)
			continue
		threads.relax_hand(h)
		hands.release(h)
	var mine: Array[PuppetHand] = run["hands"]
	mine.clear()
	mine.append_array(kept)
	if run["data"].has("places"):
		var places: Dictionary = run["data"]["places"]
		for h: PuppetHand in places.keys():
			if not kept.has(h):
				places.erase(h)


func _op_fault(bt: Dictionary, world: StringName) -> void:
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
			artifact.set_meta(&"request_id", int(run["tag"]["request_id"]))
			_applied = false
		&"held":
			var holder: PuppetHand = null
			for h in hands.active_hands():
				if h.get_meta(&"role", &"") == &"holder":
					holder = h
			if holder == null and not (run["hands"] as Array).is_empty():
				holder = (run["hands"] as Array)[0]
			if holder != null:
				artifact.hold(holder)
				_stamp(run, &"matter")
		&"edit":
			artifact.begin_edit()
			_stamp(run, &"matter")
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


## Hands of the run (including hands with a role summoned by another action), filtered by beat
## args `only` (role) / `only_index`.
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
		for h in hands.active_hands():
			if h.get_meta(&"role", &"") == bt["only"] and h.goal_presence > 0.0:
				out.append(h)
				if not list.has(h):
					list.append(h)
		return out
	return list


## Hands already out and not used by another run join this run (continuity: the hands she
## summoned keep serving her). Hands with a role (configuration) are left to their action.
func _adopt_idle_hands(run: Dictionary) -> void:
	var list: Array[PuppetHand] = run["hands"]
	for h in hands.active_hands():
		if h.goal_presence <= 0.0 or list.has(h) or h.get_meta(&"role", &"") != &"":
			continue
		var used := false
		for other in [_task, _main, _overlay]:
			if not is_same(other, run) and not other.is_empty() and (other["hands"] as Array).has(h):
				used = true
		if not used:
			list.append(h)


func _drive_hands() -> void:
	for h in hands.hands:
		if h.active:
			h.pull = threads.tension_on(h)
	_drive_run_hands(_task)
	_drive_run_hands(_main)


func _drive_run_hands(run: Dictionary) -> void:
	if run.is_empty():
		return
	var data: Dictionary = run["data"]
	var places: Dictionary = data.get("places", {})
	var mirror: Dictionary = data.get("mirror", {})
	var mirroring := not mirror.is_empty() and _clock < float(mirror["until"])
	if is_same(run, _task) and not _main.is_empty():
		mirroring = false
	var site := worlds.site(StringName(run["world"]))
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
			pos += basis.x * sin(_clock * 7.0) * 0.07 + Vector3.UP * (0.12 - artifact.edit * 0.3) \
				+ basis.z * cos(_clock * 7.0) * 0.03
		h.set_goal(pos, p["point"], p["palm"], p["pose"])


func _drive_work(dt: float) -> void:
	_particle_clock += dt
	if _task.is_empty() or not _main.is_empty():
		return
	var data: Dictionary = _task["data"]
	if not (data.has("work") or data.has("repair") or data.has("dismantle")):
		return
	var site := worlds.site(StringName(_task["world"]))
	var list: Array[PuppetHand] = _task["hands"]
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
	if k > 0.05:
		_stamp(_task, &"matter")
	if data.has("work"):
		site.build.work(float(data["work"]["rate"]) * dt * k)
	if data.has("repair"):
		var amount := float(data["repair"]["rate"]) * dt * k
		var limit := float(data.get("repair_limit", 0.0))
		site.build.crack = maxf(site.build.crack - amount, limit)
		site.build.imbalance = maxf(site.build.imbalance - amount, 0.0)
		site.build.energy = minf(site.build.energy + amount * 2.0, 1.0)
	if data.has("dismantle"):
		site.build.dismantle(float(data["dismantle"]["rate"]) * dt * k, int(data.get("dismantle_floor", WorldBuild.LAYER_COUNT)))
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
	if not _main.is_empty() or not _queue.is_empty() or not _task.is_empty() or hands.active_count() == 0:
		_hand_idle = 0.0
		return
	_hand_idle += dt
	if _hand_idle >= HAND_IDLE_RELEASE:
		_hand_idle = 0.0
		perform(ActionScript.DISCARD, {})


# ================================================================== body


func _agenda_context() -> Dictionary:
	var working := not _task.is_empty()
	var site := worlds.site(work_world)
	return {"working": working, "hands": hands.active_count(), "failed": site != null and site.build.is_broken(),
		"busy": not _main.is_empty()}


## Highest-priority arm spec of side s (expired ones are dropped).
func _spec(s: int) -> Dictionary:
	for src in PRIORITY:
		var specs: Array = _arm_specs[src]
		var sp: Dictionary = specs[s]
		if sp.is_empty():
			continue
		if _clock > float(sp["until"]):
			specs[s] = {}
			continue
		# A suspended task does not drive the arms.
		if src == SRC_TASK and not _main.is_empty():
			continue
		return sp
	return {}


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
		var spec := _spec(s)
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
			at = _target({}, &"world", work_world)
			if micro_g != &"":
				g = micro_g
				ph = mp * TAU
		if g == Gestures.FREEZE:
			continue
		Gestures.goal(g, body.shoulder(s), body.arm_reach(s), at, basis, 1.0 if s == 0 else -1.0, ph,
			body.chest_position(), body.head_position(), _goal)
		body.set_arm(s, _goal.pos, _goal.palm, _goal.point, _goal.pole, _goal.pose, speed * _goal.speed)
		_finger_wave(s, micro, busy)


func _micro_arm(s: int, micro: StringName) -> StringName:
	match micro:
		MicroAgenda.OBSERVE_HAND:
			return Gestures.SELF if s == _free_side() and hands.active_count() == 0 else &""
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
	for src in PRIORITY:
		var g: Dictionary = _gaze_beat[src]
		if g.is_empty():
			continue
		if _clock > float(g["until"]):
			_gaze_beat[src] = {}
			continue
		if src == SRC_TASK and not _main.is_empty():
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
	for src in PRIORITY:
		var t: Dictionary = _turn_beat[src]
		if t.is_empty():
			continue
		if _clock > float(t["until"]):
			_turn_beat[src] = {}
			continue
		if src == SRC_TASK and not _main.is_empty():
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


## The arm no channel uses (else the one away from the work).
func _free_side() -> int:
	for s in 2:
		if _spec(s).is_empty():
			return s
	return 1 - _lead_for(work_world)


func _sides(run: Dictionary, side: StringName, src: int) -> Array[int]:
	var lead: int = run.get("lead", 1)
	match side:
		&"both":
			return [0, 1]
		&"other":
			return [1 - lead]
		&"left":
			return [0]
		&"right":
			return [1]
		&"free":
			for s in 2:
				var used := false
				for other in [SRC_MAIN, SRC_TASK]:
					if other != src and not (_arm_specs[other][s] as Dictionary).is_empty():
						used = true
				if not used:
					return [s]
			return []
	return [lead]


func _other_world(id: StringName) -> StringName:
	var ids := LivingLayout.world_ids()
	var i := ids.find(id)
	return ids[(i + 1 + int(_clock / 9.0) % (ids.size() - 1)) % ids.size()] if i >= 0 else ids[1]


## Line of the configuration artifact for a property path (sections on lines 0, 4, 8 and their
## keys below them — the art-director's config_artifact layout).
static func _config_row(path: String) -> int:
	var parts := path.split(".")
	var section := ["identity", "appearance", "behaviour"].find(parts[0])
	if section < 0 or parts.size() < 2:
		return 1
	var keys: Array = [MikuParams.IDENTITY_DEFAULTS.keys(), MikuParams.APPEARANCE_DEFAULTS.keys(),
		MikuParams.BEHAVIOUR_DEFAULTS.keys()][section]
	return section * 4 + 1 + clampi(keys.find(parts[1]), 0, 2)


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
	var working := not _task.is_empty() and _main.is_empty()
	var n_hands := hands.active_count()
	# The push-in on her face when composure frays or returns; the rage itself is shown wide (her
	# many hands, the torn world): the camera opens instead of closing in.
	if (m == MikuMind.Mood.FRUSTRATED and t_mood < 1.8) or (m == MikuMind.Mood.RECOVERING and t_mood < 3.0):
		kind = &"emotion"
	elif m == MikuMind.Mood.ANGRY:
		kind = &"wide"
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
			and kind != &"emotion" and kind != &"user" and m != MikuMind.Mood.ANGRY:
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
