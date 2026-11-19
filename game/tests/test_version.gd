extends RefCounted
## 홈 버전 표시·개발 정보 기본 숨김(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.7).

var runner


func test_version_text() -> void:
	runner.check(AppVersion.text() == "v" + str(ProjectSettings.get_setting("application/config/version", "")), "v + 설정 버전: %s" % AppVersion.text())
	runner.check(AppVersion.text().begins_with("v0."), "버전 글자 %s" % AppVersion.text())


func test_export_name_matches() -> void:
	var cfg := ConfigFile.new()
	runner.check(cfg.load("res://export_presets.cfg") == OK, "export_presets.cfg 읽기")
	var name := str(cfg.get_value("preset.0.options", "version/name", ""))
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	runner.check(ver != "" and name.begins_with(ver), "내보내기 이름 %s 이 설정 버전 %s 로 시작" % [name, ver])


func test_dev_info_default_off() -> void:
	runner.check(not Progress.new().display_on("dev_info"), "개발 정보 기본 꺼짐")
