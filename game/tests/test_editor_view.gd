extends RefCounted
## 문제 만들기 화면의 3D 벽(editor_view.gd). 2026-11-25 사용자 "만들기 할 때 벽은 아무것도 안 보여":
## 꺾이는 벽(v0.18, fold)·벽 꾸밈(v0.21, 문제의 wall_style) 뒤로 만들기 화면이 카메라·벽·홀드를 못 만들고 회색만 보였다.

var runner


func test_editor_builds_wall_and_holds() -> void:
	var v: Node3D = load("res://scenes/editor_view.gd").new()
	v._ready()
	runner.check(v.camera != null, "카메라를 만든다")
	var d := RouteDraft.new()
	d.place("jug", 0.3, 1.6)
	v.rebuild(d)
	runner.check(v.fold != null, "접힌 벽 틀")
	runner.check(v.wall_root.get_parent() == v, "벽 묶음이 화면에 붙음")
	var n: int = v.wall_root.get_child_count()
	runner.check(n > 1, "벽·홀드를 그림 (%d)" % n)
	v.rebuild(d)
	runner.check(v.wall_root.get_child_count() == n, "다시 만들면 예전 것은 지움 (%d → %d)" % [n, v.wall_root.get_child_count()])
	v.free()
