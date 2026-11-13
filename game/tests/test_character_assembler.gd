extends RefCounted
## 캐릭터(docs/34 §7, docs/36): 목록과 glb가 맞는지, 뼈대 규격(B안 관절 위치), 예산, 고른 것만 보이는지, 저장.
## 2026-11-13: 게임 모델은 더미 1종(climber_dummy.glb, docs/39). 몸마다 model을 둘 수 있다. 파츠 교체 논리는 가짜 목록으로 시험한다.

var runner

const TRI_BUDGET := 12500
## 뼈 → B안 관절(벽면 x, y). 깊이(z)는 모델 팔·다리 중심선을 따르므로 보지 않는다.
## 2026-11-13 더미 몸(docs/39): 어깨 (0.175, 0.49), 팔 0.35/0.38(손 접점 = 손가락 뿌리), 손가락 뼈 +0.035.
const SPEC := {"pelvis": Vector2(0, 0), "spine": Vector2(0, 0.16), "chest": Vector2(0, 0.37), "neck": Vector2(0, 0.49), "head": Vector2(0, 0.56),
	"upperarm_R": Vector2(0.175, 0.49), "forearm_R": Vector2(0.525, 0.49), "hand_R": Vector2(0.905, 0.49), "finger_R": Vector2(0.94, 0.49),
	"upperarm_L": Vector2(-0.175, 0.49), "hand_L": Vector2(-0.905, 0.49), "thigh_R": Vector2(0.095, 0), "shin_R": Vector2(0.095, -0.41), "foot_R": Vector2(0.095, -0.81)}
const MODELS := {"dummy": ["res://art/characters/climber_dummy.glb", "P_body_dummy"]}

## 파츠 교체 논리용 가짜 목록(옛 모듈 시제품과 같은 모양).
const FAKE := {"model": "", "bodies": [
		{"id": "male", "name_ko": "남성", "mesh": "P_body_male", "defaults": {"hair": "tousled", "top": "tee", "bottom": "pants", "chalk": "bag", "shoes": "velcro"}},
		{"id": "female", "name_ko": "여성", "mesh": "P_body_female", "defaults": {"hair": "crop", "top": "tee", "bottom": "pants", "chalk": "bag", "shoes": "velcro"}}],
	"slots": [{"id": "hair", "parts": [{"id": "tousled", "mesh": "P_hair_tousled"}, {"id": "crop", "mesh": "P_hair_crop"}]},
		{"id": "top", "parts": [{"id": "tee", "mesh": "P_top_tee"}]}, {"id": "bottom", "parts": [{"id": "pants", "mesh": "P_bottom_pants"}]},
		{"id": "chalk", "parts": [{"id": "bag", "mesh": "P_chalk_bag"}]}, {"id": "shoes", "parts": [{"id": "velcro", "mesh": "P_shoes_velcro"}]}]}


func _model(asm: CharacterAssembler, body := "dummy") -> Node3D:
	return load(asm.model_path(body)).instantiate()


func _fake() -> CharacterAssembler:
	var a := CharacterAssembler.new()
	a.data = FAKE.duplicate(true)
	return a


func test_catalog_matches_model() -> void:
	var asm := CharacterAssembler.load_catalog()
	runner.check(asm.bodies().map(func(b): return b.id) == ["dummy"] and asm.data.get("slots", []).is_empty(), "더미 1종, 파츠 없음")
	runner.check(asm.model_path() == MODELS.dummy[0], "기본 모델은 더미")
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
		runner.check(absf(leg.raise) < 0.001, "%s 다리는 고관절에서 바로 돈다 %.3f" % [body, leg.raise])
		runner.check(absf(leg.upper + leg.lower - (Tuning.LEG_UPPER + Tuning.LEG_LOWER + leg.raise)) <= 0.01, "%s 다리 길이 %.3f+%.3f" % [body, leg.upper, leg.lower])
		runner.check(absf(leg.ankle_y + Tuning.LEG_UPPER + Tuning.LEG_LOWER) <= 0.02, "%s 발목 높이 %.3f" % [body, leg.ankle_y])
		runner.check(CharacterAssembler.compatible(sk) and asm.model_compatible(body), "%s 지금 몸(뼈 길이·어깨)과 호환" % body)
		var mesh: Mesh = (m.find_children(MODELS[body][1], "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		var arr := mesh.surface_get_arrays(0)
		var tris: int = arr[Mesh.ARRAY_INDEX].size() / 3
		runner.check(tris <= TRI_BUDGET, "%s 삼각형 예산 %d ≤ %d" % [body, tris, TRI_BUDGET])
		runner.check(arr[Mesh.ARRAY_BONES].size() == arr[Mesh.ARRAY_VERTEX].size() * 4, "%s 정점당 뼈 4개 이하" % body)
		var mat := mesh.surface_get_material(0) as BaseMaterial3D
		runner.check(mat != null and mat.resource_name == "M_body_main", "%s 재질 M_body_main" % body)
		m.free()


## 더미는 텍스처 없이 단색(M_body_main 색)으로 툰 셰이더에 넘어가고, 윤곽선 굵기는 정점 색을 쓰지 않는다.
func test_style_dummy_color() -> void:
	var asm := CharacterAssembler.load_catalog()
	var m := _model(asm)
	CharacterAssembler.style(m, load("res://art/shaders/toon.gdshader"), load("res://art/shaders/outline.gdshader"), Color.BLACK)
	var mi: MeshInstance3D = m.find_children("P_body_dummy", "MeshInstance3D", true, false)[0]
	var t := mi.get_surface_override_material(0) as ShaderMaterial
	runner.check(t != null and t.get_shader_parameter("use_texture") != true, "단색(텍스처 없음)")
	var o := t.next_pass as ShaderMaterial
	runner.check(o != null and o.get_shader_parameter("use_vertex_width") != true, "윤곽선 굵기 고정")
	m.free()


## 화면 다리 모양은 모델마다(docs/37 §7): 다른 다리 모양으로 바꾸면 화면 무릎이 그 길이를 따르고, 되돌리면 기본(더미: 올림 0).
func test_leg_shape_per_model() -> void:
	var s := ClimbSession.new(RouteDef.load_json("res://tests/fixtures/G_V0_01.json"))
	var raise := 0.10
	var upper := Tuning.LEG_UPPER + raise + 0.02
	var lower := Tuning.LEG_LOWER - 0.02
	LimbIK.set_leg_shape(raise, upper, lower)
	var t := ClimberPose.new().compute(s, Tuning.DT)
	runner.check(absf(t.hip_R.distance_to(t.knee_R) - upper) < 0.002 and absf(t.knee_R.distance_to(t.ankle_R) - lower) < 0.002, "바꾼 다리 허벅지 %.3f 정강이 %.3f" % [t.hip_R.distance_to(t.knee_R), t.knee_R.distance_to(t.ankle_R)])
	var pelvis_hip: float = (t.hip_R - t.pelvis).dot(t.up)
	runner.check(absf(pelvis_hip - raise) < 0.002, "화면 다리 관절은 골반 위 %.3f" % pelvis_hip)
	LimbIK.reset_leg_shape()
	t = ClimberPose.new().compute(s, Tuning.DT)
	runner.check(absf(t.hip_R.distance_to(t.knee_R) - Tuning.LEG_UPPER) < 0.002 and absf((t.hip_R - t.pelvis).dot(t.up)) < 0.002, "되돌리면 더미 다리(고관절에서 바로)")
	var m := _model(CharacterAssembler.load_catalog())
	var leg := CharacterAssembler.leg_shape(m.find_children("*", "Skeleton3D", true, false)[0])
	m.free()
	runner.check(absf(leg.raise - LimbIK.HIP_RAISE) < 0.001 and absf(leg.upper - LimbIK.LEG_UPPER_SHOWN) < 0.002 and absf(leg.lower - Tuning.LEG_LOWER) < 0.002, "더미 모델 다리 = 기본값 %s" % [leg])


func test_apply_shows_body() -> void:
	var asm := CharacterAssembler.load_catalog()
	var m := _model(asm)
	for look in [{}, {"body": "dummy"}, {"body": "male", "hair": "crop"}]:
		runner.check(asm.apply(m, look) == 1, "%s: 몸 하나만" % [look])
	m.free()
	runner.check(asm.normalize({"hair": "crop"}) == {"body": "dummy", "hair": "", "top": "", "bottom": "", "chalk": "", "shoes": ""}, "모르는 몸은 더미, 파츠 없는 슬롯은 빈 값")
	runner.check(asm.cycle({"body": "dummy"}, "body", 1) == "dummy", "1종이면 그대로")
	runner.check(asm.model_path("nope") == MODELS.dummy[0], "모르는 몸은 기본 모델")


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


## 손이 홀드 안에 묻히지 않게(2026-11-13): 붙은 손발은 홀드 겉면(surface_depth) 위에 놓는다. 겉면 정보가 없으면 판정 깊이.
func test_hand_on_hold_surface() -> void:
	var s := ClimbSession.new(RouteDef.load_json("res://tests/fixtures/G_V0_01.json"))
	var pose := ClimberPose.new()
	var t := pose.compute(s, Tuning.DT)
	runner.check(absf(t.wrist_L.z - Tuning.CONTACT_DEPTH) < 0.001, "겉면 정보 없으면 판정 깊이 %.3f" % t.wrist_L.z)
	pose = ClimberPose.new()
	pose.surface_depth[s.limbs[&"LH"].key] = 0.09
	pose.surface_depth[s.limbs[&"LF"].key] = 0.05
	t = pose.compute(s, Tuning.DT)
	runner.check(absf(t.wrist_L.z - (0.09 + ClimberPose.HAND_ON_SURFACE)) < 0.001, "손은 홀드 겉면 위 %.3f" % t.wrist_L.z)
	runner.check(absf(t.ankle_L.z - (0.05 + ClimberPose.FOOT_ON_SURFACE)) < 0.001, "발도 겉면 위 %.3f" % t.ankle_L.z)
