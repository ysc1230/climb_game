extends RefCounted
## CH02 캐릭터(2026-11-07 사용자 캐릭터 시트): 뼈 17개(RigPose.BONES)와 표정 메시 4종, 표정 고르기 규칙.

var runner

const PLAY_3D := preload("res://scenes/play_3d.gd")


func test_model_has_rig_and_faces() -> void:
	var model: Node3D = load("res://art/characters/climber.glb").instantiate()
	var sk: Array = model.find_children("*", "Skeleton3D", true, false)
	runner.check(sk.size() == 1, "스켈레톤 하나")
	if sk.size() == 1:
		for entry in RigPose.BONES:
			runner.check((sk[0] as Skeleton3D).find_bone(entry[0]) >= 0, "뼈 %s" % entry[0])
	var names := model.find_children("FX_face_*", "MeshInstance3D", true, false).map(func(n): return String(n.name))
	for e in ["calm", "effort", "happy", "scared"]:
		runner.check(names.has("FX_face_" + e), "표정 메시 %s: %s" % [e, names])
	model.free()


func test_expression_rules() -> void:
	runner.check(PLAY_3D.expression_for(false, false, 100.0, false) == "calm", "평소 평온")
	runner.check(PLAY_3D.expression_for(false, false, 40.0, false) == "effort", "팔 힘 45 아래 힘씀")
	runner.check(PLAY_3D.expression_for(false, false, 90.0, true) == "effort", "자세 무너짐 힘씀")
	runner.check(PLAY_3D.expression_for(false, true, 20.0, true) == "happy", "정상 잡으면 기쁨")
	runner.check(PLAY_3D.expression_for(true, true, 20.0, false) == "scared", "떨어지면 놀람")
