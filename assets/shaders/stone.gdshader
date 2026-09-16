shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

// Stylised cave stone.
//
// Triplanar because every slab is a unit cube scaled to size by a MultiMesh, so its UVs
// are stretched by wildly different amounts and a flat UV map smears.
//
// The lighting is deliberately banded rather than smooth. A continuous falloff on a
// low-contrast stone texture is what made the cave read as mush; quantising it gives each
// face a flat, readable value so a racer can tell surfaces apart at a glance -- which is
// the whole job of the art in a game about reorienting yourself.

uniform vec4 tint : source_color = vec4(0.8, 0.64, 0.42, 1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float uv_scale = 0.45;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.55;
uniform float bands : hint_range(2.0, 8.0) = 4.0;
uniform float band_softness : hint_range(0.0, 1.0) = 0.35;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.30;
uniform vec4 rim_color : source_color = vec4(0.75, 0.85, 1.0, 1.0);
uniform float texture_contrast : hint_range(0.0, 2.0) = 0.85;

varying vec3 world_pos;
varying vec3 world_norm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_norm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Sharp triplanar blend. A high exponent keeps the seams tight instead of cross-fading a
// third of every face into a blur.
vec3 blend_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(8.0));
	return w / max(w.x + w.y + w.z, 0.0001);
}

vec3 triplanar(sampler2D tex, vec3 p, vec3 w, float s) {
	return texture(tex, p.zy * s).rgb * w.x
		 + texture(tex, p.xz * s).rgb * w.y
		 + texture(tex, p.xy * s).rgb * w.z;
}

void fragment() {
	vec3 w = blend_weights(world_norm);
	vec3 tex = triplanar(albedo_tex, world_pos, w, uv_scale);

	// Push the texture around mid grey so detail stays visible without muddying the tint.
	tex = mix(vec3(0.5), tex, texture_contrast);
	ALBEDO = tint.rgb * tex * 2.0;

	vec3 nm = triplanar(normal_tex, world_pos, w, uv_scale) * 2.0 - 1.0;
	NORMAL_MAP = normalize(mix(vec3(0.0, 0.0, 1.0), nm, normal_strength)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	ROUGHNESS = 1.0;
	SPECULAR = 0.0;

	// A cool rim picks silhouettes out against the surface behind them, which is what
	// stops corridors reading as one flat wash of colour.
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	EMISSION = rim_color.rgb * fres * rim_strength;
}

void light() {
	float ndotl = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	float stepped = floor(ndotl * bands) / bands;
	// band_softness keeps a little of the smooth falloff so the bands read as stylisation
	// rather than as a rendering artefact.
	float shaded = mix(stepped, ndotl, band_softness);
	DIFFUSE_LIGHT += shaded * ATTENUATION * LIGHT_COLOR * ALBEDO;
}
