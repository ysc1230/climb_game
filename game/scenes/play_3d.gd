extends Node3D
## 3단계 대표 장면 시험. 판정·입력은 자식 PlayTest(2D, draw_world=false)가 맡고
## 이 노드는 그 상태를 읽어 3D로 그리기만 한다(docs/08 CharacterPresenter 역할).
## 벽 평면 z=0, 카메라는 +Z에서 벽을 본다. 판정은 X/Y 평면, Z는 표현 전용(docs/04).

const INK := Color("302820")
const WALL_CLAY := Color("a66a4a")
const WALL_SAND := Color("c2936c")
const WALL_OLIVE := Color("5f6047")
const HOLD_RUST := Color("985448")
const CLOTH_TEAL := Color("4f6a68")
const CLOTH_IVORY := Color("c7b79b")
const TARGET_CREAM := Color("f1d59a")
const SKIN := Color("b98a6a")

const PELVIS_DEPTH := 0.28   # 골반이 벽에서 떨어진 기본 거리
const CONTACT_DEPTH := 0.07  # 손발 접점(홀드 표면) 깊이
const PLAY_H := 3.8
const PLAY_W := 3.4

var logic  # PlayTest 노드
var toon_shader := preload("res://art/shaders/toon.gdshader")
var outline_shader := preload("res://art/shaders/outline.gdshader")
var camera: Camera3D
var parts := {}       # 이름 -> MeshInstance3D (모델이 없을 때의 대체 캡슐)
var skeleton: Skeleton3D
var candidate_ring: MeshInstance3D
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 1230
	logic = $UI/PlayTest
	logic.draw_world = false
	_build_environment()
	_build_wall()
	_build_holds()
	if not _build_model():
		_build_character()
	candidate_ring = _mesh(_torus(0.10, 0.012), _unshaded(TARGET_CREAM), false)
	add_child(candidate_ring)


# ---------- 재질 ----------

func _toon(albedo: Color, shade: Color, wall := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = toon_shader
	m.set_shader_parameter("albedo", albedo)
	m.set_shader_parameter("shade", shade)
	m.set_shader_parameter("wall_pattern", wall)
	var o := ShaderMaterial.new()
	o.shader = outline_shader
	o.set_shader_parameter("ink", INK)
	o.set_shader_parameter("width", 0.03)
	m.next_pass = o
	return m


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _mesh(mesh: Mesh, mat: Material, vertex_dir: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if mat is ShaderMaterial and mat.next_pass:
		mat.next_pass.set_shader_parameter("use_vertex_dir", vertex_dir)
	return mi


func _torus(r: float, t: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = r - t
	m.outer_radius = r + t
	m.rings = 24
	m.ring_segments = 6
	return m


# ---------- 환경 ----------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("3a2a22")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("7a5c50")
	env.ambient_light_energy = 0.65
	env.fog_enabled = true
	env.fog_light_color = Color("c48a68")
	env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("f0d6c2")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-38, -32, 0)  # 화면 왼쪽 위에서 들어오는 따뜻한 주광
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 30.0
	add_child(camera)


# ---------- 벽 ----------

func _build_wall() -> void:
	var top: float = logic.route.slots.values().reduce(func(a, s): return maxf(a, s.pos.y), 0.0) + 2.5
	# 활성 등반 평면: 슬롯이 놓이는 큰 판(살짝 기울어진 패널로 나눔)
	var y := -0.6
	var i := 0
	while y < top:
		var h := rng.randf_range(0.9, 1.4)
		for col in [-1, 1]:
			var panel := _mesh(_box(Vector3(1.55, h, 0.08)), _toon(WALL_CLAY.lerp(WALL_SAND, rng.randf() * 0.5), WALL_OLIVE, true), true)
			panel.position = Vector3(col * 0.78, y + h * 0.5, -0.06 - rng.randf() * 0.03)
			panel.rotation_degrees = Vector3(rng.randf_range(-2, 2), rng.randf_range(-3, 3) * col, 0)
			add_child(panel)
		y += h
		i += 1
	# 바닥 매트
	var mat := _mesh(_box(Vector3(9.0, 0.25, 4.0)), _toon(Color("4a5a55"), Color("2c3532")), true)
	mat.position = Vector3(0, -0.20, 1.6)
	add_child(mat)
	# 좌우 비활성 볼륨: 각진 다면체와 측면 벽(공간감, 판정 없음)
	for side in [-1, 1]:
		var wing := _mesh(_box(Vector3(2.4, top + 1.0, 0.2)), _toon(WALL_SAND.darkened(0.08), WALL_OLIVE, true), true)
		wing.position = Vector3(side * 2.75, (top - 1.0) * 0.5, 0.35)
		wing.rotation_degrees = Vector3(0, -side * 38, 0)
		add_child(wing)
		for k in 6:
			var size := rng.randf_range(0.35, 0.8)
			var prism := _mesh(_prism(Vector3(size, size * 1.3, size * 0.7)), _toon(WALL_OLIVE if k % 2 == 0 else WALL_SAND, WALL_OLIVE.darkened(0.3)), true)
			var along := rng.randf_range(-0.9, 0.9)
			var wing_dir := Vector3(cos(deg_to_rad(-side * 38)), 0, -sin(deg_to_rad(-side * 38)))
			var wing_normal := Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(-side * 38))
			prism.position = wing.position + wing_dir * along + wing_normal * (0.1 + size * 0.2)
			prism.position.y = rng.randf_range(0.6, top - 1.0)
			prism.rotation_degrees = Vector3(-90, -side * 38, rng.randf_range(0, 360))
			add_child(prism)
	# 활성 벽 위의 장식 볼륨(접점 없는 큰 돌출, 활성 슬롯과 겹치지 않게 가장자리에)
	for k in 5:
		var s := rng.randf_range(0.25, 0.45)
		var deco := _mesh(_prism(Vector3(s, s * 1.4, s * 0.5)), _toon(WALL_SAND, WALL_OLIVE), true)
		deco.position = Vector3((1 if k % 2 == 0 else -1) * rng.randf_range(1.25, 1.5), rng.randf_range(0.5, top - 1.5), 0.05)
		deco.rotation_degrees = Vector3(0, 0, rng.randf_range(0, 360))
		add_child(deco)


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _prism(size: Vector3) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = size
	return p


# ---------- 홀드 ----------

func _build_holds() -> void:
	for key in logic.route.slots:
		var slot: Dictionary = logic.route.slots[key]
		var is_goal: bool = logic.route.goal_slots.has(key)
		var hand: bool = slot.allowed.has(&"LH")
		var col := TARGET_CREAM if is_goal else (HOLD_RUST if hand else WALL_OLIVE)
		var r := rng.randf_range(0.065, 0.085) if hand else rng.randf_range(0.055, 0.07)
		var sphere := SphereMesh.new()
		sphere.radius = r
		sphere.height = r * 1.5
		sphere.radial_segments = 6
		sphere.rings = 3
		var hold := _mesh(sphere, _toon(col, col.darkened(0.45)), false)
		var p: Vector2 = slot.pos
		hold.position = Vector3(p.x, p.y, 0.0)
		hold.rotation_degrees = Vector3(rng.randf_range(-20, 20), rng.randf_range(0, 360), rng.randf_range(0, 360))
		hold.scale = Vector3(rng.randf_range(0.9, 1.3), rng.randf_range(0.8, 1.1), 0.75)
		add_child(hold)


# ---------- 캐릭터 ----------

func _build_character() -> void:
	var cloth := _toon(CLOTH_TEAL, CLOTH_TEAL.darkened(0.45))
	var pants := _toon(CLOTH_IVORY, CLOTH_IVORY.darkened(0.4))
	var skin := _toon(SKIN, SKIN.darkened(0.4))
	var shoe := _toon(HOLD_RUST.darkened(0.15), INK)
	var pack := _toon(Color("6b5240"), INK)
	parts.torso = _capsule_part(0.15, cloth)
	parts.hips = _capsule_part(0.13, pants)
	parts.head = _mesh(_sphere(0.115), _toon(Color("3b2e26"), INK), false)  # 뒷머리
	parts.pack = _mesh(_box(Vector3(0.30, 0.36, 0.14)), pack, true)
	for limb in PoseSolver.LIMBS:
		var hand := PoseSolver.is_hand(limb)
		parts[str(limb) + "_upper"] = _capsule_part(0.055 if hand else 0.075, cloth if hand else pants)
		parts[str(limb) + "_lower"] = _capsule_part(0.045 if hand else 0.06, skin if hand else pants)
		parts[str(limb) + "_end"] = _mesh(_sphere(0.05 if hand else 0.065), skin if hand else shoe, false)
	for p in parts.values():
		add_child(p)


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 6
	return s


func _capsule_part(radius: float, mat: Material) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = 1.0  # 매 프레임 길이에 맞춰 Y 스케일
	c.radial_segments = 10
	c.rings = 2
	return _mesh(c, mat, false)


## 캡슐을 a→b 구간에 맞춘다(캡슐 기본 축은 Y).
func _place_segment(part: MeshInstance3D, a: Vector3, b: Vector3, radius: float) -> void:
	var d := b - a
	var length := maxf(d.length(), 0.001)
	var y := d / length
	var x := y.cross(Vector3.BACK)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var mesh := part.mesh as CapsuleMesh
	var s := (length + radius * 2.0) / mesh.height
	part.transform = Transform3D(Basis(x, y * s, z), (a + b) * 0.5)


## 판정 거리를 바꾸지 않으면서 3D 팔다리 길이에 맞도록 골반 깊이를 줄인다(docs/23 항목 4).
func _body_depth() -> float:
	var depth := PELVIS_DEPTH
	for limb in PoseSolver.LIMBS:
		var j := PoseSolver.joint_position(logic.body.pos, logic.body.angle, limb)
		var e: Vector2 = logic.limbs[limb].pos
		var full := (Tuning.ARM_UPPER + Tuning.ARM_LOWER) if PoseSolver.is_hand(limb) else (Tuning.LEG_UPPER + Tuning.LEG_LOWER)
		var d2 := j.distance_squared_to(e)
		var max_dz := sqrt(maxf(full * full * 0.985 - d2, 0.0))
		depth = minf(depth, CONTACT_DEPTH + max_dz)
	return maxf(depth, CONTACT_DEPTH + 0.02)


## 3D 두 뼈 IK. 관절은 벽 바깥(+Z)과 몸 바깥쪽으로 꺾는다.
func _two_bone(root: Vector3, end: Vector3, a: float, b: float, pole: Vector3) -> Vector3:
	var v := end - root
	var d := clampf(v.length(), absf(a - b) + 0.001, a + b - 0.001)
	var dir := v.normalized() if v.length() > 0.0001 else Vector3.DOWN
	var x := (a * a - b * b + d * d) / (2.0 * d)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var bend := (pole - dir * pole.dot(dir))
	bend = bend.normalized() if bend.length() > 0.0001 else Vector3.BACK
	return root + dir * x + bend * h


func _process(_delta: float) -> void:
	if logic == null or logic.body == null:
		return
	_update_camera()
	var t := _pose_targets()
	if skeleton:
		_pose_model(t)
	else:
		_pose_capsules(t)
	_update_candidate()


## 판정 상태에서 표현용 3D 관절 위치를 만든다. 판정 거리는 바꾸지 않는다.
func _pose_targets() -> Dictionary:
	var body: BodyState = logic.body
	var depth := _body_depth()
	var ang := deg_to_rad(body.angle)
	var up := Vector3(-sin(ang), cos(ang), 0)
	var pelvis := Vector3(body.pos.x, body.pos.y, depth)
	var t := {"pelvis": pelvis, "spine": pelvis + up * 0.22, "chest": pelvis + up * 0.44,
		"neck": pelvis + up * 0.63, "head": pelvis + up * 0.80, "head_top": pelvis + up * 0.94, "up": up}
	for limb in PoseSolver.LIMBS:
		var hand := PoseSolver.is_hand(limb)
		var j2 := PoseSolver.joint_position(body.pos, body.angle, limb)
		var root := Vector3(j2.x, j2.y, depth + (0.02 if hand else 0.0))
		var e2: Vector2 = logic.limbs[limb].pos
		var state: String = logic.limbs[limb].state
		var end_z := CONTACT_DEPTH if state in ["Attached", "Armed"] else CONTACT_DEPTH + 0.12
		var end := Vector3(e2.x, e2.y, end_z)
		var a := Tuning.ARM_UPPER if hand else Tuning.LEG_UPPER
		var b := Tuning.ARM_LOWER if hand else Tuning.LEG_LOWER
		var side := -1.0 if limb in [&"LH", &"LF"] else 1.0
		var pole := Vector3(side * (0.6 if hand else 0.9), -0.5 if hand else 0.2, 0.8)
		var mid := _two_bone(root, end, a, b, pole)
		var s := "L" if side < 0 else "R"
		if hand:
			t["shoulder_" + s] = root
			t["elbow_" + s] = mid
			t["wrist_" + s] = end
			t["hand_" + s] = end + (end - mid).normalized() * 0.09
		else:
			t["hip_" + s] = root
			t["knee_" + s] = mid
			t["ankle_" + s] = end
			t["toe_" + s] = end + Vector3(0, -0.04, -0.15)
	return t


func _pose_capsules(t: Dictionary) -> void:
	var up: Vector3 = t.up
	_place_segment(parts.hips, t.pelvis + up * -0.02, t.pelvis + up * 0.12, 0.13)
	_place_segment(parts.torso, t.pelvis + up * 0.15, t.pelvis + up * 0.50, 0.15)
	parts.head.position = t.head + Vector3(0, 0, 0.02)
	parts.pack.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(logic.body.angle)), t.pelvis + up * 0.36 + Vector3(0, 0, 0.17))
	for limb in PoseSolver.LIMBS:
		var hand := PoseSolver.is_hand(limb)
		var s := "L" if limb in [&"LH", &"LF"] else "R"
		var root: Vector3 = t[("shoulder_" if hand else "hip_") + s]
		var mid: Vector3 = t[("elbow_" if hand else "knee_") + s]
		var end: Vector3 = t[("wrist_" if hand else "ankle_") + s]
		_place_segment(parts[str(limb) + "_upper"], root, mid, 0.055 if hand else 0.075)
		_place_segment(parts[str(limb) + "_lower"], mid, end, 0.045 if hand else 0.06)
		parts[str(limb) + "_end"].position = end


## 뼈 이름 -> [시작 관절, 끝 관절]. 부모가 먼저 오도록 정렬.
const BONE_MAP := [
	["pelvis", "pelvis", "spine"], ["spine", "spine", "chest"], ["chest", "chest", "neck"],
	["neck", "neck", "head"], ["head", "head", "head_top"],
	["upperarm_L", "shoulder_L", "elbow_L"], ["forearm_L", "elbow_L", "wrist_L"], ["hand_L", "wrist_L", "hand_L"],
	["upperarm_R", "shoulder_R", "elbow_R"], ["forearm_R", "elbow_R", "wrist_R"], ["hand_R", "wrist_R", "hand_R"],
	["thigh_L", "hip_L", "knee_L"], ["shin_L", "knee_L", "ankle_L"], ["foot_L", "ankle_L", "toe_L"],
	["thigh_R", "hip_R", "knee_R"], ["shin_R", "knee_R", "ankle_R"], ["foot_R", "ankle_R", "toe_R"],
]
var _rest_dirs := {}


func _pose_model(t: Dictionary) -> void:
	var inv := skeleton.global_transform.affine_inverse()
	for entry in BONE_MAP:
		var idx := skeleton.find_bone(entry[0])
		if idx < 0:
			continue
		var rest := skeleton.get_bone_global_rest(idx)
		var from_p: Vector3 = inv * (t[entry[1]] as Vector3)
		var to_p: Vector3 = inv * (t[entry[2]] as Vector3)
		var new_dir := (to_p - from_p).normalized()
		var rest_dir: Vector3 = _rest_dirs[entry[0]]
		var q := Quaternion(rest_dir, new_dir) if rest_dir.dot(new_dir) > -0.999 else Quaternion(rest.basis.x.normalized(), PI)
		skeleton.set_bone_global_pose(idx, Transform3D(Basis(q) * rest.basis, from_p))


func _build_model() -> bool:
	if not ResourceLoader.exists("res://art/characters/climber.glb"):
		return false
	var model: Node3D = load("res://art/characters/climber.glb").instantiate()
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] if model.find_children("*", "Skeleton3D", true, false).size() > 0 else null
	if skeleton == null:
		model.queue_free()
		return false
	# 휴지 자세의 뼈 방향: 다음 관절(자식 뼈) 원점 방향, 말단은 뼈 Y축
	for entry in BONE_MAP:
		var idx := skeleton.find_bone(entry[0])
		if idx < 0:
			continue
		var rest := skeleton.get_bone_global_rest(idx)
		var dir := rest.basis.y.normalized()
		for c in skeleton.get_bone_children(idx):
			dir = (skeleton.get_bone_global_rest(c).origin - rest.origin).normalized()
			break
		_rest_dirs[entry[0]] = dir
	var colors := {"M_shirt": CLOTH_TEAL, "M_skin": SKIN, "M_shorts": Color("6e5a48"), "M_bandage": CLOTH_IVORY,
		"M_shoe": Color("7e4a3e"), "M_hair": Color("3b2e26"), "M_pack": Color("6b5240"), "M_bandana": HOLD_RUST}
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(i)
			var c: Color = colors.get(m.resource_name if m else "", CLOTH_TEAL)
			var toon := _toon(c, c.darkened(0.45))
			toon.next_pass.set_shader_parameter("width", 0.012)
			mi.set_surface_override_material(i, toon)
	return true


func _update_camera() -> void:
	var size := get_viewport().get_visible_rect().size
	if size.y <= 0:
		return
	# 높이 3.8m를 기본으로, 중앙 56% 폭에 3.4m가 들어가지 않으면 시야를 넓힌다(docs/05 고정 플레이 창).
	var visible_h := maxf(PLAY_H, PLAY_W * size.y / maxf(size.x * 0.56, 1.0))
	var dist := (visible_h * 0.5) / tan(deg_to_rad(camera.fov * 0.5))
	camera.position = Vector3(0, logic.cam_y, CONTACT_DEPTH + dist)
	camera.rotation = Vector3.ZERO


func _update_candidate() -> void:
	candidate_ring.visible = false
	for limb in logic.limbs:
		if logic.limbs[limb].state == "Dragging":
			var key: String = logic._candidate(limb)
			if not key.is_empty():
				var p: Vector2 = logic.route.slot_pos(key)
				candidate_ring.position = Vector3(p.x, p.y, CONTACT_DEPTH + 0.03)
				candidate_ring.rotation_degrees = Vector3(90, 0, 0)
				candidate_ring.visible = true
				return
