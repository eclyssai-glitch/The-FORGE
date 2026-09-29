class_name InputTuning
extends RefCounted
## Shared input thresholds. One source for every consumer (Picker, CameraDirector), so a press
## is either a click or a drag for all of them — never both, never neither.

## Accumulated pointer travel (px, sum of every movement between press and release) from which a
## press stops being a click and becomes a camera drag. Accumulated, not net: a drag that returns
## to where it started is still a drag.
const DRAG_THRESHOLD_PX := 4.0


## True when the accumulated travel of a press makes it a drag (not a click).
static func is_drag(travel_px: float) -> bool:
	return travel_px >= DRAG_THRESHOLD_PX
