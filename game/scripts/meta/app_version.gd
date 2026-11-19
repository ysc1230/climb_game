class_name AppVersion
extends RefCounted
## 화면에 보이는 게임 버전(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.7).
## 값은 project.godot의 application/config/version 한 곳. 버전을 올릴 때 export_presets.cfg의 version/name도 같이 올린다.


static func text() -> String:
	return "v" + str(ProjectSettings.get_setting("application/config/version", ""))
