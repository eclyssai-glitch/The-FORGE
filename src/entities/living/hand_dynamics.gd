class_name HandDynamics
extends RefCounted
## Weight of a puppet hand (Loop 5). Owner: animator. Pure.
## A hand only moves under the force of its thread: with force > SLACK it follows its goal with a
## spring whose frequency falls with the square root of its mass, and its acceleration is capped
## at FORCE · force / mass — a heavy hand takes time to start and time to stop (it overshoots a
## little and settles). With a slack thread it coasts: its velocity decays (COAST_DRAG) and it
## stops where it is; it never goes to its goal by itself.

const SLACK := 0.03


## Advances `motion` (the hand's position spring) by dt towards `goal` under `force` (0..1+,
## thread tension × drive) for a hand of `mass`.
static func step(motion: SecondOrder3, goal: Vector3, force: float, mass: float, dt: float) -> void:
	if dt <= 0.0:
		return
	var m := maxf(mass, 0.05)
	if force <= SLACK:
		motion.v *= exp(-PuppetHand.COAST_DRAG * dt)
		motion.y += motion.v * dt
		motion.reset_target(motion.y)
		return
	motion.set_params(PuppetHand.BASE_F * sqrt(force) / sqrt(m), PuppetHand.ZETA, 0.0)
	motion.step_limited(goal, dt, PuppetHand.FORCE * force / m)


## Seconds a hand of `mass` needs to travel `distance` at full force (estimate used to time the
## beats that wait for the hand: ~ the spring's settle time, longer when the acceleration cap
## binds).
static func travel_time(distance: float, mass: float, force := 1.0) -> float:
	var m := maxf(mass, 0.05)
	var f := PuppetHand.BASE_F * sqrt(maxf(force, SLACK)) / sqrt(m)
	var a := PuppetHand.FORCE * maxf(force, SLACK) / m
	return maxf(1.1 / f, 2.0 * sqrt(maxf(distance, 0.0) / a))
