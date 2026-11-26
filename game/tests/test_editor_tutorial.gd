extends RefCounted
## 만들기 튜토리얼(EditorTutorial, 2026-11-26 사용자 "만들기도 튜토리얼을 만들어줘"): 따라 하기 8단계.
## 단계마다 실제로 해야 넘어가고, 안내대로 하면 막는 것 없는 첫 문제가 된다.

var runner


func _step_id(t: EditorTutorial) -> String:
	return str(t.current().id) if not t.done else "done"


func test_follow_steps_make_a_climbable_route() -> void:
	var d := RouteDraft.new()
	var t := EditorTutorial.new()
	runner.check(t.steps.size() == 8, "8단계 (%d)" % t.steps.size())
	runner.check(_step_id(t) == "place" and t.update(d, d.problems(), 0.1) == "", "처음은 놓기, 아무것도 안 하면 그대로")
	# 1 손홀드 놓기
	t.note("place_foot")
	runner.check(t.update(d, d.problems(), 0.1) == "", "발홀드를 놓아도 첫 단계는 그대로")
	var h1 := d.place("jug", -0.3, 1.7)
	t.note("place_hand")
	runner.check(t.update(d, d.problems(), 0.1) == "next" and _step_id(t) == "move", "손홀드를 놓으면 옮기기로")
	# 2 옮기기: 앞 단계 사건은 세지 않는다
	runner.check(t.update(d, d.problems(), 0.1) == "", "옮기기 전엔 그대로")
	t.note("move")
	runner.check(t.update(d, d.problems(), 0.1) == "next" and _step_id(t) == "rotate", "옮기면 돌리기로")
	t.note("rotate")
	runner.check(t.update(d, d.problems(), 0.1) == "next" and _step_id(t) == "spots", "돌리면 시작 자리로")
	# 4 시작 자리: 안내 문구대로(손 두 개 60cm, 1.3m 아래 발 두 개)
	var h2 := d.place("jug", 0.3, 1.7)
	runner.check(t.update(d, d.problems(), 0.1) == "", "손홀드 둘만으로는 아직")
	var f1 := d.place("foot_big", -0.3, 0.4)
	var f2 := d.place("foot_big", 0.3, 0.4)
	runner.check(t.update(d, d.problems(), 0.1) == "next" and _step_id(t) == "start", "손 둘·발 둘이면 시작홀드 정하기로")
	d.set_start(&"LH", h1)
	d.set_start(&"RH", h2)
	d.set_start(&"LF", f1)
	runner.check(t.update(d, d.problems(), 0.1) == "", "셋만 정하면 아직")
	d.set_start(&"RF", f2)
	runner.check(t.update(d, d.problems(), 0.1) == "next" and _step_id(t) == "top", "넷 다 정하면 탑으로")
	d.place("goal", 0.0, 3.6)
	runner.check(t.update(d, d.problems(), 0.1) == "next" and _step_id(t) == "name", "탑을 놓으면 이름으로")
	d.set_name("첫 문제")
	runner.check(t.update(d, d.problems(), 0.1) == "next" and _step_id(t) == "check", "이름을 쓰면 점검으로")
	runner.check(d.problems().is_empty(), "안내대로 만든 문제는 막는 것이 없다 %s" % [d.problems()])
	runner.check(t.update(d, d.problems(), 0.1) == "done" and t.done, "막는 것이 없으면 끝")


## 이미 해 둔 단계(시작홀드·탑·이름)는 [만드는 법]으로 다시 열어도 바로 넘어간다.
func test_state_steps_skip_when_already_done() -> void:
	var d := RouteDraft.new()
	var t := EditorTutorial.new()
	t.index = t.steps.map(func(s): return s.id).find("top")
	d.place("goal", 0.0, 3.6)
	d.set_name("이름")
	runner.check(t.update(d, d.problems(), 0.1) == "next", "탑 있음 → 넘어감")
	runner.check(t.update(d, d.problems(), 0.1) == "next", "이름 있음 → 넘어감")
	runner.check(_step_id(t) == "check" and t.update(d, d.problems(), 0.1) == "", "막는 것이 남으면 점검에서 기다린다")


## 한 단계에서 15초 넘게 진행이 없으면 도움말이 나오고, 다음 단계에선 다시 숨는다.
func test_help_after_idle() -> void:
	var d := RouteDraft.new()
	var t := EditorTutorial.new()
	t.update(d, [], 14.0)
	runner.check(t.help_text() == "", "14초엔 도움말 없음")
	t.update(d, [], 1.5)
	runner.check(t.help_text() != "", "15초 넘으면 도움말")
	d.place("jug", 0.0, 1.7)
	t.note("place_hand")
	t.update(d, [], 0.1)
	runner.check(t.help_text() == "", "다음 단계는 도움말 숨김")
	for s in t.steps:
		runner.check(str(s.text) != "" and str(s.help) != "", "%s 문구·도움말 있음" % s.id)
