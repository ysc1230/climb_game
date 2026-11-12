extends RefCounted
## 캐릭터(docs/34 §7, docs/36): 목록과 glb가 맞는지, 뼈대 규격(B안 관절 위치), 예산, 고른 것만 보이는지, 저장.
## 2026-11-11: 게임 모델은 Tripo 통짜(파츠 없음). 2026-11-13: 남성(climber_tripo.glb)·여성(climber_tripo_female.glb) 2종,
## 몸마다 model. 파츠 교체 논리는 가짜 목록으로 시험한다.

var runner

const TRI_BUDGET := 12500
## 뼈 → B안 관절(벽면 x, y). 깊이(z)는 모델 팔·다리 중심선을 따르므로 보지 않는다.
const SPEC := {"pelvis": Vector2(0, 0), "spine": Vector2(0, 0.27), "chest": Vector2(0, 0.54), "neck": Vector2(0, 0.76), "head": Vector2(0, 0.84),
	"upperarm_R": Vector2(0.18, 0.67), "forearm_R": Vector2(0.38, 0.67), "hand_R": Vector2(0.73, 0.67), "finger_R": Vector2(0.765, 0.67),
	"upperarm_L": Vector2(-0.18, 0.67), "hand_L": Vector2(-0.73, 0.67)}
const MODELS := {"male": ["res://art/characters/climber_tripo.glb", "P_body_male"],
	"female": ["res://art/characters/climber_tripo_female.glb", "P_body_female"]}

## 파츠 교체 논리용 가짜 목록(옛 모듈 시제품과 같은 모양).
const FAKE := {"model": "", "bodies": [
		{"id": "male", "name_ko": "남성", "mesh": "P_body_male", "defaults": {"hair": "tousled", "top": "tee", "bottom": "pants", "chalk": "bag", "shoes": "velcro"}},
		{"id": "female", "name_ko": "여성", "mesh": "P_body_female", "defaults": {"hair": "crop", "top": "tee", "bottom": "pants", "chalk": "bag", "shoes": "velcro"}}],
	"slots": [{"id": "hair", "parts": [{"id": "tousled", "mesh": "P_hair_tousled"}, {"id": "crop", "mesh": "P_hair_crop"}]},
		{"id": "top", "parts": [{"id": "tee", "mesh": "P_top_tee"}]}, {"id": "bottom", "parts": [{"id": "pants", "mesh": "P_bottom_pants"}]},
		{"id": "chalk", "parts": [{"id": "bag", "mesh": "P_chalk_bag"}]}, {"id": "shoes", "parts": [{"id": "velcro", "mesh": "P_shoes_velcro"}]}]}


func _model(asm: CharacterAssembler, body := "male") -> Node3D:
	return load(asm.model_path(body)).instantiate()


func _fake() -> CharacterAssembler:
	var a := CharacterAssembler.new()
	a.data = FAKE.duplicate(true)
	return a


func test_catalog_matches_model() -> void:
	var asm := CharacterAssembler.load_catalog()
	runner.check(asm.bodies().map(func(b): return b.id) == ["male", "female"] and asm.data.get("slots", []).is_empty(), "남성·여성 2종, 파츠 없음(통짜)")
	runner.check(asm.model_path() == MODELS.male[0], "기본 모델은 남성")
	for body in MODELS:
		var path: String = MODELS[body][0]
		runner.check(asm.model_path(body) == path and ResourceLoader.exists(path), "%s 모델 %s" % [body, asm.model_path(body)])
		var m := _model(asm, body)
		var names := m.find_children("P_*", "MeshInstance3D", true, false).map(func(n): return String(n.name))
		runner.check(names == [MODELS[body][1]], "%s 모델 메시는 몸 하나 %s" % [body, names])
		var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
		for entry in RigPose.BONES:
			runner.check(sk.find_bone(entry[0]) >= 0, "%s 뼈 %s" % [body, entry[0]])
		for f in ["finger_L", "finger_R"]:
			var i := sk.find_bone(f)
			runner.check(i >= 0 and sk.get_bone_name(sk.get_bone_parent(i)) == "hand_" + f.right(1), "%s 손가락 뼈 %s(부모 손)" % [body, f])
		for h in RigPose.HELPERS:
			var i := sk.find_bone(h)
			runner.check(i >= 0 and sk.get_bone_name(sk.get_bone_parent(i)) == "pelvis", "%s 엉덩이 보조 뼈 %s(부모 골반)" % [body, h])
			var th := sk.find_bone(RigPose.HELPERS[h][1])
			runner.check(i >= 0 and sk.get_bone_global_rest(i).origin.distance_to(sk.get_bone_global_rest(th).origin) < 0.001, "%s %s는 엉덩이 관절에" % [body, h])
		for b in SPEC:
			var o := sk.get_bone_global_rest(sk.find_bone(b)).origin
			var d := Vector2(o.x, o.y).distance_to(SPEC[b])
			runner.check(d <= 0.001, "%s 뼈 %s 위치 규격 ±1mm (%.4f)" % [body, b, d])
		# 다리(docs/37 §7): 화면 다리 관절은 판정 고관절 위, 허벅지+정강이 = 판정 다리 + 올린 높이, 발목은 판정 높이
		var leg := CharacterAssembler.leg_shape(sk)
		runner.check(leg.raise >= 0.05 and leg.raise <= 0.15, "%s 화면 다리 관절 높이 %.3f" % [body, leg.raise])
		runner.check(absf(leg.upper + leg.lower - (Tuning.LEG_UPPER + Tuning.LEG_LOWER + leg.raise)) <= 0.01, "%s 다리 길이 %.3f+%.3f" % [body, leg.upper, leg.lower])
		runner.check(absf(leg.ankle_y + Tuning.LEG_UPPER + Tuning.LEG_LOWER) <= 0.02, "%s 발목 높이 %.3f" % [body, leg.ankle_y])
		runner.check(CharacterAssembler.compatible(sk) and asm.model_compatible(body), "%s 지금 몸(뼈 길이·어깨)과 호환" % body)
		var mesh: Mesh = (m.find_children(MODELS[body][1], "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		var arr := mesh.surface_get_arrays(0)
		var tris: int = arr[Mesh.ARRAY_INDEX].size() / 3
		runner.check(tris <= TRI_BUDGET, "%s 삼각형 예산 %d ≤ %d" % [body, tris, TRI_BUDGET])
		runner.check(arr[Mesh.ARRAY_BONES].size() == arr[Mesh.ARRAY_VERTEX].size() * 4, "%s 정점당 뼈 4개 이하" % body)
		# 엉덩이골 윤곽선 굵기(정점 색 R): 가랑이 가운데는 0, 팔·머리는 1
		var colors: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		runner.check(colors.size() == arr[Mesh.ARRAY_VERTEX].size(), "%s 윤곽선 굵기(정점 색)" % body)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var zero := 0
		var far_ok := true
		for vi in verts.size():
			var v := verts[vi]
			if absf(v.x) < 0.02 and v.y > -0.05 and v.y < 0.15 and colors[vi].r < 0.01:
				zero += 1
			if absf(v.x) > 0.3 and colors[vi].r < 0.99:
				far_ok = false
		runner.check(zero > 10 and far_ok, "%s 가랑이 가운데만 윤곽선 0 (%d개)" % [body, zero])
		var mat := mesh.surface_get_material(0) as BaseMaterial3D
		runner.check(mat != null and mat.resource_name == "M_body_main" and mat.albedo_texture != null, "%s 재질 M_body_main + 색 텍스처" % body)
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
	var o := t.next_pass as ShaderMaterial
	runner.check(o != null and o.get_shader_parameter("use_vertex_width") == true, "윤곽선 굵기는 정점 색으로(엉덩이골 검은 선 방지)")
	m.free()


## 화면 다리 모양은 모델마다(docs/37 §7): 여성 다리로 바꾸면 화면 무릎이 그 길이를 따르고, 되돌리면 남성 기본.
func test_leg_shape_per_model() -> void:
	var asm := CharacterAssembler.load_catalog()
	var m := _model(asm, "female")
	var leg := CharacterAssembler.leg_shape(m.find_children("*", "Skeleton3D", true, false)[0])
	m.free()
	var s := ClimbSession.new(RouteDef.load_json("res://tests/fixtures/G_V0_01.json"))
	LimbIK.set_leg_shape(leg.raise, leg.upper, leg.lower)
	var t := ClimberPose.new().compute(s, Tuning.DT)
	var up := absf(t.hip_R.distance_to(t.knee_R) - leg.upper)
	var lo := absf(t.knee_R.distance_to(t.ankle_R) - leg.lower)
	runner.check(up < 0.002 and lo < 0.002, "여성 다리 허벅지 %.3f 정강이 %.3f" % [t.hip_R.distance_to(t.knee_R), t.knee_R.distance_to(t.ankle_R)])
	var pelvis_hip: float = (t.hip_R - t.pelvis).dot(t.up)
	runner.check(absf(pelvis_hip - leg.raise) < 0.002, "화면 다리 관절은 골반 위 %.3f" % pelvis_hip)
	LimbIK.reset_leg_shape()
	t = ClimberPose.new().compute(s, Tuning.DT)
	runner.check(absf(t.hip_R.distance_to(t.knee_R) - LimbIK.LEG_UPPER_SHOWN) < 0.002, "되돌리면 기본 다리")


func test_apply_tripo_shows_body() -> void:
	var asm := CharacterAssembler.load_catalog()
	for body in MODELS:
		var m := _model(asm, body)
		for look in [{"body": body}, {"body": body, "hair": "crop"}]:
			runner.check(asm.apply(m, look) == 1, "%s %s: 몸 하나만" % [body, look])
		m.free()
	runner.check(asm.normalize({"hair": "crop"}) == {"body": "male", "hair": "", "top": "", "bottom": "", "chalk": "", "shoes": ""}, "파츠 없는 슬롯은 빈 값")
	runner.check(asm.cycle({"body": "male"}, "body", 1) == "female" and asm.cycle({"body": "female"}, "body", 1) == "male" and asm.cycle({"body": "male"}, "hair", 1) == "", "성별 바꾸기, 파츠 없는 슬롯은 그대로")
	runner.check(asm.model_path("female") == MODELS.female[0] and asm.model_path("nope") == MODELS.male[0], "몸마다 모델, 모르는 몸은 기본")


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
