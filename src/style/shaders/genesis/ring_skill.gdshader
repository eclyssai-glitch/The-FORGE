// KORIUM UNIVERSE — a skill ring around a planet. Owner: art-director.
// Drawn procedurally on a flat quad (PlaneMesh, UV 0..1): radius = length(UV - 0.5) * 2, so the
// ring lives between `inner` and `outer` (shares of the quad's half-size). Fine bands of different
// brightness with dark gaps (radial UV), faintly golden. `formation` 0..1 sweeps the ring around
// its circle with a warm leading edge (the ring being laid down, not switched on).
// Additive, unshaded, double-sided, no depth write. No TIME.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 color : source_color;
uniform vec3 accent_color : source_color;
uniform float intensity = 0.4;
uniform float inner = 0.76;
uniform float outer = 1.0;
// Band frequency across the ring width.
uniform float bands = 11.0;
uniform float formation : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 0.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float t = (r - inner) / max(outer - inner, 1e-4);
	float px = max(fwidth(t), 1e-4);
	float inside = smoothstep(-px, px, t) * (1.0 - smoothstep(1.0 - px, 1.0 + px, t));

	// Bands: layered 1D noise across the width -> thin bright ribbons and dark gaps.
	float n1 = k_vnoise(vec3(t * bands, seed, 0.0));
	float n2 = k_vnoise(vec3(t * bands * 3.1, seed + 4.0, 0.0));
	float n3 = k_vnoise(vec3(t * bands * 7.3, seed + 9.0, 0.0));
	float density = smoothstep(0.25, 0.9, n1 * 0.55 + n2 * 0.3 + n3 * 0.15);
	// Soft falloff at both edges; the outer third slightly dimmer (ring thins outward).
	float edge = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.8, 1.0, t)) * mix(1.0, 0.7, t);

	float a = k_angle01(p);
	float swept = 1.0 - smoothstep(formation - 0.04, formation, a);
	// The sweep's start (angle 0) fades in while the ring forms (no hard cut at the seam); as the
	// front comes round to it the ring closes into one seamless band — at formation 1 every angle is
	// lit (the soft front edge used to leave the last 4 % before the seam dark: a hard radial cut).
	float closing = smoothstep(0.965, 1.0, formation);
	swept = mix(swept * smoothstep(0.0, 0.1, a), 1.0, closing);
	// Gaussian front: d*d, never pow(d, 2.0) (d is signed; pow of a negative base is NaN).
	float front_d = (a - formation) / 0.015;
	float front = (formation < 0.999) ? exp(-front_d * front_d) : 0.0;

	vec3 col = mix(color, accent_color, 0.35 + 0.35 * n2);
	float lum = density * edge * inside;
	ALBEDO = col * lum * intensity * swept + accent_color * front * inside * edge * 1.5;
	ALPHA = 1.0;
}
