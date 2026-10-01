// KORIUM UNIVERSE — a relation thread (link): a fibre of light prolonging MIKU's hair.
// Owner: art-director. Mesh contract (RelationThread, `build_crossed` or `build`): ribbon(s), UV.x
// from the source (0, hair end) to the target (1, body), UV.y across 0..1. Colour runs
// `color_from` (the hair tip's lilac) to `color_to` (the target's family: ICE for moons, GOLD for
// the forming planet...). `woven` 0..1 spins the thread out from the source; `pulse` 0..1 is the
// position of a travelling pulse (a backlink forming) — outside 0..1 there is no pulse.
// A fibre, never a strap: a core of ~`line_px` pixels is cut across the ribbon (constant on screen
// at any distance), each ribbon is weighted by how squarely it faces the camera (n.v^2: of two
// crossed ribbons the one turning edge-on hands the line to the other, so the sum stays even and
// no flat band ever shows), and the fibre thins and fades out near both bodies.
// Additive, unshaded, no depth write, no TIME.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color_from : source_color;
uniform vec3 color_to : source_color;
uniform vec3 pulse_color : source_color;
uniform float intensity = 0.4;
uniform float woven : hint_range(0.0, 1.0) = 1.0;
uniform float pulse = -1.0;
uniform float pulse_width = 0.05;
uniform float pulse_intensity = 2.2;
// Core width in pixels (at mid-thread; it thins toward both ends) and the soft glow around it.
uniform float line_px = 1.5;
uniform float glow = 0.22;
// Shares of the thread over which it appears from the source (x) and vanishes into the target (y).
uniform vec2 end_fade = vec2(0.1, 0.16);

void fragment() {
	float u = UV.x;
	float nv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float facing = nv * nv;
	// Thin at both ends (a fibre, not a pipe), fullest a little after the source.
	float ends = smoothstep(0.0, max(end_fade.x, 1e-3), u) * (1.0 - smoothstep(1.0 - max(end_fade.y, 1e-3), 1.0, u));
	float taper = ends * (0.75 + 0.25 * sin(u * 3.14159));
	// Constant pixel core across the ribbon, thinner near the ends.
	float d_px = abs(UV.y - 0.5) / max(fwidth(UV.y), 1e-5);
	float half_w = max(line_px, 0.5) * mix(0.35, 0.5, ends);
	float core = 1.0 - smoothstep(half_w - 0.5, half_w + 0.75, d_px);
	float halo_d = d_px / max(half_w * 3.5, 1e-3);
	float profile = (core + exp(-halo_d * halo_d) * glow) * facing;

	float spun = 1.0 - smoothstep(woven - 0.03, woven, u);
	// Gaussians as d*d, never pow(d, 2.0): d is signed and pow of a negative base is NaN.
	float front_d = (u - woven) / 0.02;
	float front = (woven < 0.999) ? exp(-front_d * front_d) * 1.8 : 0.0;
	float pulse_d = (u - pulse) / max(pulse_width, 1e-3);
	float p = exp(-pulse_d * pulse_d);

	vec3 col = mix(color_from, color_to, smoothstep(0.1, 0.9, u));
	vec3 e = col * intensity * taper * spun + pulse_color * (p * pulse_intensity * spun + front) * ends;
	ALBEDO = e * profile;
	ALPHA = 1.0;
}
