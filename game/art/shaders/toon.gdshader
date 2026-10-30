// docs/22 방향: 무광, 2~3단계 큰 명암. 벽 모드에서는 볼트 구멍 격자와 종이결 노이즈를 더한다.
shader_type spatial;
render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(0.65, 0.42, 0.29, 1.0);
uniform vec4 shade : source_color = vec4(0.37, 0.38, 0.28, 1.0);
uniform float bands = 3.0;
uniform bool wall_pattern = false;
uniform float bolt_spacing = 0.2;
uniform vec4 bolt_color : source_color = vec4(0.19, 0.16, 0.13, 1.0);

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = albedo.rgb;
	if (wall_pattern) {
		vec2 g = wpos.xy / bolt_spacing;
		vec2 cell = fract(g) - 0.5;
		float d = length(cell);
		float bolt = 1.0 - smoothstep(0.055, 0.08, d);
		float grain = hash(floor(wpos.xy * 60.0)) * 0.06 - 0.03;
		c = mix(c + grain, bolt_color.rgb, bolt * 0.85);
	}
	ALBEDO = c;
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float q = floor(ndl * bands) / (bands - 1.0);
	q = clamp(q, 0.0, 1.0);
	vec3 tint = mix(shade.rgb / max(albedo.rgb, vec3(0.05)), vec3(1.0), q);
	DIFFUSE_LIGHT += tint * LIGHT_COLOR * ATTENUATION * 0.9;
}
