// KORIUM UNIVERSE — procedural sky of the UNIVERSE. Owner: game-engineer (style review: art-director).
// The background stays VOID. On top of it: sparse, cold, pin-point stars (two layers on a cube-face
// grid, sized in screen pixels so they never become blobs) and a barely visible distant dust band
// along one great circle. No nebulae, no colour: every colour is injected from Palette.
// Static (no TIME): the background is still drawn every frame (it depends on the camera), but the
// radiance cubemap (Sky.PROCESS_MODE_AUTOMATIC) is only re-rendered when a uniform changes.
// The radiance cubemap pass carries no stars (reflections are not speckled); it outputs VOID plus a
// faint vertical lift of the band colour (brighter above, none below the horizon), so metals
// reflecting the sky get a readable gradient instead of pure black.
// `disable_fog`: depth fog would otherwise fully cover the sky (fog_sky_affect = 1).
shader_type sky;
render_mode disable_fog;

uniform vec3 void_color : source_color;
uniform vec3 star_color : source_color;
uniform vec3 star_bright_color : source_color;
uniform vec3 band_color : source_color;

uniform float star_intensity = 0.55;
// Probability that a grid cell holds a star (layer 1 = brighter, layer 2 = faint dust of stars).
uniform float star_density = 0.045;
uniform float faint_density = 0.03;
// Cells across one cube face (angular size of a cell ≈ 90° / grid).
uniform float grid = 70.0;
uniform float faint_grid = 150.0;
// Star radius in screen pixels.
uniform float star_size_px = 0.9;
// Distant dust band (great circle): orientation, angular half-width (as dot product) and strength.
uniform vec3 band_normal = vec3(0.32, 0.9, -0.29);
uniform float band_width = 0.2;
uniform float band_strength = 0.04;
// Extra star density inside the band.
uniform float band_star_boost = 1.2;
// Radiance (reflection) cubemap only: strength of the band-colour gradient over VOID.
uniform float radiance_lift = 0.05;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// Direction -> (u, v in [-1, 1], face id 0..5) on the unit cube.
vec3 cube_face(vec3 d) {
	vec3 a = abs(d);
	if (a.x >= a.y && a.x >= a.z) {
		return vec3(d.z / a.x, d.y / a.x, d.x > 0.0 ? 0.0 : 1.0);
	} else if (a.y >= a.z) {
		return vec3(d.x / a.y, d.z / a.y, d.y > 0.0 ? 2.0 : 3.0);
	}
	return vec3(d.x / a.z, d.y / a.z, d.z > 0.0 ? 4.0 : 5.0);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// One star layer at grid position `p` on face `face` (px = one screen pixel in grid units,
// computed by the caller in uniform control flow). Returns (brightness, magnitude 0..1).
vec2 star_layer(vec2 p, float face, float px, float density, float seed) {
	vec2 cell = floor(p);
	vec3 h = hash33(vec3(cell, face * 131.0 + seed));
	if (h.x > density) {
		return vec2(0.0);
	}
	// Keep the star well inside its cell so it is never clipped by the cell border.
	vec2 c = cell + 0.5 + (h.yz - 0.5) * 0.5;
	float d = length(p - c) / (px * star_size_px);
	float mag = pow(hash13(vec3(cell.yx, face * 17.0 + seed * 7.0)), 5.0);
	return vec2(exp(-d * d) * (0.06 + 0.94 * mag), mag);
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = void_color + band_color * radiance_lift * smoothstep(-0.1, 0.8, EYEDIR.y);
	} else {
		vec3 dir = normalize(EYEDIR);
		float along = dot(dir, normalize(band_normal)) / band_width;
		float band = exp(-along * along);
		// Low-frequency modulation only: higher value-noise octaves show their grid as blocks.
		float dust = band * (0.4 + 0.6 * value_noise(dir * 2.2 + vec3(7.1, 3.3, 1.9)));

		vec3 f = cube_face(dir);
		vec2 p1 = (f.xy * 0.5 + 0.5) * grid;
		vec2 p2 = (f.xy * 0.5 + 0.5) * faint_grid;
		// One screen pixel in grid units, from the (seam-free) direction derivative: a face
		// coordinate changes 0.5·cells per unit of tangent, and the tangent grows ~(1 + u²)
		// with the angle, so stars keep the same pixel size across the whole face.
		float pix = max(length(fwidth(dir)), 1e-6) * 0.5 * (1.0 + 0.5 * dot(f.xy, f.xy));
		float px1 = pix * grid;
		float px2 = pix * faint_grid;
		vec2 s1 = star_layer(p1, f.z, px1, star_density * (1.0 + band_star_boost * band), 1.0);
		vec2 s2 = star_layer(p2, f.z, px2, faint_density * (1.0 + band_star_boost * band), 2.0);
		vec3 stars = s1.x * mix(star_color, star_bright_color, s1.y) + s2.x * 0.3 * star_color;

		COLOR = void_color + band_color * band_strength * dust + stars * star_intensity;
	}
}
