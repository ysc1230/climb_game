extends RefCounted
## 캐릭터(docs/34 §7, docs/36): 목록과 glb가 맞는지, 뼈대 규격(B안 관절 위치), 예산, 고른 것만 보이는지, 저장.
## 2026-11-11: 게임 모델은 Tripo 통짜 남성 1종(climber_tripo.glb, 파츠 없음). 파츠 교체 논리는 가짜 목록으로 시험한다.

var runner

const TRI_BUDGET := 12500
## 뼈 → B안 관절(벽면 x, y). 깊이(z)는 모델 팔·다리 중심선을 따르므로 보지 않는다.
const SPEC := {"pelvis": Vector2(0, 0), "spine": Vector2(0, 0.27), "chest": Vector2(0, 0.54), "neck": Vector2(0, 0.76), "head": Vector2(0, 0.84),
	"upperarm_R": Vector2(0.18, 0.67), "forearm_R": Vector2(0.38, 0.67), "hand_R": Vector2(0.73, 0.67), "finger_R": Vector2(0.765, 0.67),
	"upperarm_L": Vector2(-0.18, 0.67), "hand_L": Vector2(-0.73, 0.67), "thigh_R": Vector2(0.10, 0)}

## 파츠 교체 논리용 가짜 목록(옛 모듈 시제품과 같은 모양).
const FAKE := {"model": "", "bodies": [
		{"id": "male", "name_ko": "남성", "mesh": "P_body_male", "defaults": {"hair": "tousled", "top": "tee", "bottom": "pants", "chalk": "bag", "shoes": "velcro"}},
		{"id": "female", "name_ko": "여성", "mesh": "P_body_female", "defaults": {"hair": "crop", "top": "tee", "bottom": "pants", "chalk": "bag", "shoes": "velcro"}}],
	"slots": [{"id": "hair", "parts": [{"id": "tousled", "mesh": "P_hair_tousled"}, {"id": "crop", "mesh": "P_hair_crop"}]},
		{"id": "top", "parts": [{"id": "tee", "mesh": "P_top_tee"}]}, {"id": "bottom", "parts": [{"id": "pants", "mesh": "P_bottom_pants"}]},
		{"id": "chalk", "parts": [{"id": "bag", "mesh": "P_chalk_bag"}]}, {"id": "shoes", "parts": [{"id": "velcro", "mesh": "P_shoes_velcro"}]}]}


func _model(asm: CharacterAssembler) -> Node3D:
	return load(asm.model_path()).instantiate()


func _fake() -> CharacterAssembler:
	var a := CharacterAssembler.new()
	a.data = FAKE.duplicate(true)
	return a


func test_catalog_matches_model() -> void:
	var asm := CharacterAssembler.load_catalog()
	runner.check(asm.model_path() == "res://art/characters/climber_tripo.glb" and ResourceLoader.exists(asm.model_path()), "Tripo 모델 %s" % asm.model_path())
	runner.check(asm.bodies().size() == 1 and asm.data.get("slots", []).is_empty(), "남성 1종, 파츠 없음(통짜)")
	var m := _model(asm)
	var names := m.find_children("P_*", "MeshInstance3D", true, false).map(func(n): return String(n.name))
	runner.check(names == ["P_body_male"], "모델 메시는 몸 하나 %s" % [names])
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	for entry in RigPose.BONES:
		runner.check(sk.find_bone(entry[0]) >= 0, "뼈 %s" % entry[0])
	for f in ["finger_L", "finger_R"]:
		var i := sk.find_bone(f)
		runner.check(i >= 0 and sk.get_bone_name(sk.get_bone_parent(i)) == "hand_" + f.right(1), "손가락 뼈 %s(부모 손)" % f)
	for h in RigPose.HELPERS:
		var i := sk.find_bone(h)
		runner.check(i >= 0 and sk.get_bone_name(sk.get_bone_parent(i)) == "pelvis", "엉덩이 보조 뼈 %s(부모 골반)" % h)
		var th := sk.find_bone(RigPose.HELPERS[h][1])
		runner.check(i >= 0 and sk.get_bone_global_rest(i).origin.distance_to(sk.get_bone_global_rest(th).origin) < 0.001, "%s는 엉덩이 관절에" % h)
	for b in SPEC:
		var o := sk.get_bone_global_rest(sk.find_bone(b)).origin
		var d := Vector2(o.x, o.y).distance_to(SPEC[b])
		runner.check(d <= 0.001, "뼈 %s 위치 규격 ±1mm (%.4f)" % [b, d])
	runner.check(CharacterAssembler.compatible(sk) and asm.model_compatible(), "지금 몸(뼈 길이·어깨)과 호환")
	var mesh: Mesh = (m.find_children("P_body_male", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var arr := mesh.surface_get_arrays(0)
	var tris: int = arr[Mesh.ARRAY_INDEX].size() / 3
	runner.check(tris <= TRI_BUDGET, "삼각형 예산 %d ≤ %d" % [tris, TRI_BUDGET])
	runner.check(arr[Mesh.ARRAY_BONES].size() == arr[Mesh.ARRAY_VERTEX].size() * 4, "정점당 뼈 4개 이하")
	var mat := mesh.surface_get_material(0) as BaseMaterial3D
	runner.check(mat != null and mat.resource_name == "M_body_main" and mat.albedo_texture != null, "재질 M_body_main + 색 텍스처")
	m.free()


## 텍스처 재질은 툰 셰이더의 텍스처 입력으로 넘어간다.
func test_style_passes_texture() -> void:
	var asm := CharacterAssembler.load_catalog()
	var m := _model(asm)
	CharacterAssembler.style(m, load("res://art/shaders/toon.gdshader"), load("res://art/shaders/outline.gdshader"), Color.BLACK)
	var mi: MeshInstance3D = m.find_children("P_body_male", "MeshInstance3D", true, false)[0]
	var t := mi.get_surface_override_material(0) as ShaderMaterial
	if t == null:
		t = mi.mesh.surface_get_material(0) as ShaderMaterial
	runner.check(t != null and t.get_shader_parameter("use_texture") == true and t.get_shader_parameter("albedo_tex") != null, "툰 셰이더에 텍스처")
	m.free()


func test_apply_tripo_shows_body() -> void:
	var asm := CharacterAssembler.load_catalog()
	var m := _model(asm)
	for look in [{}, {"body": "female"}, {"body": "male", "hair": "crop"}]:
		runner.check(asm.apply(m, look) == 1, "%s: 몸 하나만" % [look])
	runner.check(asm.normalize({"hair": "crop"}) == {"body": "male", "hair": "", "top": "", "bottom": "", "chalk": "", "shoes": ""}, "파츠 없는 슬롯은 빈 값")
	runner.check(asm.cycle({"body": "male"}, "body", 1) == "male" and asm.cycle({"body": "male"}, "hair", 1) == "", "1종이면 그대로")
	m.free()


func test_normalize_and_cycle_parts() -> void:
	var asm := _fake()
	var n := asm.normalize({})
	runner.check(n.body == "male" and n.hair == "tousled" and n.shoes == "velcro", "빈 선택 → 남성 기본 %s" % [n])
	runner.check(asm.cycle(n, "body", 1) == "female" and asm.cycle(n, "hair", 1) == "crop" and asm.cycle(n, "top", 1) == "tee", "다음 파츠(한 가지뿐이면 그대로)")
	runner.check(asm.normalize({"body": "female"}).hair == "crop" and asm.normalize({"body": "nope", "hair": "zzz"}).hair == "tousled", "몸 기본값·모르는 값")
	var vis := asm.visible_meshes({"body": "female"})
	runner.check(vis.size() == 1 + CharacterAssembler.SLOTS.size() and vis.has("P_body_female") and vis.has("P_hair_crop"), "몸 하나 + 슬롯마다 하나 %s" % [vis])
	runner.check(CharacterAssembler.is_face_material("M_eye") and CharacterAssembler.is_face_material("M_face_mouth") and not CharacterAssembler.is_face_material("M_skin"), "얼굴 재질은 외곽선 없음")


func test_look_saved() -> void:
	var p := Progress.new()
	var flow := PlayFlow.new(ContentIndex.new(), p, "user://test_look_save.json")
	flow.set_look({"body": "female", "hair": "crop"})
	runner.check(SaveStore.load("user://test_look_save.json").look == {"body": "female", "hair": "crop"}, "외형 저장·불러오기")
	for f in ["user://test_look_save.json", "user://test_look_save.json.tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
