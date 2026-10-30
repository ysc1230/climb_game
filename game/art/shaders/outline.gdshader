// 잉크 윤곽선(뒤집힌 껍데기). use_vertex_dir: 각진 메시는 중심 방향으로 키워 모서리 틈을 막는다.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 ink : source_color = vec4(0.188, 0.157, 0.125, 1.0);
uniform float width = 0.012;
uniform bool use_vertex_dir = false;

void vertex() {
	vec3 dir = use_vertex_dir ? normalize(VERTEX) : NORMAL;
	VERTEX += dir * width;
}

void fragment() {
	ALBEDO = ink.rgb;
}
