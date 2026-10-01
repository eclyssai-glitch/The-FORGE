class_name Scenario
extends RefCounted
## Registry of the demo scenarios (pure logic). Each scenario is a scripted event list, a
## derived state (a ScenarioState subclass), a mission and an entity catalog. `Simulation`
## plays exactly one scenario at a time (Simulation.scenario / set_scenario).
## LIVING (Loop 5) is the MIKU LIVING CHARACTER prototype: its character is real-time state
## (ADR-015), so it does not support seek (supports_seek) — reset recomposes it.

const ORIGIN_CHAMBER := &"origin_chamber"
const GENESIS := &"genesis"
const LIVING := &"living"
## Every scenario id, in presentation order.
const IDS: Array[StringName] = [ORIGIN_CHAMBER, GENESIS, LIVING]
## Scenario played at startup (until the GENESIS switch-over of Loop 4, phase C).
const DEFAULT := ORIGIN_CHAMBER


static func is_valid(id: StringName) -> bool:
	return IDS.has(id)


static func title(id: StringName) -> String:
	match id:
		ORIGIN_CHAMBER:
			return "ORIGIN CHAMBER"
		GENESIS:
			return "GENESIS"
		LIVING:
			return "MIKU · LIVING PROTOTYPE"
	return ""


## False for scenarios whose visuals are real-time state (LIVING, ADR-015): Simulation.seek is
## refused there; reset recomposes the scene.
static func supports_seek(id: StringName) -> bool:
	return id != LIVING


## Scripted events of the scenario (empty for an unknown id).
static func build_events(id: StringName) -> Array[SimEvent]:
	match id:
		ORIGIN_CHAMBER:
			return OriginChamberScript.build()
		GENESIS:
			return GenesisScript.build()
		LIVING:
			return LivingScript.build()
	var none: Array[SimEvent] = []
	return none


## Event types the scenario scripts.
static func types(id: StringName) -> Array[StringName]:
	match id:
		ORIGIN_CHAMBER:
			return SimEvent.ORIGIN_TYPES.duplicate()
		GENESIS:
			return SimEvent.GENESIS_TYPES.duplicate()
		LIVING:
			return SimEvent.LIVING_TYPES.duplicate()
	var none: Array[StringName] = []
	return none


## Fresh (nothing happened) state of the scenario. Unknown ids get the default scenario's.
static func new_state(id: StringName) -> ScenarioState:
	if id == GENESIS:
		return GenesisState.new()
	if id == LIVING:
		return LivingState.new()
	return WorldState.new()


## State after applying `events` in order to a fresh state of the scenario.
static func derive(id: StringName, events: Array[SimEvent]) -> ScenarioState:
	var s := new_state(id)
	for e in events:
		s.apply(e)
	return s


## Selectable entity ids of the scenario.
static func entity_ids(id: StringName) -> Array[StringName]:
	match id:
		GENESIS:
			return GenesisCatalog.all_ids()
		LIVING:
			return LivingCatalog.all_ids()
	return EntityCatalog.all_ids()


## Catalog row of an entity of the scenario ({} if unknown).
static func entity_info(id: StringName, entity: StringName) -> Dictionary:
	match id:
		GENESIS:
			return GenesisCatalog.info(entity)
		LIVING:
			return LivingCatalog.info(entity)
	return EntityCatalog.info(entity)


## Status of an entity given the scenario's state ("UNKNOWN" if the state does not match).
static func entity_status(id: StringName, entity: StringName, state: ScenarioState) -> String:
	if id == GENESIS and state is GenesisState:
		return GenesisCatalog.status(entity, state as GenesisState)
	if id == LIVING and state is LivingState:
		return LivingCatalog.status(entity, state as LivingState)
	if id != GENESIS and id != LIVING and state is WorldState:
		return EntityCatalog.status(entity, state as WorldState)
	return "UNKNOWN"
