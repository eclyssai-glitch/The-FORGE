// KORIUM UNIVERSE — emissive heart of the origin core. Owner: art-director.
// EMBER only with energy: at energy 0 the heart is black (the dormant core carries no accent).
// `pulse` (0..1) is driven by the animator from Simulation.time (no TIME here: pause/seek safe).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded, shadows_disabled;

uniform vec3 ember_color : source_color;
uniform vec3 ember_deep_color : source_color;
uniform float energy : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float peak = 2.2;

void fragment() {
	float e = clamp(energy, 0.0, 1.0);
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// Hot centre, deeper edges: reads as a volume, not a flat disc.
	vec3 col = mix(ember_deep_color, ember_color, nv * nv);
	float intensity = e * mix(0.45, 1.0, nv) * (0.7 + 0.3 * clamp(pulse, 0.0, 1.0)) * peak;
	ALBEDO = col * intensity;
}
