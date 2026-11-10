extends RefCounted
## 캐릭터 외형 고르기(docs/34 §7): 파츠 목록과 모듈 glb가 맞는지, 고른 것만 보이는지, 뼈대 규격, 저장.

var runner
const SPEC := {"pelvis": Vector3(0, 0, 0), "chest": Vector3(0, 0.44, -0.01), "head": Vector3(0, 0.80, -0.01),
	"upperarm_L": Vector3(-0.2, 0.55, 0), "hand_R": Vector3(0.907, 0.22, 0), "shin_L": Vector3(-0.176, -0.519, 0), "foot_R": Vector3(0.21, -0.998, 0)}


func _model(asm: CharacterAssembler) -> Node3D:
	return load(asm.model_path()).instantiate()


func test_catalog_matches_model() -> void:
	var asm := CharacterAssembler.load_catalog()
	runner.check(ResourceLoader.exists(asm.model_path()), "모듈 모델 있음 %s" % asm.model_path())
	var m := _model(asm)
	var names := m.find_children("P_*", "MeshInstance3D", true, false).map(func(n): return String(n.name))
	var listed: Array = asm.bodies().map(func(b): return b.mesh)
	for sid in CharacterAssembler.SLOTS:
		var parts: Array = asm.slot(sid).get("parts", [])
		runner.check(not parts.is_empty(), "%s 파츠 있음" % sid)
		for p in parts:
			listed.append(p.mesh)
	for mesh in listed:
		runner.check(names.has(mesh), "목록의 %s가 모델에 있음" % mesh)
	for n in names:
		runner.check(listed.has(n), "모델의 %s가 목록에 있음" % n)
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	for entry in RigPose.BONES:
		runner.check(sk.find_bone(entry[0]) >= 0, "뼈 %s" % entry[0])
	for b in SPEC:
		var d := sk.get_bone_global_rest(sk.find_bone(b)).origin.distance_to(SPEC[b])
		runner.check(d <= 0.001, "뼈 %s 위치 규격 ±1mm (%.4f)" % [b, d])
	m.free()


func test_apply_shows_one_per_slot() -> void:
	var asm := CharacterAssembler.load_catalog()
	var m := _model(asm)
	for look in [{}, {"body": "female"}, {"body": "male", "hair": "crop"}, {"body": "nope", "hair": "zzz"}]:
		var shown := asm.apply(m, look)
		runner.check(shown == 1 + CharacterAssembler.SLOTS.size(), "%s: 몸 하나 + 슬롯마다 하나 (%d)" % [look, shown])
	asm.apply(m, {"body": "female"})
	var vis := m.find_children("P_*", "MeshInstance3D", true, false).filter(func(n): return n.visible).map(func(n): return String(n.name))
	runner.check(vis.has("P_body_female") and not vis.has("P_body_male") and vis.has("P_hair_crop"), "여성 기본: 여성 몸 + 짧은 머리 %s" % [vis])
	m.free()


func test_normalize_and_cycle() -> void:
	var asm := CharacterAssembler.load_catalog()
	var n := asm.normalize({})
	runner.check(n.body == "male" and n.hair == "tousled" and n.shoes == "velcro", "빈 선택 → 남성 기본 %s" % [n])
	runner.check(asm.cycle(n, "body", 1) == "female" and asm.cycle(n, "hair", 1) == "crop" and asm.cycle(n, "top", 1) == "tee", "다음 파츠(한 가지뿐이면 그대로)")
	runner.check(CharacterAssembler.is_face_material("M_eye") and CharacterAssembler.is_face_material("M_face_mouth") and not CharacterAssembler.is_face_material("M_skin"), "얼굴 재질은 외곽선 없음")


func test_look_saved() -> void:
	var p := Progress.new()
	var flow := PlayFlow.new(ContentIndex.new(), p, "user://test_look_save.json")
	flow.set_look({"body": "female", "hair": "crop"})
	runner.check(SaveStore.load("user://test_look_save.json").look == {"body": "female", "hair": "crop"}, "외형 저장·불러오기")
	for f in ["user://test_look_save.json", "user://test_look_save.json.tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
