extends RefCounted
## 만들기 튜토리얼(EditorTutorial). 2026-11-26 사용자 "만들기도 튜토리얼을 만들어줘",
## "한 스텝씩 어디를 클릭하며 진행해야 문제가 만들어지는지 … 중간에 원하는 홀드들을 추가하도록 한 뒤 … 최종적으로 본인 문제를":
## 한 단계에 누를 곳 하나(버튼·벽의 노란 원·홀드). 시작 자리 뒤 자유롭게 놓기, [다음]으로 이어서 탑·이름·점검·저장.

var runner


func _id(t: EditorTutorial) -> String:
	return str(t.current().id) if not t.done else "done"


## 단계 하나 진행: 사건을 알리고(있으면) update가 "next"/"done"이면 true.
func _go(t: EditorTutorial, d: RouteDraft, ev := "") -> bool:
	if ev != "":
		t.note(ev)
	return t.update(d, d.problems(), 0.1) in ["next", "done"]


func test_follow_every_click_makes_own_route() -> void:
	var d := RouteDraft.new()
	var t := EditorTutorial.new()
	t.begin(d)
	runner.check(_id(t) == "list_hand" and t.target() == ["list", "hand"], "처음: [손홀드] 가리킴")
	runner.check(not _go(t, d, "type:jug"), "다른 버튼은 넘어가지 않음")
	runner.check(_go(t, d, "list:hand") and _id(t) == "type_jug" and t.target() == ["type", "jug"], "[손홀드] → [저그]")
	runner.check(_go(t, d, "type:jug") and _id(t) == "spot0", "[저그] → 노란 원 1")
	runner.check(t.mark(d) == EditorTutorial.SPOTS[0] and t.mark_strict() and t.place_kind() == "hand", "원 1: 손홀드 자리, 그 안만")
	for i in 2:
		var m: Vector2 = t.mark(d)
		d.place("jug", m.x, m.y)
		runner.check(_go(t, d), "원 %d에 놓으면 다음" % (i + 1))
	runner.check(_id(t) == "list_foot", "손 둘 → [발홀드]")
	runner.check(_go(t, d, "list:foot") and _go(t, d, "type:foot_big") and t.place_kind() == "foot", "[발홀드] → [큰 발판] → 발 자리")
	for i in 2:
		var m: Vector2 = t.mark(d)
		d.place("foot_big", m.x, m.y)
		runner.check(_go(t, d), "원 %d에 놓으면 다음" % (i + 3))
	runner.check(_id(t) == "tool_start" and _go(t, d, "tool:start"), "[시작홀드 설정]")
	for i in 4:
		var want := t.start_want(d)
		var limb: StringName = [&"LH", &"RH", &"LF", &"RF"][i]
		runner.check(want.limb == limb and want.hold == t.spot_hold(d, i) and want.hold != "" and t.target() == ["hold", i], "%s: 원 %d의 홀드를 가리킴" % [limb, i + 1])
		runner.check(not _go(t, d), "누르기 전엔 그대로")
		d.set_start(limb, want.hold)
		runner.check(_go(t, d), "%s 정하면 다음" % limb)
	runner.check(_id(t) == "tool_edit" and _go(t, d, "tool:edit") and _id(t) == "free", "[편집] → 자유롭게 놓기")
	# 자유: 원하는 홀드를 놓는 동안은 머무르고, 카드의 [다음]으로 이어 간다
	d.place("crimp", -0.1, 2.5)
	d.place("jug", 0.2, 3.1)
	runner.check(not _go(t, d) and t.target() == ["tut_next", ""], "놓는 동안은 그대로, [다음] 가리킴")
	runner.check(_go(t, d, "tut_next:") and _go(t, d, "list:goal") and _id(t) == "top", "[다음] → [탑] → 탑 자리")
	var top: Vector2 = t.mark(d)
	runner.check(top.is_equal_approx(Vector2(0.2, 3.7)) and not t.mark_strict(), "탑 원: 가장 높은 홀드 0.6m 위, 다른 곳도 됨 (%s)" % top)
	d.place("goal", top.x, top.y)
	runner.check(_go(t, d) and _id(t) == "name", "탑 → 이름")
	d.set_name("내 문제")
	t.typing = true
	runner.check(not _go(t, d), "쓰는 중(키보드 열림)엔 그대로")
	t.typing = false
	runner.check(d.problems().is_empty(), "누르라는 곳만 눌러 만든 문제는 막는 것이 없다 %s" % [d.problems()])
	runner.check(_go(t, d) and _id(t) == "save" and t.target() == ["save", ""], "막는 것 없으면 점검을 지나 [저장]")
	runner.check(not _go(t, d, "climb:") and _go(t, d, "save:") and t.done, "[저장]으로 끝")


## 이미 시작 자리를 다 정한 문제에서 [만드는 법]을 열면 자유롭게 놓기 앞([편집])부터.
func test_begin_after_start_is_set() -> void:
	var d := RouteDraft.new()
	var ids := []
	for i in 4:
		var m: Vector2 = EditorTutorial.SPOTS[i]
		ids.append(d.place("jug" if i < 2 else "foot_big", m.x, m.y))
	for i in 4:
		d.set_start([&"LH", &"RH", &"LF", &"RF"][i], ids[i])
	var t := EditorTutorial.new()
	t.begin(d)
	runner.check(_id(t) == "tool_edit", "시작 자리가 있으면 [편집]부터 (%s)" % _id(t))


## 원 자리에 이미 홀드가 있으면 그 단계는 바로 넘어간다(같은 자리를 두 번 놓게 하지 않음).
func test_spot_already_filled_skips() -> void:
	var d := RouteDraft.new()
	var t := EditorTutorial.new()
	t.begin(d)
	d.place("jug", EditorTutorial.SPOTS[0].x, EditorTutorial.SPOTS[0].y)
	_go(t, d, "list:hand")
	runner.check(_go(t, d, "type:jug") and _id(t) == "spot1", "원 1이 차 있으면 원 2로 (%s)" % _id(t))


func test_top_mark_without_holds() -> void:
	runner.check(EditorTutorial.top_mark(RouteDraft.new()).is_equal_approx(Vector2(0, 2.5)), "홀드가 없으면 가운데 2.5m")


## 한 단계에서 15초 넘게 진행이 없으면 도움말이 나오고, 다음 단계에선 다시 숨는다.
func test_help_after_idle() -> void:
	var d := RouteDraft.new()
	var t := EditorTutorial.new()
	t.begin(d)
	t.update(d, [], 14.0)
	runner.check(t.help_text() == "", "14초엔 도움말 없음")
	t.update(d, [], 1.5)
	runner.check(t.help_text() != "", "15초 넘으면 도움말")
	_go(t, d, "list:hand")
	runner.check(t.help_text() == "", "다음 단계는 도움말 숨김")
	for s in t.steps:
		runner.check(str(s.text) != "" and str(s.help) != "", "%s 문구·도움말 있음" % s.id)
