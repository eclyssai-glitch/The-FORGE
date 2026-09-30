// KORIUM UNIVERSE — shared cheap noise for the GENESIS shaders. Owner: art-director.
// Hash-based value noise only (no textures, no gradient tables); every loop has a small constant
// bound so the LOW profile stays cheap. Nothing here reads TIME.

float k_hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 k_hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float k_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 3D value noise in [0, 1], smooth (C1).
float k_vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = k_hash13(i);
	float n100 = k_hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = k_hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = k_hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = k_hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = k_hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = k_hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = k_hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// Fractal sum of value noise, normalised to [0, 1]. `octaves` is clamped to 1..5.
float k_fbm(vec3 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int i = 0; i < 5; i++) {
		if (i >= octaves) {
			break;
		}
		sum += amp * k_vnoise(p);
		norm += amp;
		p = p * 2.03 + vec3(17.1, 9.3, 4.7);
		amp *= 0.5;
	}
	return sum / max(norm, 1e-4);
}

// Ridge of value noise: 1 on the noise's mid iso-surface, falling off to 0 — thin crack/vein lines.
float k_ridge(vec3 p) {
	return 1.0 - abs(k_vnoise(p) * 2.0 - 1.0);
}

// Anti-aliased thin line from a ridge value (width in ridge units, widened by the pixel footprint).
float k_line(float ridge, float width) {
	float aa = max(fwidth(ridge), 1e-4);
	return smoothstep(1.0 - width - aa, 1.0 - width + aa * 0.5, ridge);
}

// 3D cellular (Voronoi) noise, 3x3x3 neighbourhood: returns (F1, F2, hash of the nearest cell).
// F2 - F1 is ~0 on cell borders: cracks, plates, kintsugi. `jitter` 0..1 (feature point spread).
vec3 k_voronoi(vec3 p, float jitter) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 h = k_hash33(i + g);
				vec3 r = g + 0.5 + (h - 0.5) * jitter - f;
				float d = dot(r, r);
				if (d < f1) {
					f2 = f1;
					f1 = d;
					id = h.z;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}
	return vec3(sqrt(f1), sqrt(f2), id);
}

// Like k_voronoi, but also returns the hash of the SECOND nearest cell: (F1, F2, id1, id2). The pair
// (id1, id2) names the border between two cells, so k_edge_hash() gives every border its own value
// (select only some cracks, seal others) — breaks the "every border is a line" grid look.
vec4 k_voronoi2(vec3 p, float jitter) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	float id1 = 0.0;
	float id2 = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 h = k_hash33(i + g);
				vec3 r = g + 0.5 + (h - 0.5) * jitter - f;
				float d = dot(r, r);
				if (d < f1) {
					f2 = f1;
					id2 = id1;
					f1 = d;
					id1 = h.z;
				} else if (d < f2) {
					f2 = d;
					id2 = h.z;
				}
			}
		}
	}
	return vec4(sqrt(f1), sqrt(f2), id1, id2);
}

// Stable 0..1 value of the border between two cells (symmetric in the pair).
float k_edge_hash(float id1, float id2) {
	return k_hash12(vec2(min(id1, id2), max(id1, id2)) * 113.7 + 1.3);
}

// Pin-point stars on a 3D grid (one cell lookup, no neighbours): returns brightness 0..1.
// `p` in cell units; `density` = probability a cell holds a star; `radius` in cell units, never
// thinner than ~0.8 of a pixel (`px` = one pixel in cell units) so they do not shimmer.
float k_stars(vec3 p, float density, float radius, float px) {
	vec3 cell = floor(p);
	vec3 h = k_hash33(cell);
	if (h.x > density) {
		return 0.0;
	}
	vec3 centre = cell + 0.5 + (h - 0.5) * 0.5;
	float d = length(p - centre);
	float r = max(radius, px * 0.8);
	float energy = (radius * radius) / (r * r);
	return (1.0 - smoothstep(r * 0.35, r, d)) * energy * (0.35 + 0.65 * fract(h.y * 7.31));
}

// Triangular dither in [-1, 1] / 255 from a screen coordinate (kills banding in dark gradients).
float k_dither(vec2 frag) {
	return (k_hash12(frag) + k_hash12(frag + 17.13) - 1.0) / 255.0;
}
