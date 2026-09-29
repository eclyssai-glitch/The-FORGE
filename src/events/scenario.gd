class_name Scenario
extends RefCounted
## Registry of the demo scenarios (pure logic). Each scenario is a scripted event list, a
## derived state (a ScenarioState subclass), a mission and an entity catalog. `Simulation`
## plays exactly one scenario at a time (Simulation.scenario / set_scenario).

const ORIGIN_CHAMBER := &"origin_chamber"
const GENESIS := &"genesis"
## Every scenario id, in presentation order.
const IDS: Array[StringName] = [ORIGIN_CHAMBER, GENESIS]
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
	return ""


## Scripted events of the scenario (empty for an unknown id).
static func build_events(id: StringName) -> Array[SimEvent]:
	match id:
		ORIGIN_CHAMBER:
			return OriginChamberScript.build()
		GENESIS:
			return GenesisScript.build()
	var none: Array[SimEvent] = []
	return none


## Event types the scenario scripts.
static func types(id: StringName) -> Array[StringName]:
	match id:
		ORIGIN_CHAMBER:
			return SimEvent.ORIGIN_TYPES.duplicate()
		GENESIS:
			return SimEvent.GENESIS_TYPES.duplicate()
	var none: Array[StringName] = []
	return none


## Fresh (nothing happened) state of the scenario. Unknown ids get the default scenario's.
static func new_state(id: StringName) -> ScenarioState:
	if id == GENESIS:
		return GenesisState.new()
	return WorldState.new()


## State after applying `events` in order to a fresh state of the scenario.
static func derive(id: StringName, events: Array[SimEvent]) -> ScenarioState:
	var s := new_state(id)
	for e in events:
		s.apply(e)
	return s


## Selectable entity ids of the scenario.
static func entity_ids(id: StringName) -> Array[StringName]:
	return GenesisCatalog.all_ids() if id == GENESIS else EntityCatalog.all_ids()


## Catalog row of an entity of the scenario ({} if unknown).
static func entity_info(id: StringName, entity: StringName) -> Dictionary:
	return GenesisCatalog.info(entity) if id == GENESIS else EntityCatalog.info(entity)


## Status of an entity given the scenario's state ("UNKNOWN" if the state does not match).
static func entity_status(id: StringName, entity: StringName, state: ScenarioState) -> String:
	if id == GENESIS and state is GenesisState:
		return GenesisCatalog.status(entity, state as GenesisState)
	if id != GENESIS and state is WorldState:
		return EntityCatalog.status(entity, state as WorldState)
	return "UNKNOWN"
