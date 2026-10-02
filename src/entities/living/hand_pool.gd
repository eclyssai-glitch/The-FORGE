class_name HandPool
extends Node3D
## The puppet hands of the living prototype (Loop 5): a pool with no arbitrary limit. Owner:
## animator. MIKU acquires hands (1, 2, 4, 6, ... — a released hand is reused once it has
## dissolved, otherwise a new one is built), drives them through her threads and releases them.
## The pool only steps them; it never moves a hand by itself (see PuppetHand / HandDynamics).
## Group GROUP; audio anchor "hands" (the first active hand carries it).

const GROUP := &"living_hands"

var hands: Array[PuppetHand] = []
## Hands built so far (grows only when every existing hand is in use).
var built := 0


func _ready() -> void:
	add_to_group(GROUP)


## A free hand (dissolved and parked) or a new one; `left` = handedness of the rig.
func acquire(left: bool) -> PuppetHand:
	for h in hands:
		if not h.active and h.left == left:
			return h
	var h2 := PuppetHand.new(hands.size(), left)
	hands.append(h2)
	built += 1
	add_child(h2)
	if hands.size() == 1:
		h2.set_meta(&"audio_anchor", &"hands")
	return h2


func release(h: PuppetHand) -> void:
	if h != null:
		h.dismiss()


## Hands summoned and not yet dissolved.
func active_hands() -> Array[PuppetHand]:
	var out: Array[PuppetHand] = []
	for h in hands:
		if h.active:
			out.append(h)
	return out


func active_count() -> int:
	var n := 0
	for h in hands:
		if h.active:
			n += 1
	return n


func step(dt: float) -> void:
	for h in hands:
		h.step(dt)


## Releases every hand at once (recomposition).
func clear() -> void:
	for h in hands:
		h.park()
