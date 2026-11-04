shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.18, 0.78, 0.84, 0.82);
uniform vec4 mid_color : source_color = vec4(0.09, 0.58, 0.72, 0.90);
uniform vec4 deep_color : source_color = vec4(0.05, 0.40, 0.58, 0.96);
uniform vec4 foam_color : source_color = vec4(0.88, 0.98, 1.00, 0.95);
uniform float wave_speed : hint_range(0.1, 4.0) = 1.15;
uniform float wave_height : hint_range(0.0, 0.15) = 0.028;

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float wave_field(vec2 xz, float t) {
	float w1 = sin(xz.x * 1.45 + xz.y * 1.10 + t * 1.6) * 0.45;
	float w2 = cos(xz.x * 2.15 - xz.y * 1.85 + t * 1.25) * 0.35;
	float w3 = sin((xz.x - xz.y) * 3.40 - t * 2.1) * 0.20;
	return w1 + w2 + w3;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float h = wave_field(wp.xz, t) * wave_height;
	VERTEX.y += h;

	float eps = 0.12;
	float hx = wave_field(wp.xz + vec2(eps, 0.0), t) * wave_height;
	float hz = wave_field(wp.xz + vec2(0.0, eps), t) * wave_height;
	NORMAL = normalize(vec3(h - hx, eps, h - hz));
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * wave_speed;
	float dist = length(world_pos.xz);

	// Diorama radial depth transition: shallow turquoise near the islands, richer azure further out
	float near_island = 1.0 - smoothstep(6.0, 28.0, dist);
	float mid_band = 1.0 - smoothstep(14.0, 40.0, dist);

	float n1 = value_noise(world_pos.xz * 1.65 + vec2(t * 0.18, -t * 0.14));
	float n2 = value_noise(world_pos.xz * 3.80 - vec2(t * 0.24, t * 0.20));
	float caustic = clamp(n1 * 0.6 + n2 * 0.55, 0.0, 1.0);

	vec3 col = mix(deep_color.rgb, mid_color.rgb, mid_band);
	col = mix(col, shallow_color.rgb, near_island * (0.65 + 0.35 * caustic));

	// Subtle sunlit caustic ribbons & specular sparkles matching map_base.png
	float sparkle = smoothstep(0.79, 0.95, n1 * 0.52 + n2 * 0.58);
	col = mix(col, foam_color.rgb, sparkle * 0.28);

	// Soft foam ring inside the central canal & around island perimeters
	float canal_ring = 0.0;
	col = mix(col, foam_color.rgb, canal_ring * (0.5 + 0.5 * sin(dist * 6.0 - t * 2.2)));

	ALBEDO = col;
	ROUGHNESS = mix(0.09, 0.18, sparkle);
	METALLIC = 0.06;
	SPECULAR = 0.72;
	EMISSION = foam_color.rgb * (sparkle * 0.10);
	ALPHA = mix(deep_color.a, shallow_color.a, near_island * 0.85);
}
