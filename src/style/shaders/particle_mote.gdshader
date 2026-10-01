// KORIUM UNIVERSE — suspended motes (GPUParticles3D draw pass, QuadMesh).
// Owner: art-director. Colour fed by MaterialLibrary.mote() from Palette; no literals here.
//
// Unshaded, additive, billboarded per particle (keeps the particle scale and spin), round soft
// disc: ALPHA = COLOR.a * disc. COLOR is the particle colour ramp (vertex colour). A near fade
// (view distance, metres) keeps motes from blooming in front of the lens. No TIME: the particle
// system owns motion, so the look is a pure function of its state.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color;
// Near fade in view-space metres: x = fully hidden, y = fully visible.
uniform vec2 near_fade = vec2(3.5, 8.0);
// Visible disc radius (share of the quad's half-size) and share of instances drawn, both applied
// only from instance `keep_from` on: the first few motes of a cloud (seed, flares, glints) never
// shrink or drop out. MaterialLibrary.mote() tightens them for the GOLD family (fewer, smaller).
uniform float disc_radius : hint_range(0.1, 1.0) = 1.0;
uniform float keep_share : hint_range(0.0, 1.0) = 1.0;
uniform int keep_from = 8;

varying flat float v_drop;
varying flat float v_disc;

void vertex() {
	bool tuned = INSTANCE_ID >= keep_from;
	float h = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	v_drop = (tuned && h > keep_share) ? 1.0 : 0.0;
	v_disc = tuned ? clamp(disc_radius, 0.1, 1.0) : 1.0;
	// Billboard (particles): face the camera, keep the particle's spin (INSTANCE_CUSTOM.x) and scale.
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]),
			normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float c = cos(INSTANCE_CUSTOM.x);
	float s = sin(INSTANCE_CUSTOM.x);
	mat_world = mat_world * mat4(vec4(c, -s, 0.0, 0.0), vec4(s, c, 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	// 1 - smoothstep(lo, hi) instead of smoothstep(hi, lo): reversed edges are undefined in GLSL.
	if (v_drop > 0.5) {
		discard;
	}
	float disc = 1.0 - smoothstep(0.15 * v_disc, 0.5 * v_disc, length(UV - 0.5));
	float near = smoothstep(near_fade.x, max(near_fade.y, near_fade.x + 1e-3), -VERTEX.z);
	ALBEDO = color * COLOR.rgb;
	ALPHA = COLOR.a * disc * near;
}
