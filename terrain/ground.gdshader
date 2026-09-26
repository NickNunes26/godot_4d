// Ground material for ConstructionTerrain.
//
// Geometry: a flat PlaneMesh whose vertices sit exactly on the height grid;
// the vertex stage lifts each one to its height (texelFetch, no filtering) and
// derives the normal from its neighbours, so no mesh is ever stored on disk.
//
// Colour: far away, the orthophoto (detail layer inside its square, context
// layer elsewhere), graded like the reference render kit -- saturation x1.25,
// value x0.72, then a curve that compresses highlights (burnt summer fields
// otherwise read as white). Close to the camera (35 -> 160 m) it blends into
// tiled PBR textures: leaf litter on flat ground, rock on slopes (normal.y
// 0.93 -> 0.70), tinted 45 % towards the orthophoto and darkened.
//
// Platforms (TerrainGrading): inside `grading_rect` each grid point carries up
// to two height changes, each tagged with its platform. A change is applied
// times that platform's timeline progress, so the ground morphs from natural to
// levelled during its earthworks. Levelled ground and its banks are drawn as
// bare earth (a gravelly tint of the rock texture near the camera).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform int grid_n = 2;
uniform float cell = 5.0;

uniform bool has_context = false;
uniform sampler2D ortho_context : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 context_rect = vec4(0.0); // x0, z0 (north edge), x1, z1 in terrain-local metres
uniform bool has_detail = false;
uniform sampler2D ortho_detail : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 detail_rect = vec4(0.0);
uniform vec3 fallback_color : source_color = vec3(0.30, 0.33, 0.22);

uniform bool grade_ortho = true;
uniform float ortho_saturation = 1.25;
uniform float ortho_value = 0.72;

uniform bool use_near = false;
uniform sampler2D leaves_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaves_roughness : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaves_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float leaves_tile = 3.0; // metres per texture repeat
uniform float rock_tile = 4.0;
uniform float near_start = 35.0;
uniform float near_end = 160.0;
uniform float slope_flat = 0.93;
uniform float slope_steep = 0.70;
uniform float near_tint = 0.45;

uniform bool has_grading = false;
uniform sampler2D grading : filter_nearest, repeat_disable; // RGBAF, see TerrainGrading
uniform ivec4 grading_rect = ivec4(0); // first column, first row, columns, rows
uniform float grade_progress[16];
uniform float grade_bare[16];
uniform vec3 earth_color : source_color = vec3(0.55, 0.44, 0.31);

varying vec2 terrain_xz;
varying float up_y;
varying float earth;

// Code: platform slot + 1 (0 = none), + 0.5 inside the platform's footprint.
int slot_of(float code) {
	return int(floor(code)) - 1;
}

float slot_progress(float code) {
	int i = slot_of(code);
	return i < 0 ? 0.0 : grade_progress[min(i, 15)];
}

float slot_earth(float change, float code) {
	int i = slot_of(code);
	if (i < 0) return 0.0;
	float w = fract(code) > 0.25 ? 1.0 : clamp(abs(change) / 0.3, 0.0, 1.0);
	return w * grade_progress[min(i, 15)] * grade_bare[min(i, 15)];
}

vec4 grading_at(ivec2 ij) {
	ivec2 g = ij - grading_rect.xy;
	if (!has_grading || g.x < 0 || g.y < 0 || g.x >= grading_rect.z || g.y >= grading_rect.w) {
		return vec4(0.0);
	}
	return texelFetch(grading, g, 0);
}

float h_at(ivec2 ij) {
	ij = clamp(ij, ivec2(0), ivec2(grid_n - 1));
	float h = texelFetch(heightmap, ij, 0).r;
	vec4 t = grading_at(ij);
	return h + t.r * slot_progress(t.g) + t.b * slot_progress(t.a);
}

void vertex() {
	float half_n = float(grid_n - 1) * 0.5;
	ivec2 ij = ivec2(round(VERTEX.xz / cell + vec2(half_n)));
	float hl = h_at(ij + ivec2(-1, 0));
	float hr = h_at(ij + ivec2(1, 0));
	float hn = h_at(ij + ivec2(0, -1)); // row - 1 = north = -Z
	float hs = h_at(ij + ivec2(0, 1));
	VERTEX.y = h_at(ij);
	NORMAL = normalize(vec3(hl - hr, 2.0 * cell, hn - hs));
	TANGENT = normalize(vec3(2.0 * cell, hr - hl, 0.0));
	BINORMAL = normalize(cross(NORMAL, TANGENT));
	terrain_xz = VERTEX.xz;
	up_y = NORMAL.y;
	vec4 t = grading_at(clamp(ij, ivec2(0), ivec2(grid_n - 1)));
	earth = max(slot_earth(t.r, t.g), slot_earth(t.b, t.a));
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

vec3 sat_val(vec3 c, float s, float v) {
	vec3 hsv = rgb2hsv(max(c, vec3(0.0)));
	hsv.y = clamp(hsv.y * s, 0.0, 1.0);
	hsv.z *= v;
	return hsv2rgb(hsv);
}

// Piecewise-linear version of the kit's combined curve: (0,0) (0.10,0.09) (0.25,0.16) (1,0.45).
float curve(float x) {
	if (x < 0.10) return x * 0.9;
	if (x < 0.25) return 0.09 + (x - 0.10) * (0.07 / 0.15);
	return 0.16 + (min(x, 1.0) - 0.25) * (0.29 / 0.75);
}

vec2 rect_uv(vec4 r, vec2 xz) {
	return (xz - r.xy) / (r.zw - r.xy);
}

bool inside(vec2 uv) {
	return uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0;
}

void fragment() {
	vec3 ortho = fallback_color;
	bool any_ortho = false;
	if (has_context) {
		vec2 uv = rect_uv(context_rect, terrain_xz);
		if (inside(uv)) {
			ortho = texture(ortho_context, uv).rgb;
			any_ortho = true;
		}
	}
	if (has_detail) {
		vec2 uv = rect_uv(detail_rect, terrain_xz);
		if (inside(uv)) {
			// Fade the last 3 % of the detail square into the context layer.
			vec2 edge = min(uv, 1.0 - uv);
			float w = any_ortho ? clamp(min(edge.x, edge.y) / 0.03, 0.0, 1.0) : 1.0;
			ortho = mix(ortho, texture(ortho_detail, uv).rgb, w);
			any_ortho = true;
		}
	}
	if (grade_ortho && any_ortho) {
		ortho = sat_val(ortho, ortho_saturation, ortho_value);
		ortho = vec3(curve(ortho.r), curve(ortho.g), curve(ortho.b));
	}

	float rough = 0.92;
	vec3 albedo = ortho;
	vec3 earth_col = earth_color;
	// The weight is interpolated across 5 m triangles; sharpen it into an edge.
	float earth_w = smoothstep(0.25, 0.75, earth);
	if (use_near) {
		float dist = length(VERTEX);
		float far_t = clamp((dist - near_start) / (near_end - near_start), 0.0, 1.0);
		float slope_t = clamp((up_y - slope_flat) / (slope_steep - slope_flat), 0.0, 1.0);
		vec2 luv = terrain_xz / leaves_tile;
		vec2 ruv = terrain_xz / rock_tile;
		vec3 near_col = mix(texture(leaves_albedo, luv).rgb, texture(rock_albedo, ruv).rgb, slope_t);
		near_col = sat_val(mix(near_col, ortho, near_tint), 0.85, 0.75);
		albedo = mix(near_col, ortho, far_t);
		rough = mix(texture(leaves_roughness, luv).r, texture(rock_roughness, ruv).r, slope_t);
		NORMAL_MAP = mix(texture(leaves_normal, luv).rgb, texture(rock_normal, ruv).rgb, slope_t);
		NORMAL_MAP_DEPTH = 1.0 - far_t;
		if (earth_w > 0.0) {
			// Gravelly bare earth: the rock texture's detail carried on the earth colour.
			vec3 rock = texture(rock_albedo, ruv).rgb;
			float lum = dot(rock, vec3(0.299, 0.587, 0.114));
			earth_col = mix(earth_col * (0.55 + lum), earth_col, far_t);
			NORMAL_MAP = mix(NORMAL_MAP, texture(rock_normal, ruv).rgb, earth_w);
		}
	}
	albedo = mix(albedo, earth_col, earth_w);
	rough = mix(rough, 0.95, earth_w);
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = 0.2;
}
