// KORIUM UNIVERSE — MIKU's hair: ribbons of light that become the relation threads. Owner: art-director.
// Mesh contract (HairRibbons): UV.x runs along the ribbon (0 root -> 1 tip), UV.y across (0..1).
// Optional vertex colour alpha = per-strand opacity (1 when the mesh has none).
// Additive, unshaded, no depth write. Gradient pale gold (root) -> dusk rose -> lilac (tip); fine
// inner filaments; soft edges; a slow shimmer travelling toward the tips (`motion_time`, set from
// MotionClock — never TIME). `reveal` grows the ribbon from root to tip (0..1).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 root_color : source_color;
uniform vec3 mid_color : source_color;
uniform vec3 tip_color : source_color;
// Overall brightness (kept near 1: the hair glows, it never blooms out).
uniform float intensity = 0.75;
// Filaments across one ribbon.
uniform float filaments = 3.0;
// How much the filaments carve the ribbon (0 = flat ribbon, 1 = separate strands).
uniform float filament_depth : hint_range(0.0, 1.0) = 0.4;
// Across-ribbon softness (share of the half-width that fades).
uniform float edge_softness : hint_range(0.05, 1.0) = 0.7;
// Slow shimmer amplitude and speed (along the ribbon, toward the tips).
uniform float shimmer : hint_range(0.0, 1.0) = 0.3;
uniform float shimmer_speed = 0.06;
uniform float motion_time = 0.0;
// 0..1: how far the ribbon has grown from the root.
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
// Per-material seed so several ribbons do not shimmer in step.
uniform float seed = 0.0;

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float across = abs(v - 0.5) * 2.0;
	float edge = 1.0 - smoothstep(1.0 - edge_softness, 1.0, across);

	// Filaments: stripes across the width whose phase wanders slowly along the ribbon.
	float wander = k_vnoise(vec3(u * 4.0, v * 1.5, seed * 7.1)) * 2.2;
	float stripe = 0.5 + 0.5 * cos((v * filaments + wander) * 6.2831853);
	float strands = mix(1.0, pow(stripe, 2.0) * 1.35, filament_depth);

	// Slow shimmer travelling rootwards -> tipwards.
	float s = k_vnoise(vec3(u * 5.0 - motion_time * shimmer_speed * 5.0, v * 2.0, seed * 3.3));
	float glint = 1.0 + shimmer * (s * 2.0 - 1.0);

	vec3 col = mix(root_color, mid_color, smoothstep(0.05, 0.4, u));
	col = mix(col, tip_color, smoothstep(0.4, 0.85, u));

	float root_fade = smoothstep(0.0, 0.05, u);
	float tip_fade = 1.0 - smoothstep(0.7, 1.0, u);
	float grown = 1.0 - smoothstep(reveal - 0.06, reveal, u);
	// Luminous leading edge while growing (reads as the strand being spun).
	float front = (reveal < 0.999) ? exp(-pow((u - reveal) / 0.03, 2.0)) * 1.5 : 0.0;

	float a = edge * strands * root_fade * tip_fade * (grown + front) * glint * COLOR.a;
	ALBEDO = col * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}
