// KORIUM UNIVERSE — GENESIS sky: a deep nebula with a warm core behind MIKU. Owner: art-director.
// Fake volumetric nebula (domain-warped fbm) in indigo/violet, concentrated in a broad band and in a
// warm dusk-rose core around `warm_dir` (the backlight behind MIKU, seen from the FORGE camera:
// roughly world -Z, slightly above the horizon). Dark dust lanes cut the clouds. Three star layers
// (bright / field / galactic dust), pixel-sized so they never become blobs, warm and cool tints,
// the brightest with a subtle twinkle driven by `motion_time` (MotionClock — never TIME).
// Triangular dithering kills banding in the dark gradients. The radiance cubemap pass carries no
// stars and fewer octaves (reflections see the nebula's colour, not its speckle).
// Cost: `detail` octaves (LOW: 2–3, HIGH: 4–5); one warped fbm + one ridge for dust; 3 star lookups.
// With Sky.PROCESS_MODE_AUTOMATIC the radiance is re-rendered when a uniform changes: update
// `motion_time` at a reduced rate (or use PROCESS_MODE_INCREMENTAL / REALTIME) — see
// docs/VISUAL_DIRECTION.md.
shader_type sky;
render_mode disable_fog;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 deep_color : source_color;
uniform vec3 indigo_color : source_color;
uniform vec3 nebula_color : source_color;
uniform vec3 lilac_color : source_color;
uniform vec3 warm_color : source_color;
uniform vec3 core_color : source_color;
// Light of the warm core: pearl heart and gold body (the rose/lilac edges reuse warm/lilac).
uniform vec3 pearl_color : source_color;
uniform vec3 gold_color : source_color;
uniform vec3 star_color : source_color;
uniform vec3 star_warm_color : source_color;
uniform vec3 star_cool_color : source_color;

// Direction of the warm core (normalised in the shader).
uniform vec3 warm_dir = vec3(0.0, 0.22, -1.0);
// Angular spread of the warm glow, as 1 - cos(angle) (0.08 ≈ a 25° soft halo).
uniform float warm_spread = 0.08;
uniform float warm_intensity = 1.0;
// Hot centre of the core (kept soft: a presence behind MIKU, not a sun).
uniform float core_intensity = 1.0;
// Filaments of gas lit by the core (0 = smooth halo, which reads as mud under AgX).
uniform float filament_strength = 1.0;
uniform float nebula_intensity = 1.0;
uniform float nebula_scale = 2.4;
uniform float dust_strength : hint_range(0.0, 1.0) = 0.6;
// Tilt of the nebula band plane around the warm direction.
uniform vec3 band_axis = vec3(0.35, 1.0, 0.12);
uniform float band_width = 0.45;
uniform float star_intensity = 1.0;
uniform float twinkle : hint_range(0.0, 1.0) = 0.3;
uniform float motion_time = 0.0;
uniform int detail : hint_range(1, 5) = 4;
uniform float radiance_strength = 0.7;
uniform float dither_strength = 1.5;
// Global scale of the whole sky (the world may dim it per mode).
uniform float sky_energy = 1.0;

// Uniform directions are user-tunable: a null `warm_dir`, or a `band_axis` parallel to it, must not
// normalise a zero vector (NaN sky). Fallbacks only kick in for such degenerate values.
vec3 warm_axis() {
	return k_safe_normalize(warm_dir, vec3(0.0, 0.0, -1.0));
}

vec3 band_normal(vec3 wd) {
	vec3 axis = k_safe_normalize(band_axis, vec3(0.0, 1.0, 0.0));
	return k_safe_normalize(cross(wd, axis), k_safe_normalize(cross(wd, vec3(1.0, 0.0, 0.0)) + vec3(0.0, 1e-4, 0.0), vec3(0.0, 1.0, 0.0)));
}

vec3 nebula(vec3 dir, int oct, out float dust_mask, out float cloud_out) {
	vec3 wd = warm_axis();
	float c = dot(dir, wd);
	vec3 band_n = band_normal(wd);
	float band = 1.0 - abs(dot(dir, band_n));
	float band_env = smoothstep(1.0 - max(band_width, 1e-3), 1.0, band);
	float near = exp((c - 1.0) / max(warm_spread, 0.005));
	float wide = exp((c - 1.0) / max(warm_spread * 4.0, 0.02));
	float tight = exp((c - 1.0) / max(warm_spread * 0.2, 0.002));

	vec3 p = dir * nebula_scale;
	vec3 w = vec3(k_vnoise(p * 1.1), k_vnoise(p * 1.1 + 5.2), k_vnoise(p * 1.1 + 9.7));
	vec3 q = p * 1.6 + (w - 0.5) * 1.8;
	float dens = k_fbm(q, oct) + (k_vnoise(q * 4.3 + 1.7) - 0.5) * 0.12;
	float envelope = clamp(band_env * 0.8 + wide * 0.7, 0.0, 1.0);
	float cloud = smoothstep(0.42, 0.85, dens) * envelope;
	// The warm core is light, not paint: a pearl heart, a gold body, dusk rose and then lilac towards
	// the edges (a radial ramp), carried by filamentary gas lit from within (thin ridges of the warped
	// field at two scales) and cut by the dust lanes. A smooth halo alone turns to beige mud under AgX.
	// Filaments stream outwards from the core: noise in polar coordinates around warm_dir (fast
	// across the angle, slow along the radius), warped so they curl like gas and never read as rays.
	vec3 b1 = k_safe_normalize(cross(wd, vec3(0.0, 1.0, 0.0)) + vec3(1e-4), vec3(1.0, 0.0, 0.0));
	vec3 b2 = cross(wd, b1);
	vec3 tv = dir - wd * c;
	float rr = length(tv);
	vec2 ang = vec2(dot(tv, b1), dot(tv, b2)) / max(rr, 1e-4);
	vec3 sp = vec3(ang * 1.5, rr * 4.2) + (w - 0.5) * 1.8;
	float streak = pow(max(k_ridge(sp * 1.5 + 5.0), 0.0), 7.0);
	float iso = pow(max(k_ridge(q * 2.1 + 11.0), 0.0), 6.0) * 0.8 + pow(max(k_ridge(q * 4.7 + 3.0), 0.0), 10.0) * 0.35;
	float fil = mix(iso, streak, 0.4 * smoothstep(0.03, 0.14, rr)) * mix(0.5, 1.0, smoothstep(0.02, 0.2, rr)) * smoothstep(0.35, 0.7, dens + near * 0.2);
	float gas = smoothstep(0.3, 0.9, dens);
	vec3 ramp = mix(lilac_color * 0.55, warm_color, smoothstep(0.02, 0.3, near));
	ramp = mix(ramp, gold_color, smoothstep(0.3, 0.72, near));
	ramp = mix(ramp, mix(gold_color, pearl_color, 0.2), smoothstep(0.55, 1.0, tight));
	float structure = 0.25 + 0.55 * gas + fil * 1.6 * filament_strength;
	// Faux scattering: cloud close to the core takes the core's light; far cloud stays violet/indigo.
	float lit = clamp(near * smoothstep(0.35, 0.8, dens) * 1.3, 0.0, 1.0);

	float lanes = k_ridge(q * 1.7 + 4.0);
	dust_mask = smoothstep(0.55, 0.95, lanes) * smoothstep(0.45, 0.75, k_fbm(p * 0.9 + 3.0, 2)) * 0.8
			* clamp(envelope + near, 0.0, 1.0);
	cloud_out = cloud;

	// Base: deep space lifted to indigo inside the band and around the core.
	vec3 sky = mix(deep_color, indigo_color, clamp(band_env * 0.7 + wide * 0.6, 0.0, 1.0)) * 0.6;
	vec3 cloud_col = mix(nebula_color, lilac_color * 0.35, smoothstep(0.5, 1.0, cloud));
	cloud_col = mix(cloud_col, ramp * 0.5, lit);
	sky += cloud_col * cloud * 0.55 * nebula_intensity;
	sky += ramp * (near * 0.21 + wide * 0.02) * structure * warm_intensity;
	sky += mix(core_color, pearl_color, 0.15) * tight * 0.8 * core_intensity * (0.45 + 0.45 * gas + 0.8 * fil);
	sky *= 1.0 - dust_strength * dust_mask;
	return sky;
}

float star_layer(vec3 dir, float grid, float density, float radius, float px_ang, float seed) {
	vec3 p = dir * grid + seed;
	return k_stars(p, density, radius, px_ang * grid);
}

vec3 star_tint(vec3 dir, float grid, float seed) {
	float h = k_hash13(floor(dir * grid + seed) + 71.0);
	vec3 t = mix(star_cool_color, star_color, smoothstep(0.2, 0.5, h));
	return mix(t, star_warm_color, smoothstep(0.8, 0.98, h));
}

void sky() {
	vec3 dir = k_safe_normalize(EYEDIR, vec3(0.0, 0.0, -1.0));
	float dust = 0.0;
	float cloud = 0.0;
	if (AT_CUBEMAP_PASS) {
		vec3 n = nebula(dir, min(detail, 2), dust, cloud);
		COLOR = n * radiance_strength * sky_energy;
	} else {
		vec3 n = nebula(dir, detail, dust, cloud);
		float px_ang = max(length(fwidth(dir)), 1e-5);
		float veil = (1.0 - dust * 0.9) * (1.0 - cloud * 0.5);

		float s1 = star_layer(dir, 70.0, 0.05, 0.1, px_ang, 0.0);
		float tw = 1.0 + twinkle * sin(motion_time * 1.3 + k_hash13(floor(dir * 70.0)) * 40.0);
		float s2 = star_layer(dir, 190.0, 0.12, 0.09, px_ang, 17.0);
		vec3 wd = warm_axis();
		vec3 band_n = band_normal(wd);
		float band = smoothstep(1.0 - max(band_width, 1e-3) * 0.7, 1.0, 1.0 - abs(dot(dir, band_n)));
		float s3 = star_layer(dir, 460.0, 0.05 + 0.12 * band, 0.08, px_ang, 43.0);

		vec3 stars = star_tint(dir, 70.0, 0.0) * s1 * 1.6 * tw
				+ star_tint(dir, 190.0, 17.0) * s2 * 0.7
				+ star_color * s3 * 0.35;
		COLOR = (n + stars * star_intensity * veil) * sky_energy;
		// The dither may push a black pixel below zero; negative radiance feeds dark specks into glow.
		COLOR = max(COLOR + vec3(k_dither(FRAGCOORD.xy) * dither_strength), vec3(0.0));
	}
}
