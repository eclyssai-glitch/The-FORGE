class_name RigBones
extends RefCounted
## Resolves the semantic bones the motion code needs to indices of a Skeleton3D (Loop 5).
## Owner: animator. The rig contract (docs/contracts/loop-05.md) names MIKU's bones `root, hips,
## spine, chest, neck, head, clavicle.L/R, upper_arm.L/R, forearm.L/R, hand.L/R`, two segments
## for thumb/index/middle/ring, `skirt.0/1/2`, and the puppet hand's `wrist, palm` + 5 fingers x 3.
## The exact spelling of the finger segments is not fixed by the contract, so every key is looked
## up through several spellings (case-insensitive): `index.L.0`, `index.L.1`-based, `index.0.L`,
## `index_0.L`, `index0.L`, `index.L0`, `index_L_0`... A key that does not resolve is -1 and the
## layers that need it simply skip it (the motion degrades, never breaks).

const SIDES: Array[String] = ["L", "R"]
const FINGERS: Array[String] = ["thumb", "index", "middle", "ring", "little"]

## key -> bone index (-1 = missing).
var index: Dictionary = {}
var skeleton: Skeleton3D


func _init(skel: Skeleton3D = null) -> void:
	skeleton = skel


## Index of `key`, resolving it on first use.
func bone(key: String) -> int:
	if index.has(key):
		return index[key]
	var i := _resolve(key)
	index[key] = i
	return i


func has(key: String) -> bool:
	return bone(key) >= 0


## Key of finger `finger` of side "L"/"R" (empty side for the puppet hand), segment `seg`
## (0-based).
static func finger_key(finger: String, side: String, seg: int) -> String:
	if side == "":
		return "%s.%d" % [finger, seg]
	return "%s.%s.%d" % [finger, side, seg]


## Candidate names of a key, most likely first. Segment numbers are tried 0-based, or 1-based
## when `one_based` (a rig that numbers its segments from 1 is detected per finger: see _resolve).
static func candidates(key: String, one_based := false) -> PackedStringArray:
	var out := PackedStringArray([] if one_based else [key])
	var parts := key.split(".")
	if parts.size() == 3:
		# finger.side.seg
		var f := parts[0]
		var s := parts[1]
		var n := int(parts[2]) + (1 if one_based else 0)
		out.append_array([
			"%s.%s.%d" % [f, s, n], "%s.%d.%s" % [f, n, s], "%s_%d.%s" % [f, n, s], "%s%d.%s" % [f, n, s],
			"%s.%s%d" % [f, s, n], "%s_%s_%d" % [f, s, n], "%s_%d_%s" % [f, n, s], "%s%d_%s" % [f, n, s],
			"%s.%s.%02d" % [f, s, n],
		])
	elif parts.size() == 2 and parts[1].is_valid_int():
		# finger.seg (puppet hand) or skirt.n
		var f2 := parts[0]
		var m := int(parts[1]) + (1 if one_based else 0)
		out.append_array(["%s.%d" % [f2, m], "%s_%d" % [f2, m], "%s%d" % [f2, m], "%s.%02d" % [f2, m]])
	elif one_based:
		return out
	elif parts.size() == 2:
		# name.side
		out.append_array(["%s_%s" % [parts[0], parts[1]], "%s%s" % [parts[0], parts[1]],
			"%s.%s" % [parts[0], parts[1].to_lower()]])
	return out


func _resolve(key: String) -> int:
	if skeleton == null:
		return -1
	var parts := key.split(".")
	var numbered := parts[parts.size() - 1].is_valid_int() and parts.size() >= 2
	if not numbered:
		return _find(candidates(key))
	# Numbered chain: 0-based when its segment 0 exists 0-based, else 1-based.
	parts[parts.size() - 1] = "0"
	var first := ".".join(parts)
	var one_based := _find(candidates(first)) < 0 and _find(candidates(first, true)) >= 0
	return _find(candidates(key, one_based))


func _find(names: PackedStringArray) -> int:
	for c in names:
		var i := skeleton.find_bone(c)
		if i >= 0:
			return i
	var lower := PackedStringArray()
	for c in names:
		lower.append(c.to_lower())
	for b in skeleton.get_bone_count():
		if lower.has(skeleton.get_bone_name(b).to_lower()):
			return b
	return -1
