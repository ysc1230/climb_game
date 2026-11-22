extends RefCounted
## 캐릭터 고르기 미리보기 카메라(2026-11-23 사용자 "회전은 멈춰 있어, 내가 할 수 있도록 … 줌인 줌아웃도 내가 하게").
## 확대·축소는 범위 안에서만, 전신이 다 보일 때는 위아래로 옮기지 않고, 가까이 가면 머리~발까지 옮겨 볼 수 있다.

var runner
const HOME := preload("res://scenes/home.gd")


func test_look_view_clamps_zoom_and_pan() -> void:
	runner.check(is_equal_approx(HOME.look_view(9.0, 0.0).x, HOME.LOOK_DIST_MAX) and is_equal_approx(HOME.look_view(0.1, 0.0).x, HOME.LOOK_DIST_MIN), "확대·축소 범위 %.1f~%.1f" % [HOME.LOOK_DIST_MIN, HOME.LOOK_DIST_MAX])
	runner.check(HOME.look_view(HOME.LOOK_DIST_MAX, 0.5).y == 0.0 and HOME.look_view(HOME.LOOK_DIST_MAX, -0.5).y == 0.0, "전신(가장 멀리)에서는 가운데 고정")
	runner.check(is_equal_approx(HOME.look_view(HOME.LOOK_DIST_MIN, 2.0).y, 0.68) and is_equal_approx(HOME.look_view(HOME.LOOK_DIST_MIN, -2.0).y, -0.75), "가장 가까이: 머리(0.68)~발(−0.75)까지")
	var mid := HOME.look_view((HOME.LOOK_DIST_MIN + HOME.LOOK_DIST_MAX) * 0.5, 2.0)
	runner.check(mid.y > 0.2 and mid.y < 0.68, "중간 거리는 옮길 수 있는 범위도 중간 %.2f" % mid.y)
