class_name WorldBuild
extends RefCounted
## Construction state of one work world (Loop 5). Owner: animator. Pure.
## A world is never spawned finished: raw matter (a drifting cloud) is GATHERED by the hands,
## COMPRESSED into a core, wrapped in LAYERS (three shells, inner to outer, laid by the hands)
## and ADJUSTED (aligned, balanced) until STABLE. Only work() advances it — work comes from a hand
## that is in place and pulled by its thread, never from time alone.
## Failure is deliberate (the script decides): a `crack` (fissure in the outer layers), an
## `imbalance` (the world tilts and wobbles) or a `collapse` (part of the outer layer falls away).
## repair() closes cracks and rebalances; a collapse can only be undone by dismantle() (the
## layers are torn back into the cloud, outer first) and building again.

enum Stage { DORMANT, GATHER, CORE, LAYERS, ADJUST, STABLE }
const STAGE_IDS: Array[StringName] = [&"dormant", &"gather", &"core", &"layers", &"adjust", &"stable"]
const LAYER_COUNT := 3
const FAULTS: Array[StringName] = [&"crack", &"imbalance", &"collapse"]

var stage: Stage = Stage.DORMANT
var gather := 0.0
var core := 0.0
var layers := PackedFloat32Array([0.0, 0.0, 0.0])
var align := 0.0
var crack := 0.0
var imbalance := 0.0
var collapsed := 0.0
## 0..1 how hard the world is being worked now (decays by itself; visual heat).
var energy := 0.0
## Everything that happened, in order: &"stage:core", &"fault:crack", &"repair", &"dismantle"...
var history: Array[StringName] = []


func stage_id() -> StringName:
	return STAGE_IDS[stage]


## Starts a stage (the work of a hand now goes to it).
func begin(s: Stage) -> void:
	stage = s
	_log(&"stage:" + String(STAGE_IDS[s]))


## Index of the layer being laid (first not complete), or LAYER_COUNT when all are.
func current_layer() -> int:
	for i in LAYER_COUNT:
		if layers[i] < 1.0:
			return i
	return LAYER_COUNT


## Applies `amount` of hand work to the current stage. Returns true when the stage is complete.
## A broken world takes no building work (it must be repaired or dismantled first).
func work(amount: float) -> bool:
	if amount <= 0.0:
		return stage_done()
	energy = minf(energy + amount * 3.0, 1.0)
	if is_broken() and stage != Stage.GATHER:
		return false
	match stage:
		Stage.GATHER:
			gather = minf(gather + amount, 1.0)
		Stage.CORE:
			core = minf(core + amount, 1.0)
		Stage.LAYERS:
			var i := current_layer()
			if i < LAYER_COUNT:
				layers[i] = minf(layers[i] + amount, 1.0)
		Stage.ADJUST:
			align = minf(align + amount, 1.0)
			if align >= 1.0:
				stage = Stage.STABLE
				_log(&"stage:stable")
	return stage_done()


func stage_done() -> bool:
	match stage:
		Stage.GATHER:
			return gather >= 1.0
		Stage.CORE:
			return core >= 1.0
		Stage.LAYERS:
			return current_layer() >= LAYER_COUNT
		Stage.ADJUST, Stage.STABLE:
			return align >= 1.0
	return false


## Overall progress 0..1 (gather 10 %, core 25 %, layers 50 %, adjust 15 %).
func progress() -> float:
	var l := (layers[0] + layers[1] + layers[2]) / 3.0
	return clampf(gather * 0.1 + core * 0.25 + l * 0.5 + align * 0.15, 0.0, 1.0)


## A deliberate failure of `kind` (&"crack", &"imbalance", &"collapse") of `amount` 0..1.
func fault(kind: StringName, amount: float) -> void:
	var a := clampf(amount, 0.0, 1.0)
	match kind:
		&"crack":
			crack = maxf(crack, a)
		&"imbalance":
			imbalance = maxf(imbalance, a)
		&"collapse":
			collapsed = maxf(collapsed, a)
			crack = maxf(crack, 0.6)
	if stage == Stage.STABLE:
		stage = Stage.ADJUST
	align = minf(align, 0.5)
	_log(&"fault:" + String(kind))


## Closes cracks and rebalances by `amount`; a collapse stays. Returns true when no crack or
## imbalance is left.
func repair(amount: float) -> bool:
	var a := maxf(amount, 0.0)
	energy = minf(energy + a * 2.0, 1.0)
	crack = maxf(crack - a, 0.0)
	imbalance = maxf(imbalance - a, 0.0)
	if crack <= 0.0 and imbalance <= 0.0 and collapsed <= 0.0:
		return true
	return false


## Tears the world back into the cloud by `amount`: the outer layer first, then the inner ones,
## then the core — but never below layer `down_to` (0..LAYER_COUNT-1 keeps the layers under it
## and the core; LAYER_COUNT = everything, core included). Faults go with the matter that carried
## them. Returns true when everything above the floor is gone.
func dismantle(amount: float, down_to := LAYER_COUNT) -> bool:
	var a := maxf(amount, 0.0)
	energy = minf(energy + a * 2.0, 1.0)
	var floor_layer := clampi(down_to, 0, LAYER_COUNT)
	if floor_layer >= LAYER_COUNT:
		floor_layer = 0
	for i in range(LAYER_COUNT - 1, floor_layer - 1, -1):
		if a <= 0.0:
			break
		var take := minf(layers[i], a)
		layers[i] -= take
		a -= take
	var whole := down_to >= LAYER_COUNT
	if a > 0.0 and whole:
		core = maxf(core - a, 0.0)
	var outer := layers[LAYER_COUNT - 1]
	collapsed = minf(collapsed, outer)
	crack = minf(crack, outer)
	imbalance = minf(imbalance, outer)
	align = 0.0
	var done := core <= 0.0 if whole else layers[floor_layer] <= 0.0
	if done:
		collapsed = 0.0
		crack = 0.0
		imbalance = 0.0
		if stage == Stage.STABLE or stage == Stage.ADJUST:
			stage = Stage.LAYERS
	return done


## Records that the dismantling started (the visual reads it; history for tests).
func begin_dismantle() -> void:
	_log(&"dismantle")


func is_broken() -> bool:
	return crack > 0.02 or imbalance > 0.02 or collapsed > 0.02


func is_stable() -> bool:
	return stage == Stage.STABLE and not is_broken()


## Heat decays when nobody works the world.
func cool(dt: float) -> void:
	energy = maxf(energy - dt * 0.6, 0.0)


func _log(e: StringName) -> void:
	history.append(e)
	if history.size() > 64:
		history.remove_at(0)
