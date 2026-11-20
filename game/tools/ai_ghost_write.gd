extends SceneTree
## AI 고스트 기록 만들기(2026-11-20 사용자): 정답 순서가 있는 일반 문제를 검사 봇으로 돌려 data/ai_ghosts/<route_id>.json에 쓴다.
## 휴대폰에서 봇을 돌리면 몇 초 멈추므로 미리 만든다. 문제(content_version)나 조정값(TUNING_VERSION)이 바뀌면 다시 돌린다.
## 사용: godot --headless --path game --script res://tools/ai_ghost_write.gd [-- route_id ...]


func _init() -> void:
	var ids := Array(OS.get_cmdline_user_args())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(HelpPicker.AI_DIR))
	var ok := true
	for r in ContentIndex.load_all().all_routes():
		if r.mode != "general" or r.intended_moves.is_empty() or (not ids.is_empty() and not ids.has(r.route_id)):
			continue
		var g := HelpPicker.demo_track(r)
		if g == null:
			print("FAIL ", r.route_id, " 봇이 못 깸")
			ok = false
			continue
		var f := FileAccess.open(HelpPicker.stored_path(r.route_id), FileAccess.WRITE)
		f.store_string(JSON.stringify(HelpPicker.stored_dict(r, g)))
		f.close()
		print("ok ", r.route_id, " %.1fs" % g.duration())
	quit(0 if ok else 1)
