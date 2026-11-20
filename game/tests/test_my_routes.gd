extends RefCounted
## 내 문제 저장(작업 6 §3): user://my_routes/<route_id>.json, 인터넷 없이 저장·플레이.

var runner
const DIR := "user://test_my_routes/"


func _draft() -> RouteDraft:
	var d := RouteDraft.new()
	d.route_id = MyRoutes.new_id()
	d.name = "내 문제"
	var f1 := d.place("foot_chip", -0.15, 0.1)
	var f2 := d.place("foot_chip", 0.18, 0.1)
	var h1 := d.place("jug", -0.3, 1.5)
	var h2 := d.place("jug", 0.3, 1.5)
	d.place("goal", 0.05, 2.1)
	d.set_start(&"LH", h1)
	d.set_start(&"RH", h2)
	d.set_start(&"LF", f1)
	d.set_start(&"RF", f2)
	return d


func _cleanup() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR + f)
		DirAccess.remove_absolute(DIR)


func test_new_id_format() -> void:
	var a := MyRoutes.new_id()
	runner.check(a.begins_with("U_") and a.length() == 12 and a != MyRoutes.new_id(), "U_ + 10글자, 매번 다름 %s" % a)


func test_save_list_load() -> void:
	_cleanup()
	var d := _draft()
	runner.check(MyRoutes.save(d, DIR), "저장")
	var lst := MyRoutes.list(DIR)
	runner.check(lst.size() == 1 and lst[0].route_id == d.route_id and lst[0].name == "내 문제", "목록 %s" % [lst])
	var e := MyRoutes.load_draft(d.route_id, DIR)
	runner.check(e != null and e.holds.size() == d.holds.size(), "초안 다시 읽기")
	var r := MyRoutes.load_route(d.route_id, DIR)
	runner.check(r != null and r.errors.is_empty() and r.mode == "custom", "문제로 읽기 %s" % [r.errors if r else "null"])
	runner.check(MyRoutes.remove(d.route_id, DIR) and MyRoutes.list(DIR).is_empty(), "지우기")
	_cleanup()


## 만든 문제를 플레이 흐름에 넣으면 기존 완등 기록 경로가 그대로 쓰인다(만든 사람 완등 = 올리기 조건).
func test_play_flow_custom() -> void:
	var d := _draft()
	var flow := PlayFlow.new(ContentIndex.new(), Progress.new(), "user://test_my_routes_save.json")
	flow.add_custom(d.build())
	flow.current_route_id = d.route_id
	runner.check(flow.current_route() != null and flow.list_target(d.route_id) == {"tab": "make"}, "현재 문제·돌아갈 곳은 만들기 탭")
	flow.finish_clear(30.0, 0, {"score": 80})
	runner.check(d.can_publish(flow.progress), "도움 없이 완등하면 올리기 조건 충족")
	runner.check(flow.next_route_id(d.route_id) == "", "다음 문제 없음")
	DirAccess.remove_absolute("user://test_my_routes_save.json")
