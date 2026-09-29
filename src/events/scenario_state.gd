class_name ScenarioState
extends RefCounted
## Common base of every scenario's derived world (WorldState for ORIGIN CHAMBER, GenesisState
## for GENESIS). Pure reduction of simulation events: no nodes, no clocks, no randomness.
## `Simulation.state` is the active scenario's state as a ScenarioState (scenario-agnostic
## readers); scenario-specific readers use the typed `Simulation.world` / `Simulation.genesis`.
## Every "*_at" field is the simulation time of the event, or -1.0 if not yet happened.

var session_at := -1.0
var completed_at := -1.0


## Applies one event. Returns false for types the scenario does not know (ignored).
func apply(_e: SimEvent) -> bool:
	return false


## Index of the current phase in the scenario's Phase enum (0 = nothing happened yet).
func phase_index() -> int:
	return 0


## Uppercase phase name shown by the UI.
func phase_name() -> String:
	return ""


## True once the session of the scenario has completed.
func is_complete() -> bool:
	return completed_at >= 0.0


## Seconds elapsed since `at` at simulation time `now`; negative if not happened.
static func since(at: float, now: float) -> float:
	return now - at if at >= 0.0 else -1.0


## Smooth 0..1 ramp that starts at `at` and reaches 1 after `ramp` seconds (smoothstep).
## 0 when `at` has not happened (at < 0) or `now` is before it; a step when ramp <= 0.
static func progress(at: float, now: float, ramp: float) -> float:
	if at < 0.0 or now < at:
		return 0.0
	if ramp <= 0.0:
		return 1.0
	return smoothstep(0.0, 1.0, (now - at) / ramp)
