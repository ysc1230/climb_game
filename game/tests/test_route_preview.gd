extends RefCounted
## 루트 읽기(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.6): 탑에서 시작 지점까지 내려오는 카메라.
## 2026-11-24 사용자: "각 난이도를 시작할 때 가장 높은 탑 부분부터 천천히 화면을 내려오며 캐릭터가 있는 곳까지 내려와서 …
## 캐릭터가 위치하는 곳에 카메라가 위치하면 1초 정도 있다가 시작하자" → 처음 들어갈 때(full)는 탑에 0.8초, 초당 0.8m로
## 내려오고(1.2~4초), 캐릭터에서 1초 멈춘 뒤 끝난다. 다시 하기(full 아님)는 예전처럼 짧게(0.3초 + 1~2초 안, 끝 멈춤 없음).

var runner


func test_full_timing() -> void:
	var p := RoutePreview.new(4.0, 1.0)  # 3m
	runner.check(is_equal_approx(p.hold_top, 0.8) and is_equal_approx(p.pan, 3.0 / 0.8) and is_equal_approx(p.hold_end, 1.0), "탑 0.8초 · 3m를 3.75초 · 끝 1초")
	runner.check(is_equal_approx(p.dur, 0.8 + 3.75 + 1.0), "전체 %.2f초" % p.dur)
	runner.check(is_equal_approx(RoutePreview.new(1.5, 1.0).pan, 1.2), "짧아도 1.2초")
	runner.check(is_equal_approx(RoutePreview.new(9.0, 1.0).pan, 4.0), "길어도 4초")
	var flat := RoutePreview.new(1.0, 1.0)
	runner.check(is_equal_approx(flat.pan, 0.0) and flat.dur > 1.5, "탑이 이미 보여도 탑·끝에 머문다(%.2f초)" % flat.dur)


func test_retry_is_short() -> void:
	var p := RoutePreview.new(4.0, 1.0, false)
	runner.check(is_equal_approx(p.hold_top, 0.3) and is_equal_approx(p.hold_end, 0.0) and p.pan >= 1.0 and p.pan <= 2.0, "다시 하기: 0.3초 + %.2f초, 끝 멈춤 없음" % p.pan)


func test_cam_y_path() -> void:
	var p := RoutePreview.new(3.0, 1.0)
	runner.check(p.y() == 3.0, "처음은 탑")
	p.advance(0.79, false)
	runner.check(p.y() == 3.0, "0.8초까지 탑에 머묾")
	var prev := 3.0
	for i in 20:
		p.advance(p.pan / 20.0, false)
		var y := p.y()
		runner.check(y <= prev + 1e-6 and y >= 1.0 - 1e-6, "단조 감소 %s" % y)
		prev = y
	p.advance(0.02, false)
	runner.check(is_equal_approx(p.y(), 1.0) and not p.done(), "내려온 뒤 캐릭터에서 멈춤(아직 시작 안 함)")
	p.advance(0.9, false)
	runner.check(not p.done(), "1초가 안 됨")
	p.advance(0.2, false)
	runner.check(p.done() and p.y() == 1.0, "1초 뒤 시작")


func test_preview_skip_and_resume() -> void:
	var p := RoutePreview.new(3.0, 1.0)
	p.advance(0.5, false)
	runner.check(is_equal_approx(p.t, 0.5), "흐름")
	p.advance(0.5, true)
	runner.check(is_equal_approx(p.t, 0.5), "일시정지 중 그대로")
	runner.check(not p.done(), "아직")
	p.skip()
	runner.check(p.done() and p.y() == 1.0, "건너뛰면 끝·시작 높이")


func test_title_shows_until_end() -> void:
	var p := RoutePreview.new(3.0, 1.0)
	runner.check(p.title_alpha() > 0.5, "처음부터 문제 안내")
	p.advance(p.hold_top + p.pan + 0.5, false)
	runner.check(p.title_alpha() > 0.0, "캐릭터에서 멈춘 동안에도")
	p.advance(0.6, false)
	runner.check(p.title_alpha() == 0.0, "시작하면 사라짐")
