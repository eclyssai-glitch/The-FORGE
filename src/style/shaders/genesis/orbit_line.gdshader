// KORIUM UNIVERSE — an orbit: a thin line of light that fades along the arc. Owner: art-director.
// Mesh contract (OrbitLine): a closed ribbon, UV.x along the orbit 0..1 (same direction as the
// body's motion), UV.y across 0..1. Brightest just behind the body (`head`, 0..1 = the body's
// position on the orbit), fading over `trail` of the loop to a faint `base`. `formation` 0..1 draws
// the orbit in behind the body. Additive, unshaded, no depth write. No TIME.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color;
uniform float intensity = 0.45;
uniform float head : hint_range(0.0, 1.0) = 0.0;
// Share of the loop over which the trail fades.
uniform float trail : hint_range(0.01, 1.0) = 0.55;
// Brightness of the rest of the loop (0..1 of the peak).
uniform float base : hint_range(0.0, 1.0) = 0.08;
uniform float formation : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float behind = fract(head - UV.x);
	float k = 1.0 - clamp(behind / trail, 0.0, 1.0);
	float lum = base + (1.0 - base) * k * k;
	// Draw-in: only the part of the loop behind the head that has been traced.
	float traced = 1.0 - smoothstep(formation - 0.02, formation, behind);
	if (formation >= 0.999) {
		traced = 1.0;
	}
	float across = 1.0 - abs(UV.y - 0.5) * 2.0;
	float profile = smoothstep(0.0, 0.8, across);
	ALBEDO = color * lum * intensity * profile * traced;
	ALPHA = 1.0;
}
