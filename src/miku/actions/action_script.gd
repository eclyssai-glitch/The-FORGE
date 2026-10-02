class_name ActionScript
extends RefCounted
## How each action of the vocabulary is PERFORMED (Loop 5). Owner: animator. Pure.
## An action is a list of beats {t (s at tempo 1), op, ...args} that Miku executes in order,
## at the speed of her mood (MikuMind.tempo()). Ops are the runtime's vocabulary of intention:
## look (gaze/attend/turn), body (pose/breath/arm/wave), hands (summon/cast/pull/send/mirror/
## relax/release), world (stage/work/fault/repair/dismantle), mind (fail/success/mood),
## file (artifact/commit) and `wait` (blocks the beats after it until a condition holds or
## its timeout passes). The order of beats IS the causal chain:
## intention -> anticipation (windup) -> gesture -> thread (cast) -> pull -> hand (send) -> matter.
## Providers never see this: they only name actions of VOCABULARY (ADR-016).

const LOOK_AT_USER := &"LOOK_AT_USER"
const LOOK_AT_WORLD := &"LOOK_AT_WORLD"
const ACKNOWLEDGE := &"ACKNOWLEDGE"
const THINK := &"THINK"
const WORK := &"WORK"
const INSPECT := &"INSPECT"
const SUMMON_HAND := &"SUMMON_HAND"
const SUMMON_HANDS := &"SUMMON_HANDS"
const GRAB_FILE := &"GRAB_FILE"
const EDIT_FILE := &"EDIT_FILE"
const POINT := &"POINT"
const DISCARD := &"DISCARD"
const FRUSTRATED := &"FRUSTRATED"
const ANGRY := &"ANGRY"
const RECOVER := &"RECOVER"
const SATISFIED := &"SATISFIED"

const VOCABULARY: Array[StringName] = [LOOK_AT_USER, LOOK_AT_WORLD, ACKNOWLEDGE, THINK, WORK, INSPECT,
	SUMMON_HAND, SUMMON_HANDS, GRAB_FILE, EDIT_FILE, POINT, DISCARD, FRUSTRATED, ANGRY, RECOVER, SATISFIED]
## Actions that only use the eyes, head and one free arm: they play over a running action
## (the overlay channel) instead of waiting for it.
const OVERLAY: Array[StringName] = [LOOK_AT_USER, ACKNOWLEDGE]

## Ops (documentation and validation).
const OPS: Array[StringName] = [&"gaze", &"attend", &"turn", &"pose", &"breath", &"arm", &"wave",
	&"summon", &"cast", &"pull", &"send", &"mirror", &"relax", &"release", &"stage", &"work", &"work_stop",
	&"fault", &"repair", &"dismantle", &"success", &"mood", &"artifact", &"commit", &"self_react",
	&"wait", &"next_stage", &"particles", &"done"]


static func is_action(a: StringName) -> bool:
	return VOCABULARY.has(a)


static func b(t: float, op: StringName, args := {}) -> Dictionary:
	var d := args.duplicate()
	d["t"] = t
	d["op"] = op
	return d


## Beats of `action` with `args` (WORK's stages come from WorkPlan as the work goes).
static func beats(action: StringName, args: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at: StringName = args.get("world", &"")
	match action:
		LOOK_AT_USER:
			out = [b(0.0, &"gaze", {"at": &"user", "secs": 2.4}), b(0.0, &"attend", {"kind": &"user", "secs": 2.4}),
				b(0.15, &"turn", {"at": &"user", "amount": 0.35, "secs": 2.4}),
				b(0.3, &"pose", {"tilt": 0.07, "lift": 0.1, "secs": 2.2}), b(2.5, &"done")]
		LOOK_AT_WORLD:
			out = [b(0.0, &"gaze", {"at": &"world", "world": at, "secs": 2.6}),
				b(0.0, &"attend", {"kind": &"world", "world": at, "secs": 2.6}),
				b(0.2, &"turn", {"at": &"world", "world": at, "amount": 0.55, "secs": 2.6}),
				b(0.35, &"pose", {"lean": 0.05, "secs": 2.2}), b(2.7, &"done")]
		ACKNOWLEDGE:
			out = [b(0.0, &"pose", {"nod": 0.17, "secs": 0.4}), b(0.45, &"pose", {"nod": -0.03, "lift": 0.08, "secs": 0.5}),
				b(0.1, &"arm", {"side": &"free", "g": Gestures.PALM_UP, "at": &"user", "secs": 1.2}),
				b(1.3, &"done")]
		THINK:
			out = [b(0.0, &"gaze", {"at": &"think", "secs": 3.0}), b(0.15, &"arm", {"side": &"lead", "g": Gestures.CHIN, "secs": 2.8}),
				b(0.4, &"wave", {"side": &"lead", "kind": &"tap", "secs": 2.2}),
				b(0.2, &"pose", {"tilt": 0.11, "lean": 0.03, "nod": 0.06, "secs": 2.8}),
				b(0.1, &"breath", {"depth": 1.4, "rate": 0.85, "secs": 3.0}), b(3.1, &"done")]
		INSPECT:
			out = [b(0.0, &"gaze", {"at": &"world", "world": at, "scan": true, "secs": 2.8}),
				b(0.0, &"attend", {"kind": &"work", "world": at, "secs": 2.8}),
				b(0.1, &"turn", {"at": &"world", "world": at, "amount": 0.45, "secs": 2.8}),
				b(0.25, &"pose", {"lean": 0.16, "tilt": 0.12, "secs": 2.5}),
				b(0.5, &"arm", {"side": &"lead", "g": Gestures.PINCH, "at": &"world", "world": at, "speed": 0.8, "secs": 2.2}),
				b(2.9, &"done")]
		SUMMON_HAND, SUMMON_HANDS:
			var n: int = 1 if action == SUMMON_HAND else int(args.get("count", 2))
			out = summon_beats(n, bool(args.get("release", false)))
		POINT:
			out = [b(0.0, &"gaze", {"at": &"world", "world": at, "secs": 2.6}),
				b(0.0, &"attend", {"kind": &"world", "world": at, "secs": 2.6}),
				b(0.05, &"turn", {"at": &"world", "world": at, "amount": 0.5, "secs": 3.0}),
				b(0.15, &"arm", {"side": &"lead", "g": Gestures.WINDUP, "at": &"world", "world": at, "secs": 0.4}),
				b(0.55, &"arm", {"side": &"lead", "g": Gestures.POINT, "at": &"world", "world": at, "speed": 1.3, "secs": 1.9}),
				b(0.6, &"pose", {"lean": 0.05, "lift": 0.1, "secs": 1.6}), b(2.6, &"done")]
		GRAB_FILE:
			out = grab_beats()
			out.append(b(out[out.size() - 1]["t"] + 0.1, &"done"))
		EDIT_FILE:
			out = edit_beats(not bool(args.get("held", false)), bool(args.get("keep", false)))
		DISCARD:
			out = [b(0.0, &"gaze", {"at": &"file", "secs": 1.4}),
				b(0.05, &"arm", {"side": &"lead", "g": Gestures.WINDUP, "at": &"file", "secs": 0.3}),
				b(0.35, &"arm", {"side": &"lead", "g": Gestures.FLICK, "at": &"file", "speed": 1.6, "secs": 1.0}),
				b(0.5, &"artifact", {"state": &"reject" if args.get("rejected", false) else &"vanish"}),
				b(0.5, &"relax", {"all": true}), b(0.7, &"release", {"all": true})]
			if args.get("rejected", false):
				out.append(b(0.6, &"pose", {"tilt": -0.06, "nod": -0.04, "secs": 0.6}))
				out.append(b(1.2, &"pose", {"tilt": 0.06, "secs": 0.6}))
			out.append(b(1.6, &"done"))
		FRUSTRATED:
			out = [b(0.0, &"mood", {"to": &"frustrated"}), b(0.1, &"breath", {"depth": 0.55, "rate": 1.6, "secs": 3.0}),
				b(0.1, &"pose", {"raise": 0.6, "lean": 0.06, "secs": 3.0}),
				b(0.3, &"wave", {"side": &"free", "kind": &"tap", "secs": 2.4}),
				b(0.5, &"pose", {"tilt": -0.07, "secs": 0.35}), b(0.9, &"pose", {"tilt": 0.07, "secs": 0.35}),
				b(3.1, &"done")]
		ANGRY:
			out = [b(0.0, &"mood", {"to": &"angry"}), b(0.0, &"breath", {"depth": 0.12, "rate": 1.2, "secs": 2.5}),
				b(0.0, &"pose", {"raise": 0.35, "nod": 0.07, "secs": 2.6}),
				b(0.35, &"arm", {"side": &"both", "g": Gestures.CLAW, "at": &"world", "world": at, "secs": 2.0}),
				b(2.6, &"done")]
		RECOVER:
			out = recover_beats()
		SATISFIED:
			out = [b(0.0, &"success", {"mag": 0.5}), b(0.0, &"breath", {"depth": 1.9, "rate": 0.75, "secs": 3.0}),
				b(0.1, &"pose", {"lift": 0.35, "tilt": 0.1, "raise": -0.15, "secs": 2.6}),
				b(0.2, &"gaze", {"at": &"world", "world": at, "secs": 2.6}),
				b(0.3, &"arm", {"side": &"both", "g": Gestures.PALM_UP, "at": &"world", "world": at, "speed": 0.7, "secs": 2.0}),
				b(2.8, &"done")]
		WORK:
			out = [b(0.0, &"next_stage")]
	return out


## Summoning n hands: anticipation, the call, threads cast from her fingers, the hands form at
## the threads' ends, the pull brings them before her, then they follow her conducting hand
## (mirror) — proof of control — and the threads relax. They stay (hovering) unless `release`.
static func summon_beats(n: int, release: bool) -> Array[Dictionary]:
	var both := n > 1
	var out: Array[Dictionary] = [
		b(0.0, &"gaze", {"at": &"summon", "secs": 1.6}),
		b(0.0, &"attend", {"kind": &"hand", "secs": 6.0}),
		b(0.0, &"arm", {"side": &"lead", "g": Gestures.WINDUP, "at": &"summon"}),
		b(0.0, &"breath", {"depth": 1.5, "rate": 1.0, "secs": 1.2}),
		b(0.5, &"arm", {"side": &"lead", "g": Gestures.CALL, "at": &"summon", "speed": 1.2}),
		b(0.55, &"wave", {"side": &"lead", "kind": &"beckon", "secs": 1.2}),
		b(0.62, &"summon", {"n": n, "near": &"miku"}),
		b(0.62, &"cast", {"force": 0.0}),
		b(0.7, &"gaze", {"at": &"hands", "secs": 4.5}),
		b(1.15, &"pull", {"force": 0.55}),
		b(1.15, &"send", {"place": &"present"}),
		b(1.2, &"wait", {"until": &"arrived", "timeout": 4.0}),
		b(1.25, &"arm", {"side": &"lead", "g": Gestures.CONDUCT, "at": &"hands"}),
		b(1.3, &"mirror", {"gain": 3.2, "secs": 3.4}),
		b(1.35, &"arm", {"side": &"lead", "g": Gestures.CONDUCT, "at": &"hands", "sway": 0.7, "secs": 3.2}),
		b(4.7, &"relax", {}),
		b(4.8, &"arm", {"side": &"lead", "g": &"rest"}),
	]
	if both:
		out.append(b(0.1, &"arm", {"side": &"other", "g": Gestures.WINDUP, "at": &"summon"}))
		out.append(b(0.6, &"arm", {"side": &"other", "g": Gestures.CALL, "at": &"summon", "speed": 1.1}))
		out.append(b(4.9, &"arm", {"side": &"other", "g": &"rest"}))
	if release:
		out.append(b(5.4, &"release", {}))
	out.append(b(5.6, &"done"))
	return out


## The configuration artifact is called into being over her raised palm; a puppet hand is
## summoned (thread) and takes it.
static func grab_beats() -> Array[Dictionary]:
	return [
		b(0.0, &"gaze", {"at": &"file_spot", "secs": 2.2}),
		b(0.0, &"attend", {"kind": &"file", "secs": 6.0}),
		b(0.0, &"arm", {"side": &"lead", "g": Gestures.WINDUP, "at": &"file_spot"}),
		b(0.45, &"arm", {"side": &"lead", "g": Gestures.PALM_UP, "at": &"file_spot", "speed": 0.9}),
		b(0.7, &"artifact", {"state": &"appear"}),
		b(1.4, &"summon", {"n": 1, "near": &"miku", "role": &"holder"}),
		b(1.45, &"cast", {"force": 0.0, "side": &"other"}),
		b(1.5, &"gaze", {"at": &"hands", "secs": 1.0}),
		b(1.9, &"pull", {"force": 0.5}),
		b(1.9, &"send", {"place": &"card_hold"}),
		b(1.95, &"wait", {"until": &"arrived", "timeout": 3.5}),
		b(2.0, &"artifact", {"state": &"held"}),
		b(2.05, &"gaze", {"at": &"file", "secs": 1.5}),
		b(2.1, &"arm", {"side": &"lead", "g": &"rest"}),
		b(2.2, &"pull", {"force": 0.3}),
	]


## Editing: (grab first when needed) a second hand is summoned to write on the card while her
## other hand guides it (pinch); the glyphs are rewritten; at the end the change is COMMITTED
## (signal file_committed; the interaction system validates and applies it, Miku.apply_config);
## the card shows the validation, she reacts to the change in herself, then lets the card go.
static func edit_beats(grab_first: bool, keep: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t0 := 0.0
	if grab_first:
		out = grab_beats()
		t0 = 2.4
	out.append_array([
		b(t0 + 0.0, &"summon", {"n": 1, "near": &"miku", "role": &"editor"}),
		b(t0 + 0.0, &"arm", {"side": &"lead", "g": Gestures.WINDUP, "at": &"file"}),
		b(t0 + 0.05, &"cast", {"force": 0.0, "side": &"lead", "only": &"editor"}),
		b(t0 + 0.5, &"pull", {"force": 0.55, "only": &"editor"}),
		b(t0 + 0.5, &"send", {"place": &"card_edit", "only": &"editor"}),
		b(t0 + 0.55, &"wait", {"until": &"arrived", "timeout": 3.5}),
		b(t0 + 0.6, &"arm", {"side": &"lead", "g": Gestures.PINCH, "at": &"file"}),
		b(t0 + 0.6, &"gaze", {"at": &"file", "scan": true, "secs": 3.0}),
		b(t0 + 0.6, &"pose", {"lean": 0.08, "tilt": 0.08, "secs": 3.0}),
		b(t0 + 0.65, &"artifact", {"state": &"edit"}),
		b(t0 + 0.7, &"wait", {"until": &"edited", "timeout": 4.0}),
		b(t0 + 0.75, &"commit", {}),
		b(t0 + 0.8, &"wait", {"until": &"applied", "timeout": 4.0}),
		b(t0 + 0.85, &"artifact", {"state": &"valid"}),
		b(t0 + 0.9, &"arm", {"side": &"lead", "g": &"rest"}),
		b(t0 + 1.0, &"self_react", {}),
	])
	if not keep:
		out.append_array([
			b(t0 + 1.1, &"artifact", {"state": &"vanish"}),
			b(t0 + 1.2, &"relax", {"all": true}),
			b(t0 + 1.5, &"release", {"all": true}),
		])
	out.append(b(t0 + 1.7, &"done"))
	return out


## Recovery: a long exhale, the shoulders drop, the posture is corrected, she smooths her dress
## and looks at her own hand — the elegance comes back.
static func recover_beats() -> Array[Dictionary]:
	return [
		b(0.0, &"mood", {"to": &"recover"}),
		b(0.0, &"breath", {"depth": 2.4, "rate": 0.55, "secs": 5.0}),
		b(0.1, &"pose", {"raise": -0.25, "lift": 0.05, "nod": 0.12, "secs": 2.0}),
		b(2.0, &"pose", {"raise": -0.1, "lift": 0.32, "tilt": 0.08, "secs": 3.0}),
		b(0.6, &"arm", {"side": &"lead", "g": Gestures.SMOOTH, "at": &"self_low", "speed": 0.6, "secs": 1.8}),
		b(2.4, &"arm", {"side": &"lead", "g": Gestures.SELF, "speed": 0.7, "secs": 2.4}),
		b(2.4, &"gaze", {"at": &"own_hand", "secs": 2.4}),
		b(5.0, &"done"),
	]


## The reaction to the user's call (MikuMind.user_call()): curious, brief, curt or cold.
static func user_reaction(r: Dictionary) -> Array[Dictionary]:
	var hold: float = r.get("hold", 1.5)
	var turn: float = r.get("turn", 0.0)
	match StringName(r.get("reaction", MikuMind.REACT_BRIEF)):
		MikuMind.REACT_CURIOUS:
			return [b(0.0, &"gaze", {"at": &"user", "secs": hold}), b(0.0, &"attend", {"kind": &"user", "secs": hold}),
				b(0.12, &"turn", {"at": &"user", "amount": turn, "secs": hold}),
				b(0.25, &"pose", {"tilt": 0.13, "lift": 0.15, "secs": hold * 0.8}),
				b(0.2, &"breath", {"depth": 1.6, "rate": 1.1, "secs": 1.5}),
				b(0.55, &"arm", {"side": &"free", "g": Gestures.PALM_UP, "at": &"user", "speed": 0.8, "secs": hold * 0.7}),
				b(hold * 0.55, &"pose", {"nod": 0.09, "tilt": 0.1, "secs": 0.5}),
				b(hold + 0.1, &"done")]
		MikuMind.REACT_BRIEF:
			return [b(0.0, &"gaze", {"at": &"user", "secs": hold}), b(0.0, &"attend", {"kind": &"user", "secs": hold}),
				b(0.1, &"turn", {"at": &"user", "amount": turn, "secs": hold}),
				b(0.35, &"pose", {"nod": 0.1, "secs": 0.4}), b(hold + 0.05, &"done")]
		MikuMind.REACT_CURT:
			return [b(0.0, &"gaze", {"at": &"user", "secs": hold, "weight": 0.7}),
				b(0.0, &"attend", {"kind": &"user", "secs": hold}),
				b(0.05, &"pose", {"raise": 0.3, "nod": 0.04, "secs": hold}), b(hold, &"done")]
	# Cold: the eyes only (most of the gaze stays on the work); not a muscle more.
	return [b(0.0, &"gaze", {"at": &"user", "secs": hold, "weight": 0.35}),
		b(0.0, &"attend", {"kind": &"user", "secs": hold}), b(hold, &"done")]


## Reaction to the target the user pointed at: she looks, turns, acknowledges with a nod.
static func world_target_reaction(world: StringName) -> Array[Dictionary]:
	return [b(0.0, &"gaze", {"at": &"world", "world": world, "secs": 2.0}),
		b(0.0, &"attend", {"kind": &"world", "world": world, "secs": 2.0}),
		b(0.1, &"turn", {"at": &"world", "world": world, "amount": 0.5, "secs": 2.5}),
		b(0.5, &"pose", {"nod": 0.12, "secs": 0.35}), b(0.9, &"pose", {"nod": 0.0, "lift": 0.1, "secs": 0.6}),
		b(1.6, &"done")]


## Her reaction to a change in herself: appearance = she looks at her body (her hand, her
## shoulder), turns a little as before a mirror, then a small satisfied nod; personality =
## a felt change: a breath in, the posture settles differently.
static func self_reaction(appearance_changed: bool) -> Array[Dictionary]:
	if appearance_changed:
		return [b(0.0, &"gaze", {"at": &"own_hand", "secs": 2.0}),
			b(0.0, &"attend", {"kind": &"self", "secs": 3.6}),
			b(0.05, &"arm", {"side": &"lead", "g": Gestures.SELF, "speed": 0.8, "secs": 2.2}),
			b(0.2, &"breath", {"depth": 1.8, "rate": 0.9, "secs": 2.5}),
			b(1.9, &"gaze", {"at": &"own_shoulder", "secs": 1.4}),
			b(1.9, &"turn", {"angle": 0.18, "secs": 1.4}),
			b(2.0, &"pose", {"tilt": 0.14, "lift": 0.2, "secs": 1.4}),
			b(3.3, &"pose", {"nod": 0.1, "secs": 0.4}), b(3.8, &"done")]
	return [b(0.0, &"breath", {"depth": 2.0, "rate": 0.8, "secs": 2.5}),
		b(0.0, &"attend", {"kind": &"self", "secs": 2.5}),
		b(0.1, &"pose", {"lift": 0.3, "nod": -0.04, "tilt": 0.09, "secs": 1.8}),
		b(0.3, &"gaze", {"at": &"inward", "secs": 1.6}),
		b(2.0, &"pose", {"nod": 0.08, "secs": 0.5}), b(2.6, &"done")]
