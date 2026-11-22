extends RefCounted
## 캐릭터(docs/34 §7, docs/36): 목록과 glb가 맞는지, 뼈대 규격(B안 관절 위치), 예산, 고른 것만 보이는지, 저장.
## 2026-11-13: 게임 모델은 남성(2026-11-22부터 climber_anime_male.glb, 기본)과 시험용 더미(climber_dummy.glb, docs/39). 몸마다 model. 파츠 교체 논리는 가짜 목록으로 시험한다.
## 2026-11-22: 대머리(사용자 그림 4장 → Tripo, docs/55) 추가. 속옷만 입은 맨몸(옷은 나중에 몸 위에 맞춰 만든다).
## 2026-11-23: 남성 = 대머리 몸 + 기본 착장(climber_male_base.glb, docs/56): 바가지 머리·흰 티·청바지·회색 초크백·벨크로 암벽화.

var runner

## 2026-11-22 애니 남성: 예전 12,500에서 얼굴·머리카락이 뭉개져(사용자 "20년 전 캐릭터 같아") 25,000으로.
## 화면에 캐릭터 하나, 아트 의뢰 기준(docs/14 CH01 15k~25k) 안.
const TRI_BUDGET := 25000
## 뼈 → B안 관절(벽면 x, y). 깊이(z)는 모델 팔·다리 중심선을 따르므로 보지 않는다.
## 2026-11-13 더미 몸(docs/39): 어깨 (0.175, 0.49), 팔 0.35/0.38(손 접점 = 손가락 뿌리), 손가락 뼈 +0.035.
const SPEC := {"pelvis": Vector2(0, 0), "spine": Vector2(0, 0.16), "chest": Vector2(0, 0.37), "neck": Vector2(0, 0.49), "head": Vector2(0, 0.56),
	"upperarm_R": Vector2(0.175, 0.49), "forearm_R": Vector2(0.525, 0.49), "hand_R": Vector2(0.905, 0.49),
	"upperarm_L": Vector2(-0.175, 0.49), "hand_L": Vector2(-0.905, 0.49), "thigh_R": Vector2(0.095, 0), "shin_R": Vector2(0.095, -0.41), "foot_R": Vector2(0.095, -0.81)}
const MODELS := {"male": ["res://art/characters/climber_male_base.glb", "P_body_male"], "dummy": ["res://art/characters/climber_dummy.glb", "P_body_dummy"], "female": ["res://art/characters/climber_female.glb", "P_body_female"], "bald": ["res://art/characters/climber_bald.glb", "P_body_bald"]}

## 남성 기본 착장(2026-11-23, docs/56).
const MALE_LOOK := {"body": "male", "hair": "hair_bowl", "top": "top_white_tee", "bottom": "pants_jeans", "chalk": "chalk_gray", "shoes": "shoes_velcro"}
const MALE_MESHES := ["P_body_male", "P_chalk_gray", "P_hair_bowl", "P_pants_jeans", "P_shoes_velcro", "P_top_white_tee"]
## 착장 메시 하나·남성 전체(몸 + 옷) 삼각형 예산.
const OUTFIT_PART_BUDGET := 10000
const MALE_TOTAL_BUDGET := 40000

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
	runner.check(asm.bodies().map(func(b): return b.id) == ["male", "female", "bald", "dummy"], "남성·여성·대머리·더미")
	runner.check(asm.data.get("slots", []).map(func(x): return x.id) == ["hair", "top", "bottom", "chalk", "shoes"], "슬롯: 헤어·상의·하의·초크백·암벽화(2026-11-23 남성 착장)")
	runner.check(asm.model_path() == MODELS.male[0], "기본 모델은 남성")
	for body in MODELS:
		var path: String = MODELS[body][0]
		runner.check(asm.model_path(body) == path and ResourceLoader.exists(path), "%s 모델 %s" % [body, asm.model_path(body)])
		var m := _model(asm, body)
		var names := m.find_children("P_*", "MeshInstance3D", true, false).map(func(n): return String(n.name))
		var want := [MODELS[body][1]]
		for sid in CharacterAssembler.SLOTS:
			for p in asm.parts_for(sid, body):
				for mn in CharacterAssembler.part_meshes(p):
					if not want.has(mn):
						want.append(mn)
		names.sort()
		want.sort()
		runner.check(names == want, "%s 모델 메시는 몸 + 그 몸의 옷 %s" % [body, names])
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
		# 손가락(2026-11-13): 손가락 뿌리 = 손 접점, 손가락 뼈는 손 접점에서 2~4cm(남성은 손가락을 짧게)
		var fl := sk.get_bone_global_rest(sk.find_bone("finger_R")).origin.x - sk.get_bone_global_rest(sk.find_bone("hand_R")).origin.x
		runner.check(fl > 0.02 and fl < 0.04, "%s 손가락 첫 마디 %.3f" % [body, fl])
		m.free()


## 더미는 텍스처 없이 단색(M_body_main 색)으로 툰 셰이더에 넘어가고, 윤곽선 굵기는 정점 색을 쓰지 않는다.
func test_style_dummy_color() -> void:
	var asm := CharacterAssembler.load_catalog()
	var m := _model(asm, "dummy")
	CharacterAssembler.style(m, load("res://art/shaders/toon.gdshader"), load("res://art/shaders/outline.gdshader"), Color.BLACK)
	var mi: MeshInstance3D = m.find_children("P_body_dummy", "MeshInstance3D", true, false)[0]
	var t := mi.get_surface_override_material(0) as ShaderMaterial
	runner.check(t != null and t.get_shader_parameter("use_texture") != true, "단색(텍스처 없음)")
	var o := t.next_pass as ShaderMaterial
	runner.check(o != null and o.get_shader_parameter("use_vertex_width") != true, "윤곽선 굵기 고정")
	m.free()
	# 남성은 텍스처 + 윤곽선 굵기(엉덩이골 선 방지)
	m = _model(asm, "male")
	CharacterAssembler.style(m, load("res://art/shaders/toon.gdshader"), load("res://art/shaders/outline.gdshader"), Color.BLACK)
	t = (m.find_children("P_body_male", "MeshInstance3D", true, false)[0] as MeshInstance3D).get_surface_override_material(0)
	runner.check(t.get_shader_parameter("use_texture") == true and (t.next_pass as ShaderMaterial).get_shader_parameter("use_vertex_width") == true, "남성: 텍스처·윤곽선 굵기")
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
	for body in MODELS:
		var m := _model(asm, body)
		for look in [{"body": body}, {"body": body, "hair": "crop"}]:
			runner.check(asm.apply(m, look) == asm.visible_meshes(look).size() and asm.visible_meshes(look)[0] == MODELS[body][1], "%s %s: 몸과 기본 옷만" % [body, look])
		m.free()
	runner.check(asm.normalize({"hair": "crop"}) == MALE_LOOK, "기본 몸은 남성, 모르는 값은 남성 기본 착장")
	runner.check(asm.normalize({"body": "bald"}) == {"body": "bald", "hair": "", "top": "base", "bottom": "base", "chalk": "", "shoes": "base"}, "대머리: 옷은 기본, 파츠 없는 슬롯은 빈 값")
	runner.check(asm.cycle({"body": "male"}, "body", 1) == "female" and asm.cycle({"body": "female"}, "body", 1) == "bald" and asm.cycle({"body": "bald"}, "body", 1) == "dummy" and asm.cycle({"body": "dummy"}, "body", 1) == "male", "몸 바꾸기")
	runner.check(asm.model_path("dummy") == MODELS.dummy[0] and asm.model_path("nope") == MODELS.male[0], "몸마다 모델, 모르는 몸은 기본")


## 여성 옷(2026-11-16, docs/46): 여성은 상의·하의·암벽화 각 기본 + 2종, 고른 옷 메시만 보이고(기본은 몸에 붙은 옷),
## 남성·더미는 기본뿐. 다른 몸의 옷을 고른 값은 기본으로.
func test_female_wardrobe() -> void:
	var asm := CharacterAssembler.load_catalog()
	for sid in ["top", "bottom", "shoes"]:
		runner.check(asm.parts_for(sid, "female").size() == 3 and asm.parts_for(sid, "male").size() == 1, "%s: 여성 3, 남성 1(기본 착장)" % sid)
	runner.check(asm.cycle({"body": "female", "top": "base"}, "top", 1) == "top_mint_tee" and asm.cycle({"body": "female", "top": "top_coral_long"}, "top", 1) == "base", "여성 상의 차례로")
	runner.check(asm.cycle({"body": "male", "top": "top_white_tee"}, "top", 1) == "top_white_tee", "남성은 흰 티뿐")
	runner.check(asm.normalize({"body": "male", "top": "top_mint_tee"}).top == "top_white_tee" and asm.normalize({"body": "male", "top": "base"}).top == "top_white_tee", "다른 몸의 옷·예전 기본값은 남성 기본(흰 티)으로")
	var m := _model(asm, "female")
	var look := {"body": "female", "top": "top_mint_tee", "bottom": "pants_olive_crop", "shoes": "shoes_teal_pair"}
	runner.check(asm.apply(m, look) == 5, "몸 + 옷 세 벌 + 7부 아래 기본 바지 아랫단")
	var vis := m.find_children("P_*", "MeshInstance3D", true, false).filter(func(n): return n.visible).map(func(n): return String(n.name))
	vis.sort()
	runner.check(vis == ["P_body_female", "P_female_pants_low", "P_pants_olive_crop", "P_shoes_teal_pair", "P_top_mint_tee"], "고른 것만 보이고 덮인 기본 옷은 숨음 %s" % [vis])
	runner.check(asm.apply(m, {"body": "female"}) == 5, "기본이면 몸 + 기본 옷 네 조각")
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
	runner.check(absf(t.ankle_L.z - (0.05 + ClimberPose.FOOT_ON_SURFACE)) < 0.001, "윗면 정보 없으면 발목은 겉면 위 %.3f" % t.ankle_L.z)
	pose = ClimberPose.new()
	var fk = s.limbs[&"LF"].key
	pose.surface_depth[fk] = 0.05
	pose.surface_top[fk] = 0.03
	t = pose.compute(s, Tuning.DT)
	var hold: Vector2 = s.route.slot_pos(fk)
	var toe: Vector3 = t.ankle_L + Anatomy.FOOT_WANT.normalized() * Anatomy.FOOT_LENGTH
	runner.check(toe.distance_to(Vector3(hold.x, hold.y + 0.03, 0.025)) < 0.001, "발끝이 홀드 윗면에 %s" % toe)
	runner.check(t.ankle_L.y > hold.y + 0.03, "발목은 홀드 윗면보다 위 %.3f" % t.ankle_L.y)


## 겨드랑이 아래 몸통 옆(골반 위 0.345~0.40m, |x| 0.13~0.17m)이 위팔을 따르는 가중치의 최댓값.
## 예전 규칙(|x|만 봄)은 이 몸통 옆이 위팔을 30~50% 따라가 팔을 들면 어깨 뒤가 가시처럼 찢어졌다(2026-11-23 사용자 "어깨가 이상").
static func arm_weight_below_armpit(m: Node, mesh_name: String) -> float:
	var mi: MeshInstance3D = m.find_children(mesh_name, "MeshInstance3D", true, false)[0]
	var sk: Skeleton3D = mi.get_node(mi.skeleton)
	var arr := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var worst := 0.0
	for i in verts.size():
		var v := verts[i]
		if absf(v.x) < 0.13 or absf(v.x) > 0.17 or v.y < 0.345 or v.y > 0.40:
			continue
		var w := 0.0
		for j in 4:
			var b := bones[i * 4 + j]
			var bone_name := String(mi.skin.get_bind_name(b)) if mi.skin != null else ""
			if bone_name == "":
				bone_name = sk.get_bone_name(mi.skin.get_bind_bone(b) if mi.skin != null else b)
			if bone_name.begins_with("upperarm"):
				w += wts[i * 4 + j]
		worst = maxf(worst, w)
	return worst


func test_bald_torso_below_armpit_ignores_arm() -> void:
	var asm := CharacterAssembler.load_catalog()
	var m := _model(asm, "bald")
	var w := arm_weight_below_armpit(m, "P_body_bald")
	runner.check(w < 0.01, "대머리: 겨드랑이 아래 몸통 옆은 위팔을 따르지 않는다(최대 %.3f)" % w)
	m.free()


## 몸 메시에서 상자(x 반폭, y 범위) 안 정점 수. Godot 좌표: y 위(골반 관절 0), x 좌우.
static func body_verts_in(m: Node, mesh_name: String, half_x: float, y0: float, y1: float) -> int:
	var mi: MeshInstance3D = m.find_children(mesh_name, "MeshInstance3D", true, false)[0]
	var n := 0
	for v in (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		if absf(v.x) < half_x and v.y > y0 and v.y < y1:
			n += 1
	return n


## 남성 기본 착장(2026-11-23, docs/56): 다섯 가지를 입고 나오고, 옷이 덮는 피부는 지워 큰 자세에서도 뚫고 나오지 않는다.
func test_male_default_outfit() -> void:
	var asm := CharacterAssembler.load_catalog()
	runner.check(asm.normalize({"body": "male"}) == MALE_LOOK, "남성 기본 = 바가지 머리·흰 티·청바지·회색 초크백·벨크로 암벽화")
	for sid in ["hair", "chalk"]:
		runner.check(asm.parts_for(sid, "male").size() == 1 and asm.parts_for(sid, "female").is_empty() and asm.parts_for(sid, "bald").is_empty(), "%s: 남성만" % sid)
	var m := _model(asm, "male")
	runner.check(asm.apply(m, {"body": "male"}) == MALE_MESHES.size(), "몸 + 옷 다섯")
	var vis := m.find_children("P_*", "MeshInstance3D", true, false).filter(func(n): return n.visible).map(func(n): return String(n.name))
	vis.sort()
	runner.check(vis == MALE_MESHES, "보이는 메시 %s" % [vis])
	var total := 0
	for name in MALE_MESHES:
		var mi: MeshInstance3D = m.find_children(name, "MeshInstance3D", true, false)[0]
		runner.check(mi.skin != null and mi.get_node_or_null(mi.skeleton) is Skeleton3D, "%s: 같은 뼈대에 스키닝" % name)
		var tris: int = (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		total += tris
		if name != "P_body_male":
			runner.check(tris <= OUTFIT_PART_BUDGET, "%s 삼각형 %d ≤ %d" % [name, tris, OUTFIT_PART_BUDGET])
	runner.check(total <= MALE_TOTAL_BUDGET, "남성 전체 삼각형 %d ≤ %d" % [total, MALE_TOTAL_BUDGET])
	# 덮인 피부는 지웠다: 가슴·배(티 안), 허벅지·정강이(청바지 안)에 몸 정점이 없다. 맨몸(대머리)에는 있다.
	var bald := _model(asm, "bald")
	for box in [[0.10, 0.20, 0.40, "가슴·배"], [0.25, -0.70, -0.10, "다리"]]:
		var n_male := body_verts_in(m, "P_body_male", box[0], box[1], box[2])
		var n_bald := body_verts_in(bald, "P_body_bald", box[0], box[1], box[2])
		runner.check(n_male == 0 and n_bald > 100, "%s: 남성 몸 정점 %d(지움), 맨몸 %d" % [box[3], n_male, n_bald])
	bald.free()
	# 티는 몸 가중치를 그대로 쓴다: 겨드랑이 아래 옆구리 천도 위팔을 따르지 않는다(docs/55 §6 어깨 가시).
	var w := arm_weight_below_armpit(m, "P_top_white_tee")
	runner.check(w < 0.01, "흰 티: 겨드랑이 아래 옆구리는 위팔을 따르지 않는다(최대 %.3f)" % w)
	m.free()


## 캐릭터 고르기 미리보기는 팔을 내린 자세(2026-11-23 사용자 "팔을 들고 있지 말고 내려"): 손이 어깨보다 한참 아래, 몸 옆.
## 쉬는 자세에서 계산하므로 두 번 불러도 같다.
func test_relax_arms_lowers_hands() -> void:
	var asm := CharacterAssembler.load_catalog()
	for body in ["male", "female", "bald"]:
		var m := _model(asm, body)
		var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
		CharacterAssembler.relax_arms(m)
		CharacterAssembler.relax_arms(m)
		sk.force_update_all_bone_transforms()  # 트리 밖이라 전역 자세를 직접 갱신
		for s in ["L", "R"]:
			var sh := sk.get_bone_global_pose(sk.find_bone("upperarm_" + s)).origin
			var hand := sk.get_bone_global_pose(sk.find_bone("hand_" + s)).origin
			var elbow := sk.get_bone_global_pose(sk.find_bone("forearm_" + s)).origin
			runner.check(hand.y < sh.y - 0.6 and absf(hand.x) < 0.40 and signf(hand.x) == signf(sh.x), "%s %s 손이 어깨 아래 몸 옆 %s" % [body, s, hand])
			runner.check(hand.z < elbow.z - 0.02, "%s %s 팔꿈치를 앞(−z)으로 살짝 굽힘 %.3f" % [body, s, hand.z - elbow.z])
		m.free()
