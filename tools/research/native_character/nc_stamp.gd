class_name NCStamp
extends SkeletonModifier3D
## SPIKE — a GDScript SkeletonModifier3D that only timestamps its place in the stack. Proves custom
## (own) modifiers run inside the native pipeline in child order, and lets the spike time the stack.

var stamp_us := 0


func _process_modification_with_delta(_delta: float) -> void:
	stamp_us = Time.get_ticks_usec()
