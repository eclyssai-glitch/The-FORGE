// KORIUM UNIVERSE — MIKU's hair: one nebula mass of light whose longest strands become the relation
// threads. Owner: art-director.
// Mesh contract (HairRibbons.build / nebula): UV.x runs along the ribbon (0 root -> 1 tip), UV.y
// across (0..1); vertex colour alpha = per-strand opacity; CUSTOM0 = (1 for a link strand else 0,
// tuft share 0..1, strand length / longest strand, 0) — zeros when absent (all common strands).
// Additive, unshaded, no depth write. Common strands: pale gold (root) -> dusk rose -> lilac (tip),
// fine inner filaments, soft edges, the tip dissolving. Each tuft takes its own tone (rose <-> lilac
// <-> pearl, `tone_variation`) and opacity (`opacity_variation`), so the mass reads as locks, not a
// fan of identical ribbons. Link strands are thin bright fibres (a core of `link_core` of the
// ribbon) that run the full length and turn ICE -> `link_tip_color` at the tip — the colour the
// relation thread starts with (MaterialLibrary sets both from hair_link_tip()), so hair and graph
// are one fibre. Every strand leaves the single root: the first share of each strand is damped
// (`root_level`) so the stacked additive roots never bloom into a hot spot.
// `motion_time` (MotionClock) drives a slow shimmer toward the tips — never TIME. `reveal` grows
// the ribbon from root to tip (0..1); `link_pulse` (outside 0..1 = none) runs a gold pulse along the
// link strands only (the climax pulse leaving the hair before it runs along the threads).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 root_color : source_color;
uniform vec3 mid_color : source_color;
uniform vec3 tip_color : source_color;
// Alternative tones a tuft drifts toward (mid / tip), by tuft hash.
uniform vec3 tuft_mid_color : source_color;
uniform vec3 tuft_tip_color : source_color;
// Link strands: the colour along the outer half and at the very tip (= relation thread colour_from).
uniform vec3 link_color : source_color;
uniform vec3 link_tip_color : source_color;
uniform vec3 pulse_color : source_color;
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
// Per-tuft variation: tone shift and opacity range (0 = every tuft identical).
uniform float tone_variation : hint_range(0.0, 1.0) = 0.6;
uniform float opacity_variation : hint_range(0.0, 1.0) = 0.45;
// Root: brightness share at the root (all strands stack there) and the share over which it
// recovers to full.
uniform float root_level : hint_range(0.0, 1.0) = 0.3;
uniform float root_length : hint_range(0.01, 0.5) = 0.18;
// Link strands: brightness share, core width (share of the half-width) and where the ICE begins.
uniform float link_intensity = 1.35;
uniform float link_core : hint_range(0.05, 1.0) = 0.3;
uniform float link_color_from : hint_range(0.0, 1.0) = 0.45;
// Link pulse position along the strand (outside 0..1 = none) and its half-width / brightness.
uniform float link_pulse = -1.0;
uniform float link_pulse_width = 0.05;
uniform float link_pulse_intensity = 2.0;

varying vec4 v_custom;

void vertex() {
	v_custom = CUSTOM0;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float across = abs(v - 0.5) * 2.0;
	float link = clamp(v_custom.x, 0.0, 1.0);
	float tuft = clamp(v_custom.y, 0.0, 1.0);
	// Two independent hashes per tuft (and per material seed).
	float h1 = k_hash12(vec2(tuft * 37.13 + 1.7, seed * 3.1 + 0.4));
	float h2 = k_hash12(vec2(tuft * 19.71 + 8.3, seed * 1.9 + 5.2));

	// Across profile: a soft ribbon for common strands, a fine bright core for link strands.
	float edge_soft = 1.0 - smoothstep(1.0 - max(edge_softness, 1e-3), 1.0, across);
	float lc = max(link_core, 0.05);
	float core_d = across / lc;
	float edge_link = exp(-core_d * core_d * 2.5) + (1.0 - smoothstep(0.0, 1.0, across)) * 0.12;
	float edge = mix(edge_soft, edge_link, link);

	// Filaments: stripes across the width whose phase wanders slowly along the ribbon (per tuft).
	float wander = k_vnoise(vec3(u * 4.0, v * 1.5, seed * 7.1 + h1 * 11.0)) * 2.2;
	float stripe = 0.5 + 0.5 * cos((v * filaments + wander) * 6.2831853);
	float strands = mix(1.0, stripe * stripe * 1.35, filament_depth * (1.0 - link));

	// Slow shimmer travelling rootwards -> tipwards.
	float s = k_vnoise(vec3(u * 5.0 - motion_time * shimmer_speed * 5.0, v * 2.0, seed * 3.3 + h2 * 7.0));
	float glint = 1.0 + shimmer * (s * 2.0 - 1.0);

	// Colour: each tuft drifts toward its own mid / tip tone.
	float tv = clamp(tone_variation, 0.0, 1.0);
	vec3 mid_c = mix(mid_color, tuft_mid_color, h1 * tv);
	vec3 tip_c = mix(tip_color, tuft_tip_color, h2 * tv);
	vec3 col = mix(root_color, mid_c, smoothstep(0.05, 0.4, u));
	col = mix(col, tip_c, smoothstep(0.4, 0.85, u));
	// Link strands: rose -> ICE over the outer half -> the thread's colour at the tip.
	vec3 link_col = mix(root_color, mid_c, smoothstep(0.05, 0.3, u));
	link_col = mix(link_col, link_color, smoothstep(link_color_from, link_color_from + 0.3, u));
	link_col = mix(link_col, link_tip_color, smoothstep(0.82, 1.0, u));
	col = mix(col, link_col, link);

	// Root: all strands stack there — damped, recovering over root_length.
	float root_fade = smoothstep(0.0, 0.04, u) * mix(clamp(root_level, 0.0, 1.0), 1.0, smoothstep(0.0, max(root_length, 0.01), u));
	// Common tips dissolve; link strands carry on into their thread (vertex alpha keeps 0.8 there).
	float tip_fade = mix(1.0 - smoothstep(0.7, 1.0, u), 1.0, link);
	float opacity = mix(1.0, mix(1.0 - opacity_variation, 1.0, h2), 1.0 - link);
	float grown = 1.0 - smoothstep(reveal - 0.06, reveal, u);
	// Luminous leading edge while growing (reads as the strand being spun).
	// Gaussian front: d*d, never pow(d, 2.0) (d is signed; pow of a negative base is NaN).
	float front_d = (u - reveal) / 0.03;
	float front = (reveal < 0.999) ? exp(-front_d * front_d) * 1.5 : 0.0;
	float pulse_d = (u - link_pulse) / max(link_pulse_width, 1e-3);
	float pulse = exp(-pulse_d * pulse_d) * link * link_pulse_intensity * grown;

	float a = edge * strands * root_fade * tip_fade * opacity * (grown + front) * glint * COLOR.a;
	float level = mix(1.0, link_intensity, link);
	ALBEDO = (col * level + pulse_color * pulse) * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}
