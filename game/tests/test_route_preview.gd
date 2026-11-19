extends RefCounted
## 루트 읽기(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.6): 탑에서 시작 지점까지 1~2초 내려오는 카메라.

var runner


func test_duration() -> void:
	runner.check(is_equal_approx(RoutePreview.duration(0.5), 1.0), "짧으면 1초")
	runner.check(is_equal_approx(RoutePreview.duration(2.25), 1.5), "2.25m 1.5초")
	runner.check(is_equal_approx(RoutePreview.duration(6.0), 2.0), "길어도 2초")


func test_cam_y_path() -> void:
	var dur := RoutePreview.duration(2.0)
	runner.check(RoutePreview.cam_y(0.0, 3.0, 1.0, dur) == 3.0, "처음은 탑")
	runner.check(RoutePreview.cam_y(0.29, 3.0, 1.0, dur) == 3.0, "0.3초까지 탑에 머묾")
	runner.check(RoutePreview.cam_y(dur, 3.0, 1.0, dur) == 1.0, "끝은 시작")
	var prev := 3.0
	for i in 20:
		var y := RoutePreview.cam_y(0.3 + (dur - 0.3) * i / 19.0, 3.0, 1.0, dur)
		runner.check(y <= prev + 1e-6 and y >= 1.0 - 1e-6 and y <= 3.0 + 1e-6, "단조 감소 %s" % y)
		prev = y


func test_preview_skip_and_resume() -> void:
	var p := RoutePreview.new(3.0, 1.0)
	p.advance(0.5, false)
	runner.check(is_equal_approx(p.t, 0.5), "흐름")
	p.advance(0.5, true)
	runner.check(is_equal_approx(p.t, 0.5), "일시정지 중 그대로")
	runner.check(not p.done(), "아직")
	p.skip()
	runner.check(p.done() and p.y() == 1.0, "건너뛰면 끝·시작 높이")
