// 잉크 윤곽선(뒤집힌 껍데기). use_vertex_dir: 각진 메시는 중심 방향으로 키워 모서리 틈을 막는다.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 ink : source_color = vec4(0.188, 0.157, 0.125, 1.0);
uniform float width = 0.012;
uniform bool use_vertex_dir = false;
// 껍데기를 화면 깊이 쪽(카메라 반대)으로 미는 거리(m). 주름이 많은 메시(Tripo, docs/36)에서 껍데기 뒷면이
// 겉면을 뚫고 검은 점으로 보이는 것을 막는다. 0이면 예전과 같다.
uniform float depth_push = 0.0;
// 정점 색 R을 굵기에 곱한다(Tripo 모델, docs/37 §7): 엉덩이골·가랑이처럼 움푹한 곳에서 껍데기가 비쳐 검은 선이 생기는 곳은 0.
uniform bool use_vertex_width = false;

void vertex() {
	vec3 dir = use_vertex_dir ? normalize(VERTEX) : NORMAL;
	VERTEX += dir * width * (use_vertex_width ? COLOR.r : 1.0);
	if (depth_push > 0.0) {
		vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		v.z -= depth_push;
		POSITION = PROJECTION_MATRIX * v;
	}
}

void fragment() {
	ALBEDO = ink.rgb;
}
