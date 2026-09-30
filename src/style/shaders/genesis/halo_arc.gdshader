// KORIUM UNIVERSE — MIKU's halo: an incomplete astrolabe arc behind the head. Owner: art-director.
// Drawn procedurally on a flat quad (QuadMesh/PlaneMesh, UV 0..1): a thin main arc with tapered
// ends, a fainter inner arc on the opposite side, and fine ticks just outside the main arc.
// Lines keep a constant on-screen width (fwidth), so the halo stays a hairline at any distance.
// Additive, unshaded, no depth write. Rotation is the node's (Palette.T_HALO_TURN per turn).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 color : source_color;
uniform vec3 inner_color : source_color;
uniform float intensity = 1.1;
// 0..1 presence (awakening swell).
uniform float strength : hint_range(0.0, 1.0) = 1.0;
// Radii as a share of the quad's half-size.
uniform float radius = 0.86;
uniform float inner_radius = 0.7;
// Line width in pixels.
uniform float line_px = 1.3;
// Share of the circle covered by the main / inner arc.
uniform float arc_span : hint_range(0.0, 1.0) = 0.68;
uniform float inner_span : hint_range(0.0, 1.0) = 0.4;
// Ticks (astrolabe graduation) along the main arc.
uniform float ticks = 72.0;
uniform float tick_strength : hint_range(0.0, 1.0) = 0.45;
// Breathing 0..1 (animator).
uniform float breath : hint_range(0.0, 1.0) = 0.5;

float arc_mask(float a, float span, float taper) {
	return smoothstep(0.0, taper, a) * (1.0 - smoothstep(span - taper, span, a));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = fract(k_angle01(p) + 0.25);
	float px = max(fwidth(r), 1e-5);
	// Line widths never collapse to zero (smoothstep with equal edges is undefined).
	float lw = max(line_px, 1e-3) * px;
	float tick_n = max(ticks, 1.0);

	float main_line = 1.0 - smoothstep(0.0, lw, abs(r - radius));
	float main_arc = main_line * arc_mask(a, arc_span, 0.14);

	float a2 = fract(a + 0.5 + arc_span * 0.5 - inner_span * 0.5);
	float inner_line = 1.0 - smoothstep(0.0, lw * 0.8, abs(r - inner_radius));
	float inner_arc = inner_line * arc_mask(a2, inner_span, 0.12) * 0.45;

	// Ticks: distance to the nearest graduation along the circle, in quad units -> pixels.
	float ta = fract(a * tick_n);
	float along = min(ta, 1.0 - ta) / tick_n * 6.2831853 * r;
	float tick = 1.0 - smoothstep(0.0, lw * 0.8, along);
	// Every sixth tick is longer (graduation rhythm).
	float major = step(mod(floor(a * tick_n + 0.5), 6.0), 0.5);
	float tick_len = mix(0.018, 0.04, major);
	tick *= smoothstep(radius + px * 2.0, radius + px * 3.0, r) * (1.0 - smoothstep(radius + tick_len - px, radius + tick_len, r));
	float tick_arc = tick * mix(0.55, 1.0, major) * arc_mask(a, arc_span, 0.14) * tick_strength;

	vec3 col = color * (main_arc + tick_arc) + inner_color * inner_arc;
	ALBEDO = col * intensity * (0.85 + 0.15 * breath);
	ALPHA = strength;
}
