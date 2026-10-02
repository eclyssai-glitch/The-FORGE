class_name WorkPlan
extends RefCounted
## How MIKU builds a world, stage by stage, and how the deliberate failure unfolds (Loop 5).
## Owner: animator. Pure. Each stage is the same causal sentence — look, anticipate, gesture,
## cast the threads, pull, the hands go to their places, the matter answers while they work,
## release, look at the result — with a recipe per stage (hands, gestures, force, rate). Composed
## MIKU builds with 2 hands, gracefully; after she loses her composure she rebuilds with 6, fast
## and dry (ANGRY recipes).
##
## The failure (WORK with {"fail": true}) escalates in three beats of the script below:
## 1. a CRACK opens while the outer layer is laid: she freezes, holds her breath, looks, leans in,
##    then tries one elegant correction with one hand — it closes the crack only partly;
## 2. the fix does not hold (crack widens, the world tilts): FRUSTRATED — shoulders up, two hands
##    pushing harder and faster — and the outer layer COLLAPSES;
## 3. ANGRY: stillness, the locked stare, four more hands at once with many taut threads, the world
##    is torn back into the cloud and rebuilt with extreme efficiency; success -> RECOVERING.

const STAGES: Array[WorldBuild.Stage] = [WorldBuild.Stage.GATHER, WorldBuild.Stage.CORE,
	WorldBuild.Stage.LAYERS, WorldBuild.Stage.ADJUST]
## Layer progress of the outer layer at which the planned crack opens.
const FAIL_AT_LAYER := 2
const FAIL_AT_PROGRESS := 0.45

## Stage recipes: hands, lead gesture, other-arm gesture, force, work rate (/s at full tension).
const CALM := {
	WorldBuild.Stage.GATHER: [2, Gestures.SMOOTH, Gestures.CONDUCT, 0.55, 0.2],
	WorldBuild.Stage.CORE: [2, Gestures.COMPRESS, Gestures.COMPRESS, 0.85, 0.2],
	WorldBuild.Stage.LAYERS: [2, Gestures.SMOOTH, Gestures.PUSH, 0.6, 0.26],
	WorldBuild.Stage.ADJUST: [2, Gestures.PINCH, Gestures.CONDUCT, 0.45, 0.32],
}
const FURIOUS := {
	WorldBuild.Stage.GATHER: [6, Gestures.CLAW, Gestures.CLAW, 1.0, 0.6],
	WorldBuild.Stage.CORE: [6, Gestures.CLAW, Gestures.CLAW, 1.0, 0.55],
	WorldBuild.Stage.LAYERS: [6, Gestures.CLAW, Gestures.CLAW, 1.0, 0.7],
	WorldBuild.Stage.ADJUST: [6, Gestures.PINCH, Gestures.CLAW, 0.9, 0.7],
}


static func recipe(stage: WorldBuild.Stage, furious: bool) -> Array:
	var table: Dictionary = FURIOUS if furious else CALM
	return table.get(stage, CALM[WorldBuild.Stage.GATHER])


## Stage that follows `s` (STABLE after ADJUST).
static func next_stage(s: WorldBuild.Stage) -> WorldBuild.Stage:
	match s:
		WorldBuild.Stage.DORMANT:
			return WorldBuild.Stage.GATHER
		WorldBuild.Stage.GATHER:
			return WorldBuild.Stage.CORE
		WorldBuild.Stage.CORE:
			return WorldBuild.Stage.LAYERS
		WorldBuild.Stage.LAYERS:
			return WorldBuild.Stage.ADJUST
	return WorldBuild.Stage.STABLE


## Beats of one stage on `world`.
static func stage_beats(stage: WorldBuild.Stage, world: StringName, furious: bool) -> Array[Dictionary]:
	var r := recipe(stage, furious)
	var n: int = r[0]
	var g_lead: StringName = r[1]
	var g_other: StringName = r[2]
	var force: float = r[3]
	var rate: float = r[4]
	var B := ActionScript
	var out: Array[Dictionary] = [
		B.b(0.0, &"stage", {"s": stage}),
		B.b(0.0, &"gaze", {"at": &"world", "world": world, "secs": 1.2}),
		B.b(0.0, &"attend", {"kind": &"work", "world": world, "secs": 0.0}),
		B.b(0.0, &"turn", {"at": &"world", "world": world, "amount": 0.4, "secs": 999.0}),
		B.b(0.1, &"pose", {"lean": 0.1 if not furious else 0.0, "lift": 0.05, "secs": 999.0, "key": &"stage"}),
		B.b(0.25, &"arm", {"side": &"lead", "g": Gestures.WINDUP, "at": &"world", "world": world}),
		B.b(0.35, &"arm", {"side": &"other", "g": Gestures.WINDUP, "at": &"world", "world": world}),
		B.b(0.7, &"arm", {"side": &"lead", "g": g_lead, "at": &"world", "world": world, "rhythm": true}),
		B.b(0.8, &"arm", {"side": &"other", "g": g_other, "at": &"world", "world": world, "rhythm": true}),
		B.b(0.8, &"summon", {"n": n, "near": &"world", "world": world}),
		B.b(0.85, &"cast", {"force": 0.0, "extra": 1 if furious else 0}),
		B.b(0.9, &"gaze", {"at": &"hands", "secs": 0.9}),
		B.b(1.3, &"pull", {"force": force}),
		B.b(1.3, &"send", {"place": &"work", "world": world}),
		B.b(1.35, &"wait", {"until": &"arrived", "timeout": 5.0}),
		B.b(1.4, &"gaze", {"at": &"world", "world": world, "scan": true, "secs": 999.0}),
		B.b(1.4, &"work", {"rate": rate, "world": world}),
		B.b(1.45, &"wait", {"until": &"stage", "timeout": 16.0}),
		B.b(1.5, &"work_stop", {}),
		B.b(1.5, &"particles", {"kind": &"form", "world": world}),
		B.b(1.55, &"relax", {}),
		B.b(1.6, &"arm", {"side": &"both", "g": &"rest"}),
		B.b(1.6, &"pose", {"lean": 0.14, "tilt": 0.1, "secs": 1.1, "key": &"stage"}),
		B.b(1.6, &"gaze", {"at": &"world", "world": world, "scan": true, "secs": 1.2}),
		B.b(2.8, &"next_stage", {}),
	]
	return out


## Beats of the deliberate failure on `world` (starts when the outer layer reaches
## FAIL_AT_PROGRESS while the composed MIKU lays it).
static func failure_beats(world: StringName) -> Array[Dictionary]:
	var B := ActionScript
	return [
		# 1. The crack. Cause first, then her perception (a beat later).
		B.b(0.0, &"work_stop", {}),
		B.b(0.0, &"fault", {"kind": &"crack", "amount": 0.55, "severity": 0.35, "world": world}),
		B.b(0.0, &"pull", {"force": 0.35}),
		B.b(0.2, &"gaze", {"at": &"crack", "world": world, "secs": 2.6}),
		B.b(0.2, &"arm", {"side": &"both", "g": Gestures.FREEZE}),
		B.b(0.2, &"breath", {"depth": 0.15, "rate": 0.6, "secs": 1.6}),
		B.b(0.25, &"pose", {"lean": 0.2, "nod": 0.06, "lift": -0.05, "secs": 1.6, "key": &"stage"}),
		B.b(1.5, &"pose", {"lean": 0.22, "tilt": 0.15, "secs": 1.4, "key": &"stage"}),
		# Elegant correction: one hand, one fine gesture.
		B.b(2.7, &"arm", {"side": &"lead", "g": Gestures.WINDUP, "at": &"crack", "world": world}),
		B.b(3.0, &"arm", {"side": &"lead", "g": Gestures.SMOOTH, "at": &"crack", "world": world, "rhythm": true, "speed": 0.8}),
		B.b(3.0, &"relax", {"except": 0}),
		B.b(3.1, &"pull", {"force": 0.55, "only_index": 0}),
		B.b(3.1, &"send", {"place": &"crack", "world": world, "only_index": 0}),
		B.b(3.15, &"wait", {"until": &"arrived", "timeout": 3.0, "only_index": 0}),
		B.b(3.2, &"repair", {"rate": 0.16, "limit": 0.22, "world": world}),
		B.b(3.25, &"wait", {"until": &"repaired", "timeout": 5.0}),
		# 2. It does not hold.
		B.b(3.3, &"work_stop", {}),
		B.b(3.3, &"fault", {"kind": &"crack", "amount": 0.85, "severity": 0.0, "world": world}),
		B.b(3.3, &"fault", {"kind": &"imbalance", "amount": 0.55, "severity": 0.32, "world": world}),
		B.b(3.5, &"gaze", {"at": &"crack", "world": world, "secs": 4.0}),
		B.b(3.5, &"pose", {"raise": 0.55, "lean": 0.12, "secs": 4.5, "key": &"stage"}),
		B.b(3.5, &"breath", {"depth": 0.6, "rate": 1.6, "secs": 4.5}),
		B.b(3.6, &"wave", {"side": &"other", "kind": &"tap", "secs": 0.9}),
		B.b(4.3, &"arm", {"side": &"both", "g": Gestures.PUSH, "at": &"crack", "world": world, "rhythm": true, "speed": 1.4}),
		B.b(4.35, &"pull", {"force": 0.85}),
		B.b(4.35, &"send", {"place": &"crack", "world": world, "dist": 1.25}),
		B.b(4.4, &"wait", {"until": &"arrived", "timeout": 2.5}),
		B.b(4.45, &"repair", {"rate": 0.3, "limit": 0.45, "world": world}),
		B.b(4.5, &"wait", {"until": &"repaired", "timeout": 3.0}),
		# 3. Collapse -> composure lost.
		B.b(4.6, &"work_stop", {}),
		B.b(4.6, &"fault", {"kind": &"collapse", "amount": 0.62, "severity": 0.6, "world": world}),
		B.b(4.65, &"particles", {"kind": &"fragments", "world": world, "strength": 1.6}),
		B.b(4.8, &"arm", {"side": &"both", "g": Gestures.FREEZE}),
		B.b(4.8, &"breath", {"depth": 0.08, "rate": 1.3, "secs": 2.0}),
		B.b(4.8, &"pose", {"lean": 0.0, "nod": 0.08, "raise": 0.35, "tilt": 0.0, "secs": 999.0, "key": &"stage"}),
		B.b(4.8, &"gaze", {"at": &"crack", "world": world, "secs": 999.0}),
		B.b(5.5, &"arm", {"side": &"both", "g": Gestures.CLAW, "at": &"world", "world": world, "rhythm": true}),
		B.b(5.6, &"summon", {"n": 6, "near": &"world", "world": world}),
		B.b(5.65, &"cast", {"force": 0.0, "extra": 1}),
		B.b(5.95, &"pull", {"force": 1.0}),
		B.b(5.95, &"send", {"place": &"work", "world": world, "dist": 1.35}),
		B.b(6.0, &"wait", {"until": &"arrived", "timeout": 3.5}),
		B.b(6.05, &"dismantle", {"rate": 0.75, "world": world}),
		B.b(6.1, &"wait", {"until": &"dismantled", "timeout": 8.0}),
		B.b(6.15, &"work_stop", {}),
		B.b(6.2, &"next_stage", {"from": WorldBuild.Stage.CORE, "furious": true}),
	]


## After the rebuild: success, the threads let go, the extra hands dissolve, she recovers.
static func finish_beats(world: StringName, recovered: bool) -> Array[Dictionary]:
	var B := ActionScript
	var out: Array[Dictionary] = [
		B.b(0.0, &"success", {"mag": 1.0, "world": world}),
		B.b(0.0, &"particles", {"kind": &"form", "world": world}),
		B.b(0.1, &"relax", {"all": true}),
		B.b(0.2, &"turn", {"angle": 0.0, "secs": 0.1}),
		B.b(0.2, &"pose", {"lean": 0.0, "secs": 0.1, "key": &"stage"}),
		B.b(0.3, &"arm", {"side": &"both", "g": &"rest"}),
	]
	if recovered:
		out.append(B.b(0.6, &"release", {"all": true}))
		var rec := ActionScript.recover_beats()
		for x in rec:
			if x["op"] == &"done":
				continue
			x["t"] = float(x["t"]) + 0.9
			out.append(x)
		out.append(B.b(6.2, &"gaze", {"at": &"world", "world": world, "secs": 2.0}))
		out.append(B.b(6.3, &"pose", {"lift": 0.3, "tilt": 0.1, "secs": 2.0}))
		out.append(B.b(8.2, &"done", {}))
	else:
		out.append(B.b(0.6, &"gaze", {"at": &"world", "world": world, "scan": true, "secs": 2.2}))
		out.append(B.b(0.8, &"pose", {"lift": 0.3, "tilt": 0.1, "secs": 2.0}))
		out.append(B.b(1.0, &"breath", {"depth": 1.7, "rate": 0.8, "secs": 2.5}))
		out.append(B.b(2.6, &"release", {"all": true}))
		out.append(B.b(3.0, &"done", {}))
	return out
