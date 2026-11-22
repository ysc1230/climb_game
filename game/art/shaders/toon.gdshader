// docs/22 방향: 무광, 2~3단계 큰 명암. 벽 모드(작업 4 §4.3): 합판 판넬(이음선·판마다 톤·가장자리 어둡게·얼룩)과
// 판 안의 규칙적인 볼트 구멍(살짝 파인 느낌). 매트 모드: 회색 천(이음선·결).
shader_type spatial;
render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(0.65, 0.42, 0.29, 1.0);
uniform vec4 shade : source_color = vec4(0.37, 0.38, 0.28, 1.0);
uniform float bands = 3.0;
uniform bool wall_pattern = false;
// 홀드 레진 질감(작업 4 §4.2): 점박이 얼룩(물체 좌표라 홀드와 같이 돈다).
uniform bool speckle = false;
// 텍스처 캐릭터(Tripo, docs/36): 색은 텍스처 × albedo, 그늘은 밝기 × shade_mult(색별 shade 대신).
uniform bool use_texture = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float shade_mult = 0.6;
// 텍스처 캐릭터 밝기(빛 세기 1에서 밝은 면 = 텍스처 × 이 값).
uniform float texture_light = 1.0;
uniform float bolt_spacing = 0.2;
uniform float panel_size = 1.2;
uniform bool mat_pattern = false;
uniform vec4 bolt_color : source_color = vec4(0.19, 0.16, 0.13, 1.0);

varying vec3 wpos;
varying vec3 lpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lpos = VERTEX;
}

void fragment() {
	vec3 c = albedo.rgb;
	if (use_texture) {
		c = texture(albedo_tex, UV).rgb * albedo.rgb;
	}
	if (wall_pattern) {
		vec2 pc = wpos.xy / panel_size;
		vec2 f = fract(pc);
		c *= 1.0 + (hash(floor(pc)) - 0.5) * 0.09;  // 판마다 조금 다른 톤
		float n = vnoise(wpos.xy * 2.5) * 0.6 + vnoise(wpos.xy * 11.0) * 0.4;
		c *= 0.93 + 0.12 * n;  // 얼룩
		vec2 e = min(f, 1.0 - f) * panel_size;
		float edge = min(e.x, e.y);
		c *= mix(0.84, 1.0, smoothstep(0.0, 0.14, edge));  // 판 가장자리 어둡게
		c = mix(c, c * 0.42, 1.0 - smoothstep(0.004, 0.009, edge));  // 이음선
		vec2 bc = fract(wpos.xy / bolt_spacing) - 0.5;
		float d = length(bc);
		float hole = 1.0 - smoothstep(0.045, 0.06, d);
		float rim = (1.0 - smoothstep(0.06, 0.085, d)) * (1.0 - hole);
		c = mix(c, bolt_color.rgb, hole * 0.9);
		c *= 1.0 + rim * clamp(-bc.y * 6.0, -0.12, 0.12);  // 파인 구멍: 아래 테는 밝고 위 테는 어둡다(빛이 위에서)
		c += (hash(floor(wpos.xy * 60.0)) - 0.5) * 0.03;
	}
	if (mat_pattern) {
		vec2 m = wpos.xz;
		vec2 mf = abs(fract(m + 0.5) - 0.5);
		c *= 0.94 + 0.08 * vnoise(m * 30.0) + (hash(floor(m * 140.0)) - 0.5) * 0.05;  // 천 결
		c = mix(c, c * 0.55, 1.0 - smoothstep(0.006, 0.014, min(mf.x, mf.y)));  // 1m 이음선
	}
	if (speckle) {
		vec3 q = floor(lpos * 140.0);
		float n = hash(q.xy + q.z * 17.0);
		c *= n > 0.9 ? 0.82 : (n < 0.08 ? 1.08 : 1.0);
	}
	ALBEDO = c;
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float q = floor(ndl * bands) / (bands - 1.0);
	q = clamp(q, 0.0, 1.0);
	vec3 tint = use_texture ? mix(vec3(shade_mult), vec3(1.0), q) : mix(shade.rgb / max(albedo.rgb, vec3(0.05)), vec3(1.0), q);
	// Godot 4의 LIGHT_COLOR는 빛 세기 × π다. 단색(벽·홀드·더미)은 이 밝기에 맞춰 색을 골라 그대로 두고, 텍스처 캐릭터는
	// π로 나눠 텍스처 색이 그대로 보이게 한다(2026-11-23: 피부 (0.78, 0.60, 0.46)이 (1.0, 0.97, 0.61)로 잘려 노랗게 보였음).
	float k = use_texture ? texture_light / PI : 0.9;
	DIFFUSE_LIGHT += tint * LIGHT_COLOR * ATTENUATION * k;
}
