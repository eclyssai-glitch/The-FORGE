class_name HandPoses
extends RefCounted
## Finger poses shared by MIKU's own hands and the puppet hands (Loop 5). Owner: animator. Pure.
## A pose = curl 0..1 of [thumb, index, middle, ring, little] + spread 0..1. The springs of each
## finger (MikuMotor, PuppetHand) carry the fingers between poses with a small lead of the index
## and a lag of the little finger (overlap), never all at once.

const FINGER_COUNT := 5
## Curl at 1 of each segment (rad): base, middle, tip (the stand-in and MIKU's rig use 2).
const CURL_ANGLES: Array[float] = [1.25, 1.45, 1.0]
const THUMB_CURL_ANGLES: Array[float] = [0.75, 0.9, 0.8]
## Spread at 1 (rad) of each finger from the middle axis (thumb opens most).
const SPREAD_ANGLES: Array[float] = [0.55, 0.16, 0.0, -0.14, -0.28]

const POSES := {
	# MIKU: the natural cascade of a resting hand.
	&"relaxed": [[0.28, 0.2, 0.3, 0.38, 0.46], 0.2],
	# MIKU: the dancer's hand (middle finger a little lower, little finger lifted).
	&"ballet": [[0.32, 0.07, 0.34, 0.22, 0.1], 0.35],
	&"open": [[0.02, 0.0, 0.02, 0.04, 0.06], 0.7],
	# Conducting: soft, index leading.
	&"conduct": [[0.22, 0.02, 0.22, 0.32, 0.38], 0.45],
	# Calling: fingers gathered towards the palm (the beckon draws the thread).
	&"call": [[0.45, 0.62, 0.66, 0.7, 0.72], 0.1],
	&"hold": [[0.4, 0.38, 0.42, 0.46, 0.5], 0.25],
	&"cup": [[0.35, 0.3, 0.34, 0.38, 0.42], 0.15],
	&"pinch": [[0.58, 0.58, 0.32, 0.38, 0.42], 0.1],
	&"point": [[0.62, 0.0, 0.88, 0.92, 0.92], 0.0],
	&"fist": [[0.75, 0.97, 1.0, 1.0, 1.0], 0.0],
	&"push": [[0.08, 0.04, 0.05, 0.06, 0.08], 0.3],
	&"smooth": [[0.15, 0.06, 0.06, 0.08, 0.12], 0.1],
	# Lost composure: tense, half-closed, spread — the not-human hand.
	&"claw": [[0.42, 0.55, 0.6, 0.62, 0.62], 0.55],
	# Discard: the flick that releases.
	&"flick": [[0.0, -0.08, -0.06, -0.04, 0.0], 0.85],
}


static func has_pose(id: StringName) -> bool:
	return POSES.has(id)


## Curls of a pose (copy into `out`, 5 entries). Unknown ids give "relaxed".
static func curls(id: StringName, out: PackedFloat32Array) -> void:
	var p: Array = POSES.get(id, POSES[&"relaxed"])
	var c: Array = p[0]
	out.resize(FINGER_COUNT)
	for i in FINGER_COUNT:
		out[i] = float(c[i])


static func spread(id: StringName) -> float:
	var p: Array = POSES.get(id, POSES[&"relaxed"])
	return float(p[1])


## Spring frequency multiplier per finger: the index leads, the little finger trails.
static func finger_lag(i: int) -> float:
	return FINGER_LAG[clampi(i, 0, 4)]


const FINGER_LAG: Array[float] = [0.9, 1.15, 1.0, 0.88, 0.78]
