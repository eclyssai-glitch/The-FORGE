// KORIUM UNIVERSE — a relation thread (link): a fibre of light prolonging MIKU's hair.
// Owner: art-director. Mesh contract (RelationThread): ribbon/tube, UV.x from the source (0, hair
// end) to the target (1, body), UV.y across 0..1. Colour runs `color_from` (the hair tip's lilac)
// to `color_to` (the target's family: ICE for moons, GOLD for the forming planet...). `woven` 0..1
// spins the thread out from the source; `pulse` 0..1 is the position of a travelling pulse (a
// backlink forming) — outside 0..1 there is no pulse. Additive, unshaded, no depth write, no TIME.
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

void fragment() {
	float u = UV.x;
	float across = 1.0 - abs(UV.y - 0.5) * 2.0;
	float profile = smoothstep(0.0, 0.9, across);
	// Thin at both ends (a fibre, not a pipe), fullest a little after the source.
	float taper = smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.9, 1.0, u)) * (0.75 + 0.25 * sin(u * 3.14159));
	float spun = 1.0 - smoothstep(woven - 0.03, woven, u);
	// Gaussians as d*d, never pow(d, 2.0): d is signed and pow of a negative base is NaN.
	float front_d = (u - woven) / 0.02;
	float front = (woven < 0.999) ? exp(-front_d * front_d) * 1.8 : 0.0;
	float pulse_d = (u - pulse) / max(pulse_width, 1e-3);
	float p = exp(-pulse_d * pulse_d);

	vec3 col = mix(color_from, color_to, smoothstep(0.1, 0.9, u));
	vec3 e = col * intensity * taper * spun + pulse_color * (p * pulse_intensity * spun + front);
	ALBEDO = e * profile;
	ALPHA = 1.0;
}
