extends RefCounted
## 모든 스크립트가 문법 오류 없이 불러와진다(2026-11-28: 실행기는 스크립트 오류를 실패로 세지 않아, 만들기 화면 파싱 오류가 있어도
## "532개 통과"였다). scenes·scripts·tools 아래 .gd를 모두 불러 본다.

var runner


func _gd_files(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_gd_files(dir.path_join(d), out)


func test_all_scripts_load() -> void:
	var files: Array = []
	for root in ["res://scenes", "res://scripts", "res://tools"]:
		_gd_files(root, files)
	var bad: Array = []
	for f in files:
		var sc = load(f)
		if sc == null or not (sc is GDScript) or not (sc as GDScript).can_instantiate():
			bad.append(f)
	runner.check(files.size() > 50 and bad.is_empty(), "스크립트 %d개, 못 불러온 것 %s" % [files.size(), bad])
