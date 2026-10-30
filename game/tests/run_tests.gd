extends SceneTree
## 의존성 없는 헤드리스 테스트 실행기.
## 사용: godot --headless --path game --script res://tests/run_tests.gd
## res://tests/test_*.gd 의 test_ 로 시작하는 메서드를 실행한다.

var failures := 0
var current := ""


func _init() -> void:
	var total := 0
	var dir := DirAccess.open("res://tests")
	var only := OS.get_cmdline_user_args()  # 예: -- test_support.gd
	var files := Array(dir.get_files()).filter(func(f): return f.begins_with("test_") and f.ends_with(".gd") and (only.is_empty() or only.has(f)))
	files.sort()
	for file in files:
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			failures += 1
			total += 1
			print("  FAIL " + file + " (불러오기 실패)")
			continue
		var suite = script.new()
		suite.set("runner", self)
		for m in suite.get_method_list():
			if not String(m.name).begins_with("test_"):
				continue
			total += 1
			current = "%s::%s" % [file, m.name]
			print("  ..   " + current)
			var before := failures
			suite.call(m.name)
			print(("  ok   " if failures == before else "  FAIL ") + current)
	print("%d개 중 %d개 실패" % [total, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("    ", current, ": ", msg)
