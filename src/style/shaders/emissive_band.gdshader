// KORIUM UNIVERSE — thin emissive ring (verification scan ring, halos). Owner: art-director.
// Additive, unshaded, no depth write. Expects ring UVs with v across the band width (0..1);
// intensity falls off softly from the band centre so the ring never reads as a neon tube.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 color : source_color;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float intensity = 1.0;
uniform float softness : hint_range(0.05, 1.0) = 0.6;

void fragment() {
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float fall = smoothstep(0.0, softness, across);
	float s = clamp(strength, 0.0, 1.0);
	ALBEDO = color * intensity * fall * s;
	ALPHA = fall * s;
}
