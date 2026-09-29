class_name SimEvent
extends RefCounted
## One fictional, local simulation event (DEMO MODE).
## Events never represent or imitate real providers, agents or services.

const SESSION_OPENED := &"session.opened"
const CORE_ACTIVATION := &"core.activation"
const CORE_ONLINE := &"core.online"
const FRAGMENTS_EMITTED := &"fragments.emitted"
const STRUCTURE_SEEDED := &"structure.seeded"
const LAYER_ADDED := &"structure.layer_added"
const MATERIALS_APPLIED := &"structure.materials_applied"
const LIGHTING_APPLIED := &"structure.lighting_applied"
const VERIFICATION_STARTED := &"verification.started"
const CHECK_PASSED := &"verification.check_passed"
const VERIFICATION_PASSED := &"verification.passed"
const STRUCTURE_FINALIZED := &"structure.finalized"
const SESSION_COMPLETED := &"session.completed"

# GENESIS (Loop 4). SESSION_OPENED / SESSION_COMPLETED are shared by every scenario.
const MIKU_AWAKEN := &"miku.awaken"
const HANDS_SUMMONED := &"hands.summoned"
const DUST_GATHERED := &"dust.gathered"
const PLANET_SEEDED := &"planet.seeded"
## payload: {"layer": 0 mantle | 1 crust | 2 atmosphere}
const PLANET_LAYER := &"planet.layer"
## payload: {"index": 0..1, "name": String}
const MOON_FORMED := &"moon.formed"
const RING_FORMED := &"ring.formed"
const BELT_FORMED := &"belt.formed"
const LINKS_WOVEN := &"links.woven"
## payload: {"name": String}
const PLANET_STABLE := &"planet.stable"

## Types scripted by the ORIGIN CHAMBER scenario (OriginChamberScript).
const ORIGIN_TYPES: Array[StringName] = [
	SESSION_OPENED, CORE_ACTIVATION, CORE_ONLINE, FRAGMENTS_EMITTED, STRUCTURE_SEEDED,
	LAYER_ADDED, MATERIALS_APPLIED, LIGHTING_APPLIED, VERIFICATION_STARTED, CHECK_PASSED,
	VERIFICATION_PASSED, STRUCTURE_FINALIZED, SESSION_COMPLETED,
]

## Types scripted by the GENESIS scenario (GenesisScript).
const GENESIS_TYPES: Array[StringName] = [
	SESSION_OPENED, MIKU_AWAKEN, HANDS_SUMMONED, DUST_GATHERED, PLANET_SEEDED, PLANET_LAYER,
	MOON_FORMED, RING_FORMED, BELT_FORMED, LINKS_WOVEN, PLANET_STABLE, SESSION_COMPLETED,
]

## Every known type, each once (union of the scenario lists; a test keeps them coherent).
const ALL_TYPES: Array[StringName] = [
	SESSION_OPENED, CORE_ACTIVATION, CORE_ONLINE, FRAGMENTS_EMITTED, STRUCTURE_SEEDED,
	LAYER_ADDED, MATERIALS_APPLIED, LIGHTING_APPLIED, VERIFICATION_STARTED, CHECK_PASSED,
	VERIFICATION_PASSED, STRUCTURE_FINALIZED, SESSION_COMPLETED,
	MIKU_AWAKEN, HANDS_SUMMONED, DUST_GATHERED, PLANET_SEEDED, PLANET_LAYER,
	MOON_FORMED, RING_FORMED, BELT_FORMED, LINKS_WOVEN, PLANET_STABLE,
]

var id: StringName
## Seconds from the start of the demo session.
var time: float
var type: StringName
## Short, uppercase label for the HUD.
var label: String
## Factual, one-line description for logs.
var detail: String
## Optional entity this event concerns (see EntityCatalog).
var entity: StringName
var payload: Dictionary


func _init(
	p_id: StringName,
	p_time: float,
	p_type: StringName,
	p_label: String,
	p_detail: String,
	p_entity: StringName = &"",
	p_payload: Dictionary = {},
) -> void:
	id = p_id
	time = p_time
	type = p_type
	label = p_label
	detail = p_detail
	entity = p_entity
	payload = p_payload.duplicate(true)
	payload.make_read_only()


func format_time() -> String:
	return "T+%05.1f" % time
