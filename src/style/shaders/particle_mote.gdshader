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

void vertex() {
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
	float disc = smoothstep(0.5, 0.15, length(UV - 0.5));
	float near = smoothstep(near_fade.x, max(near_fade.y, near_fade.x + 1e-3), -VERTEX.z);
	ALBEDO = color * COLOR.rgb;
	ALPHA = COLOR.a * disc * near;
}
