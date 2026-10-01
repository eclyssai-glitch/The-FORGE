extends Node3D
## Audio proof rig for tools/audio/record_proof.sh (not part of the game; tools/audio is
## .gdignore'd, the scene is loaded by path only).
##
## The real `Simulation` plays GENESIS from 0 and the real `AudioDirector` mixes it: events come
## from `Simulation.event_emitted` at their scripted times (Movie Maker fixed 30 fps = game time),
## anchored sounds play on AudioStreamPlayer3D. A camera (the listener) and the three anchors stand
## at fixed places so the recording is repeatable: camera (0, 2.5, 17) looking at (0, 2, 2);
## planet (0, 1, 4), miku (0, 4, 0), hands (0.1, 0.9, 4.7).

const CAMERA_POS := Vector3(0.0, 2.5, 17.0)
const CAMERA_TARGET := Vector3(0.0, 2.0, 2.0)
const ANCHORS := {
	&"planet": Vector3(0.0, 1.0, 4.0),
	&"miku": Vector3(0.0, 4.0, 0.0),
	&"hands": Vector3(0.1, 0.9, 4.7),
}


func _ready() -> void:
	Simulation.set_scenario(&"genesis")
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = CAMERA_POS
	cam.look_at(CAMERA_TARGET)
	cam.make_current()
	var director: Node = load("res://src/audio/audio_director.gd").new()
	add_child(director)
	for kind: StringName in ANCHORS:
		var n := Node3D.new()
		n.name = "Anchor_%s" % kind
		add_child(n)
		n.position = ANCHORS[kind]
		director.call(&"set_anchor", kind, n)
	Simulation.start()
	print("[audio-proof] GENESIS started")
