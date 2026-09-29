class_name GenesisScript
extends RefCounted
## Canonical scripted timeline of the GENESIS demonstration (Loop 4 vertical slice):
## MIKU awakens, two auxiliary hands gather stardust and shape a new world (a fictional
## subagent) that gains mantle, crust and sky, two documentation moons, a ring of skills,
## a memory belt around MIKU and, last, the relational threads that tie it all together.
## Entirely fictional. Times are seconds from session start, ascending, with deliberate
## pauses between steps (contemplative pacing).

const DURATION := 56.0

## The world formed in this session: a fictional subagent.
const PLANET_NAME := "ILVARA-7"
## Planet layers, in formation order (payload "layer" of PLANET_LAYER).
const LAYER_COUNT := 3
const LAYER_NAMES: Array[String] = ["MANTLE", "CRUST", "SKY"]
const LAYER_DETAILS: Array[String] = [
	"Incandescent mantle wraps the molten core",
	"The mantle cools into a dark crust",
	"A thin atmosphere settles over the crust",
]
## Documentation moons (fictional documents), in formation order (payload "index"/"name").
const MOON_COUNT := 2
const MOON_NAMES: Array[String] = ["ALMANAC", "GLOSSARY"]
## Fictional skills held by the ring, in segment order.
const SKILLS: Array[String] = ["WEAVING", "CHARTING", "LISTENING", "MENDING"]
## Distant worlds (other fictional subagents), already formed when the session starts.
const FAR_PLANET_NAMES: Array[String] = ["NAUVE-2", "KESTRE-4"]
## Relational threads woven by LINKS_WOVEN: [from entity, to entity]. The last one runs from a
## distant world back to the new one (a backlink forming).
const LINKS: Array = [
	[&"miku", &"planet_forming"],
	[&"planet_forming", &"moon_0"],
	[&"planet_forming", &"moon_1"],
	[&"planet_forming", &"ring_skill"],
	[&"miku", &"belt_memory"],
	[&"miku", &"planet_far_0"],
	[&"miku", &"planet_far_1"],
	[&"planet_far_0", &"planet_forming"],
]

## Event times (seconds). Layer i at LAYER_TIMES[i], moon i at MOON_TIMES[i].
const T_OPENED := 0.0
const T_AWAKEN := 3.0
const T_HANDS := 8.0
const T_DUST := 13.0
const T_SEEDED := 18.0
const LAYER_TIMES: Array[float] = [22.0, 27.0, 32.0]
const MOON_TIMES: Array[float] = [37.0, 40.0]
const T_RING := 43.0
const T_BELT := 46.0
const T_LINKS := 50.0
const T_STABLE := 53.0
const T_COMPLETED := DURATION


static func build() -> Array[SimEvent]:
	var e: Array[SimEvent] = []
	e.append(SimEvent.new(&"gn-000", T_OPENED, SimEvent.SESSION_OPENED,
		"SESSION OPENED", "Demo session opened. All events in this session are simulated.",
		&"miku"))
	e.append(SimEvent.new(&"gn-001", T_AWAKEN, SimEvent.MIKU_AWAKEN,
		"MIKU AWAKENS", "Central agent MIKU wakes, suspended in the void; her halo begins to turn.",
		&"miku"))
	e.append(SimEvent.new(&"gn-002", T_HANDS, SimEvent.HANDS_SUMMONED,
		"THE HANDS ARRIVE", "Two auxiliary hands rise from the mist below MIKU.",
		&"hand_left", {"hands": [&"hand_left", &"hand_right"]}))
	e.append(SimEvent.new(&"gn-003", T_DUST, SimEvent.DUST_GATHERED,
		"DUST GATHERS", "Stardust drawn into a slow disc between the hands.",
		&"planet_forming"))
	e.append(SimEvent.new(&"gn-004", T_SEEDED, SimEvent.PLANET_SEEDED,
		"A WORLD IS SEEDED", "Subagent %s seeded as a molten core." % PLANET_NAME,
		&"planet_forming", {"name": PLANET_NAME}))
	for i in LAYER_COUNT:
		e.append(SimEvent.new(StringName("gn-%03d" % (5 + i)), LAYER_TIMES[i], SimEvent.PLANET_LAYER,
			LAYER_NAMES[i], "%s (layer %d of %d)." % [LAYER_DETAILS[i], i + 1, LAYER_COUNT],
			&"planet_forming", {"layer": i}))
	for i in MOON_COUNT:
		e.append(SimEvent.new(StringName("gn-%03d" % (8 + i)), MOON_TIMES[i], SimEvent.MOON_FORMED,
			"%s MOON · %s" % [["FIRST", "SECOND"][i], MOON_NAMES[i]],
			"Documentation moon %s enters orbit around %s." % [MOON_NAMES[i], PLANET_NAME],
			moon_entity(i), {"index": i, "name": MOON_NAMES[i]}))
	e.append(SimEvent.new(&"gn-010", T_RING, SimEvent.RING_FORMED,
		"A RING OF SKILLS", "Skill ring condensed around %s: %s." % [PLANET_NAME, ", ".join(SKILLS).to_lower()],
		&"ring_skill", {"skills": SKILLS}))
	e.append(SimEvent.new(&"gn-011", T_BELT, SimEvent.BELT_FORMED,
		"THE MEMORY BELT", "A thin belt of memory fragments settles into orbit around MIKU.",
		&"belt_memory"))
	e.append(SimEvent.new(&"gn-012", T_LINKS, SimEvent.LINKS_WOVEN,
		"THREADS OF LIGHT", "%d relational threads woven between MIKU, %s, its moons, the ring, the belt and the distant worlds."
			% [LINKS.size(), PLANET_NAME],
		&"relations", {"count": LINKS.size()}))
	e.append(SimEvent.new(&"gn-013", T_STABLE, SimEvent.PLANET_STABLE,
		"A WORLD HOLDS", "Subagent %s reached a stable orbit." % PLANET_NAME,
		&"planet_forming", {"name": PLANET_NAME}))
	e.append(SimEvent.new(&"gn-014", T_COMPLETED, SimEvent.SESSION_COMPLETED,
		"SESSION COMPLETE", "Demo session complete. Nothing was sent or received.",
		&"miku"))
	return e


static func moon_entity(index: int) -> StringName:
	return StringName("moon_%d" % index)


static func far_planet_entity(index: int) -> StringName:
	return StringName("planet_far_%d" % index)
