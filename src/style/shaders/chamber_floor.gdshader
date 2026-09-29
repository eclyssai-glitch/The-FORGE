// KORIUM UNIVERSE — chamber floor (CylinderMesh disc). Owner: art-director.
// Almost black, rough, with a faint glossy reflection of the lit structure. Towards the rim the
// albedo and specular fade to zero (edge_fade, share of the radius), so the disc never ends in a
// visible lit edge: it dissolves into the void.
//
// Radius comes from the UVs, independent of the disc size: Godot's CylinderMesh maps the top cap to
// a disc centred at (0.25, 0.75) with UV radius 0.25 (guarded by tests/unit/test_ui_theme.gd).
// The side wall and the bottom cap are treated as rim (fully faded). No textures; no literals of
// colour (floor_color is fed from Palette by MaterialLibrary).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 floor_color : source_color;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.18;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.55;
// Radius share where the fade starts (x) and where albedo/specular reach zero (y).
uniform vec2 edge_fade = vec2(0.85, 1.0);

// 1 on the top cap, 0 on the side wall and bottom cap (flat per face).
varying flat float v_top;

void vertex() {
	v_top = step(0.5, NORMAL.y);
}

void fragment() {
	float radius = mix(1.0, length(UV - vec2(0.25, 0.75)) * 4.0, v_top);
	float keep = 1.0 - smoothstep(edge_fade.x, edge_fade.y, radius);
	ALBEDO = floor_color * keep;
	METALLIC = 0.0;
	SPECULAR = specular_amount * keep;
	ROUGHNESS = roughness_amount;
}
