// The pour (fill_up): a part drawn only up to the concrete level, `fill_y`, in
// world space -- the level rises straight up whatever the part's orientation --
// and the cut closed by a flat surface at that level. The surface is the part's
// own inside seen through the cut: its faces are wound outward-front
// (MeshPrep.outward()), so what shows as a back face below the level can only
// be the inside, and it is lit as a horizontal top.
//
// The rest reproduces the StandardMaterial3D the part had (AnimationApplier.
// _fill_material()): albedo colour and texture, roughness, metallic/specular,
// UV1 triplanar in object or world space with Godot's own mapping (so swapping
// in and out of this material doesn't shift the texture), and a multiplied
// detail layer on UV2. Normal maps are left out for the few days a part is
// being poured.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform float fill_y = 1e9;
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool has_albedo_tex = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform bool has_roughness_tex = false;
uniform sampler2D roughness_tex : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform bool triplanar = false;
uniform bool world_triplanar = false;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform float uv1_sharpness = 1.0;
uniform bool has_detail = false;
uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool uv2_triplanar = false;
uniform vec3 uv2_scale = vec3(1.0);
uniform vec3 uv2_offset = vec3(0.0);
uniform float uv2_sharpness = 1.0;
// The fresh concrete at the top, a touch darker than the cured faces.
uniform float top_shade = 0.85;

varying vec3 world_pos;
varying vec3 uv1_pos;
varying vec3 uv1_w;
varying vec3 uv2_pos;
varying vec3 uv2_w;

vec3 blend_weights(vec3 n, float sharp) {
	vec3 w = pow(abs(n), vec3(sharp));
	return w / max(dot(w, vec3(1.0)), 1e-5);
}

// One per texture: GLSL here won't pass samplers with different hints through
// one function. Godot's own triplanar_texture(), sample for sample.
vec4 tri_albedo(vec3 p, vec3 w) {
	return texture(albedo_tex, p.xy) * w.z + texture(albedo_tex, p.xz) * w.y + texture(albedo_tex, p.zy * vec2(-1.0, 1.0)) * w.x;
}
vec4 tri_rough(vec3 p, vec3 w) {
	return texture(roughness_tex, p.xy) * w.z + texture(roughness_tex, p.xz) * w.y + texture(roughness_tex, p.zy * vec2(-1.0, 1.0)) * w.x;
}
vec4 tri_detail(vec3 p, vec3 w) {
	return texture(detail_tex, p.xy) * w.z + texture(detail_tex, p.xz) * w.y + texture(detail_tex, p.zy * vec2(-1.0, 1.0)) * w.x;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = world_triplanar ? normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz) : NORMAL;
	vec3 p = world_triplanar ? world_pos : VERTEX;
	uv1_w = blend_weights(n, uv1_sharpness);
	uv1_pos = (p * uv1_scale + uv1_offset) * vec3(1.0, -1.0, 1.0);
	uv2_w = blend_weights(NORMAL, uv2_sharpness);
	uv2_pos = (VERTEX * uv2_scale + uv2_offset) * vec3(1.0, -1.0, 1.0);
}

void fragment() {
	if (world_pos.y > fill_y) {
		discard;
	}
	vec4 col = albedo;
	if (has_albedo_tex) {
		col *= triplanar ? tri_albedo(uv1_pos, uv1_w) : texture(albedo_tex, UV * uv1_scale.xy + uv1_offset.xy);
	}
	if (has_detail) {
		vec4 d = uv2_triplanar ? tri_detail(uv2_pos, uv2_w) : texture(detail_tex, UV2 * uv2_scale.xy + uv2_offset.xy);
		col.rgb = mix(col.rgb, col.rgb * d.rgb, d.a);
	}
	float rough = roughness;
	if (has_roughness_tex) {
		rough *= triplanar ? tri_rough(uv1_pos, uv1_w).r : texture(roughness_tex, UV * uv1_scale.xy + uv1_offset.xy).r;
	}
	ALBEDO = col.rgb;
	ROUGHNESS = rough;
	METALLIC = metallic;
	SPECULAR = specular;
	if (!FRONT_FACING) {
		// Inside, seen through the cut: the top of the concrete.
		ALBEDO = col.rgb * top_shade;
		ROUGHNESS = 0.9;
		NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	}
}
