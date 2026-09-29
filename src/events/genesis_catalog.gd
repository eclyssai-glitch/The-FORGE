class_name GenesisCatalog
extends RefCounted
## Static catalog of the selectable entities of the GENESIS scenario and their derived status.
## Every entity is a fictional element of the demo universe. The celestial form ("body") is
## the visual metaphor; "kind" is what it stands for: planets are subagents, moons are
## documentation, rings are skills, belts are memory, threads are links.

enum Kind { CENTRAL_AGENT, HAND, SUBAGENT, DOCUMENTATION, SKILL, MEMORY, RELATION }

const KIND_NAMES: Array[String] = [
	"CENTRAL AGENT", "AUXILIARY HAND", "SUBAGENT", "DOCUMENTATION", "SKILLS", "MEMORY", "RELATIONS",
]

const IDS: Array[StringName] = [
	&"miku", &"hand_left", &"hand_right", &"planet_forming", &"moon_0", &"moon_1",
	&"ring_skill", &"belt_memory", &"planet_far_0", &"planet_far_1", &"relations",
]


static func all_ids() -> Array[StringName]:
	return IDS.duplicate()


## {"id", "title", "kind", "kind_name", "body", "summary"}, or {} for an unknown id.
static func info(id: StringName) -> Dictionary:
	match id:
		&"miku":
			return _row(id, "MIKU", Kind.CENTRAL_AGENT, "figure",
				"The central agent: a celestial weaver whose hair becomes the threads of this universe.")
		&"hand_left":
			return _row(id, "LEFT HAND", Kind.HAND, "hand",
				"A hand of night-stone that cradles the new world from below.")
		&"hand_right":
			return _row(id, "RIGHT HAND", Kind.HAND, "hand",
				"A hand of night-stone that shapes the new world from above.")
		&"planet_forming":
			return _row(id, GenesisScript.PLANET_NAME, Kind.SUBAGENT, "planet",
				"A world being born: a fictional subagent taking form.")
		&"moon_0":
			return _row(id, "MOON · %s" % GenesisScript.MOON_NAMES[0], Kind.DOCUMENTATION, "moon",
				"A small moon of knowledge: the almanac of how the new world works.")
		&"moon_1":
			return _row(id, "MOON · %s" % GenesisScript.MOON_NAMES[1], Kind.DOCUMENTATION, "moon",
				"A pale moon of knowledge: the glossary of the new world's words.")
		&"ring_skill":
			return _row(id, "RING OF SKILLS", Kind.SKILL, "ring",
				"A ring of what the new world can do: %s." % ", ".join(GenesisScript.SKILLS).to_lower())
		&"belt_memory":
			return _row(id, "MEMORY BELT", Kind.MEMORY, "belt",
				"A thin belt of remembered fragments circling MIKU.")
		&"planet_far_0":
			return _row(id, GenesisScript.FAR_PLANET_NAMES[0], Kind.SUBAGENT, "planet",
				"An older world, formed long ago, keeping a close orbit.")
		&"planet_far_1":
			return _row(id, GenesisScript.FAR_PLANET_NAMES[1], Kind.SUBAGENT, "planet",
				"An older world, formed long ago, keeping a far orbit.")
		&"relations":
			return _row(id, "THREADS OF LIGHT", Kind.RELATION, "threads",
				"Every thread is a link between bodies; every pulse along it, a backlink forming.")
	return {}


## Human-readable status of an entity given the current GENESIS state.
static func status(id: StringName, g: GenesisState) -> String:
	match id:
		&"miku":
			if g.awaken_at < 0.0:
				return "ASLEEP"
			if g.stable_at >= 0.0:
				return "SERENE"
			return "CONDUCTING" if g.hands_at >= 0.0 else "AWAKE"
		&"hand_left", &"hand_right":
			if g.hands_at < 0.0:
				return "IN THE MIST"
			if g.stable_at >= 0.0:
				return "AT REST"
			return "CRADLING" if id == &"hand_left" else "SHAPING"
		&"planet_forming":
			if g.stable_at >= 0.0:
				return "STABLE"
			if g.seeded_at < 0.0:
				return "GATHERING DUST" if g.dust_at >= 0.0 else "UNFORMED"
			var n := g.layers_formed()
			if n == 0:
				return "SEEDED"
			return "%s · %d/%d" % [GenesisScript.LAYER_NAMES[n - 1], n, GenesisScript.LAYER_COUNT]
		&"moon_0", &"moon_1":
			if g.moon_at(1 if id == &"moon_1" else 0) < 0.0:
				return "UNFORMED"
			return "LINKED" if g.links_at >= 0.0 else "IN ORBIT"
		&"ring_skill":
			if g.ring_at < 0.0:
				return "UNFORMED"
			return "%d SKILLS" % GenesisScript.SKILLS.size()
		&"belt_memory":
			if g.belt_at < 0.0:
				return "UNFORMED"
			return "LINKED" if g.links_at >= 0.0 else "IN ORBIT"
		&"planet_far_0", &"planet_far_1":
			return "LINKED" if g.links_at >= 0.0 else "DISTANT"
		&"relations":
			if g.links_at < 0.0:
				return "UNWOVEN"
			return "%d THREADS" % g.link_count
	return "UNKNOWN"


static func _row(id: StringName, title: String, kind: Kind, body: String, summary: String) -> Dictionary:
	return {"id": id, "title": title, "kind": kind, "kind_name": KIND_NAMES[kind], "body": body, "summary": summary}
