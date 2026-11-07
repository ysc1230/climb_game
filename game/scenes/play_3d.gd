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

const CONTACT_DEPTH := Tuning.CONTACT_DEPTH
const PLAY_H := 3.8
const PLAY_W := 3.4

var logic  # PlayTest 노드
var toon_shader := preload("res://art/shaders/toon.gdshader")
var outline_shader := preload("res://art/shaders/outline.gdshader")
var camera: Camera3D
var parts := {}       # 이름 -> MeshInstance3D (모델이 없을 때의 대체 캡슐)
var skeleton: Skeleton3D
var foot_marks := {}  # foot -> [채운, 빈]
var flag_marks := {}  # foot -> 균형 발 마름모
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 1230
	logic = $UI/PlayTest
	logic.draw_world = false
	logic.w2s_fn = world_to_screen
	logic.s2w_fn = screen_to_wall
	_build_environment()
	_build_wall()
	_build_holds()
	if not _build_model():
		_build_character()
	# 발 하중 표시(docs/25): 채운 삼각형 = Loaded, 빈 삼각형 = Attached·Unloaded
	for foot in [&"LF", &"RF"]:
		var filled := _mesh(_tri_mesh(false), _overlay(TARGET_CREAM), false)
		var hollow := _mesh(_tri_mesh(true), _overlay(TARGET_CREAM), false)
		add_child(filled)
		add_child(hollow)
		foot_marks[foot] = [filled, hollow]
		var diamond := _mesh(_diamond_mesh(), _overlay(Color("a8d8d0")), false)
		add_child(diamond)
		flag_marks[foot] = diamond


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


## 다른 물체에 가려지지 않는 표시용 재질(판정 피드백)
func _overlay(c: Color) -> StandardMaterial3D:
	var m := _unshaded(c)
	m.no_depth_test = true
	m.render_priority = 10
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
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

var hold_glows := {}  # 슬롯 키 → 홀드 위에 겹친 빛 메시(잡을 수 있음: 흰색 깜빡임, 튜토리얼 목표: 노란색 깜빡임)


## 홀드 디자인 v2(docs/32): Blender로 만든 실제 크기 로우폴리 레진 홀드(art/holds/holds.glb, tools/holds/make_holds.py).
## v8: 홀드 크기는 잡기 영역 반폭에서 정한다(보이는 크기 = 잡는 크기). 아주 작음~아주 큼 다섯 등급마다
## 어울리는 종류(크림프·너브·포켓·에지·핀치·저그·슬로퍼)를 고른다. 작을수록 잡기 반경도 작아 정확히 가져가야 한다.
const HOLD_MESHES := preload("res://art/holds/holds.glb")
const HOLD_COLORS := {
	"hand": [Color("2b7a6f"), Color("8fd0bc")],
	"match": [Color("2f5fc4"), Color("9cc0f4")],  # 합손 가능(hand_area.matchable)
	"foot": [Color("5e4c70"), Color("c4b0d6")],
	"goal": [Color("d9b872"), Color("f1d59a")],
}
## 크기 등급(손홀드 반폭 기준, v8): 보이는 크기 = 잡는 크기. 작은 홀드는 잡기 반경도 작다(GripCheck.radius_for).
const HAND_SIZE_CLASSES := [
	[0.05, ["hs_crimp_1", "hs_nub_0", "hs_pocket_0"]],                     # 아주 작음
	[0.09, ["hs_crimp_0", "hs_edge_1", "hs_pinch_0", "hs_pocket_0", "hs_nub_1"]],  # 작음
	[0.13, ["hs_edge_0", "hm_jug_0", "hs_nub_0", "hm_sloper_0"]],          # 중간
	[0.17, ["hm_jug_0", "hm_sloper_0"]],                                   # 큼
	[INF, ["hl_jug_0", "hl_sloper_0"]],                                    # 아주 큼
]
const HOLD_FOOT := ["f_chip_0", "f_chip_1", "f_chip_2", "f_edge_0"]
var _hold_mesh_cache := {}


func _hold_mesh(name: String) -> Mesh:
	if _hold_mesh_cache.is_empty():
		var root := HOLD_MESHES.instantiate()
		for n in root.find_children("*", "MeshInstance3D", true, false):
			_hold_mesh_cache[String(n.name)] = (n as MeshInstance3D).mesh
		root.free()
	return _hold_mesh_cache.get(name)


## 슬롯에 놓을 홀드 메시 이름(크기 등급 안에서 키 해시로 고정된 무작위).
static func hold_variant(key: String, slot: Dictionary, is_goal: bool) -> String:
	var h := absi(hash(key))
	if is_goal:
		return "goal"
	if not slot.has("hand_area"):
		return HOLD_FOOT[h % HOLD_FOOT.size()]
	var hw := float(slot.hand_area.half_width)
	for c in HAND_SIZE_CLASSES:
		if hw < float(c[0]):
			return c[1][h % (c[1] as Array).size()]
	return "hl_jug_0"


## 보이는 길이(잡는 방향): 손 2·반폭 + 2·두께, 발 2·발 반폭 + 0.02. 메시 원래 길이로 나눈 균일 배율.
static func hold_view_scale(slot: Dictionary, mesh: Mesh, is_goal: bool) -> float:
	if is_goal:
		return 1.25
	var target: float
	if slot.has("hand_area"):
		target = 2.0 * float(slot.hand_area.half_width) + 2.0 * GripCheck.hand_thickness(slot)
	else:
		target = 2.0 * GripCheck.foot_half_width(slot) + 0.02
	var native := maxf(mesh.get_aabb().size.x, 0.01)
	return maxf(0.45, target / native)


func _build_holds() -> void:
	for key in logic.route.slots:
		var slot: Dictionary = logic.route.slots[key]
		var is_goal: bool = logic.route.goal_slots.has(key)
		var hand: bool = slot.has("hand_area")
		var kind := "goal" if is_goal else ("foot" if not hand else ("match" if slot.hand_area.get("matchable", false) else "hand"))
		var variant := hold_variant(key, slot, is_goal)
		var mesh := _hold_mesh(variant)
		var ang: float = (slot.hand_area.dir as Vector2).angle() if hand else (slot.foot_area.up as Vector2).angle() - PI / 2.0
		var hold := MeshInstance3D.new()
		hold.mesh = mesh
		var cols: Array = HOLD_COLORS[kind]
		var mats := [_toon(cols[0], cols[0].darkened(0.45)), _toon(cols[1], cols[1].darkened(0.35)), _toon(INK, INK.darkened(0.3))]
		for si in mesh.get_surface_count():
			var m: ShaderMaterial = mats[mini(si, 2)]
			m.next_pass.set_shader_parameter("width", 0.006)
			hold.set_surface_override_material(si, m)
		var p: Vector2 = slot.pos
		hold.position = Vector3(p.x, p.y, 0.0)
		hold.rotation = Vector3(0, 0, ang + deg_to_rad(rng.randf_range(-8, 8)))
		hold.scale = Vector3.ONE * hold_view_scale(slot, mesh, is_goal) * rng.randf_range(0.95, 1.05)
		add_child(hold)
		var glow := MeshInstance3D.new()
		glow.mesh = mesh
		var gm := _overlay(Color(1, 1, 1, 0.0))
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.material_override = gm
		glow.position = hold.position + Vector3(0, 0, 0.004)
		glow.rotation = hold.rotation
		glow.scale = hold.scale * 1.18
		glow.visible = false
		add_child(glow)
		hold_glows[key] = glow


## 홀드 빛: 끄는 손발 아래 지금 놓으면 잡히는 홀드(세션 후보)는 흰색으로 깜빡이며 빛나고,
## 튜토리얼 목표 홀드는 노란색으로 깜빡인다. 잡을 수 있는 쪽이 우선이다.
func _update_hold_glow() -> void:
	var t := Time.get_ticks_msec() * 0.001
	var fast := 0.5 + 0.5 * sin(TAU * 2.2 * t)
	var slow := 0.5 + 0.5 * sin(TAU * 1.2 * t)
	var grab := {}
	if not logic.session.selecting:
		for limb in logic.session.limbs:
			var l: Dictionary = logic.session.limbs[limb]
			if l.state == "Dragging" and not l.cand.is_empty():
				grab[l.cand.key] = true
	var goal: String = logic._tutorial_goal_key()
	for key in hold_glows:
		var g: MeshInstance3D = hold_glows[key]
		var m := g.material_override as StandardMaterial3D
		if grab.has(key):
			g.visible = true
			m.albedo_color = Color(1, 1, 1, 0.35 + 0.6 * fast)
		elif key == goal:
			g.visible = true
			m.albedo_color = Color(1.0, 0.86, 0.35, 0.25 + 0.5 * slow)
		else:
			g.visible = false


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


func _process(delta: float) -> void:
	if logic == null or logic.session == null:
		return
	_update_camera()
	var t := _pose_targets(delta)
	if skeleton:
		_pose_model(t, delta)
		_update_face()
	else:
		_pose_capsules(t)
	_update_hold_glow()
	_update_foot_marks()


var climber_pose := ClimberPose.new()


## 판정 상태 → 표현용 3D 관절 위치(ClimberPose, docs/04 §8).
func _pose_targets(delta: float) -> Dictionary:
	return climber_pose.compute(logic.session, delta)


func _pose_capsules(t: Dictionary) -> void:
	var up: Vector3 = t.up
	_place_segment(parts.hips, t.pelvis + up * -0.02, t.pelvis + up * 0.12, 0.13)
	_place_segment(parts.torso, t.pelvis + up * 0.15, t.pelvis + up * 0.50, 0.15)
	parts.head.position = t.head + Vector3(0, 0, 0.02)
	parts.pack.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(logic.session.body.angle)), t.pelvis + up * 0.36 + Vector3(0, 0, 0.17))
	for limb in PoseSolver.LIMBS:
		var hand := PoseSolver.is_hand(limb)
		var s := "L" if limb in [&"LH", &"LF"] else "R"
		var root: Vector3 = t[("shoulder_" if hand else "hip_") + s]
		var mid: Vector3 = t[("elbow_" if hand else "knee_") + s]
		var end: Vector3 = t[("wrist_" if hand else "ankle_") + s]
		_place_segment(parts[str(limb) + "_upper"], root, mid, 0.055 if hand else 0.075)
		_place_segment(parts[str(limb) + "_lower"], mid, end, 0.045 if hand else 0.06)
		parts[str(limb) + "_end"].position = end


## 관절 키 -> 그 관절에서 시작하는 뼈(휴지 위치 조회용)
const JOINT_BONE := {"pelvis": "pelvis", "spine": "spine", "chest": "chest", "neck": "neck", "head": "head",
	"shoulder_L": "upperarm_L", "elbow_L": "forearm_L", "wrist_L": "hand_L",
	"shoulder_R": "upperarm_R", "elbow_R": "forearm_R", "wrist_R": "hand_R",
	"hip_L": "thigh_L", "knee_L": "shin_L", "ankle_L": "foot_L",
	"hip_R": "thigh_R", "knee_R": "shin_R", "ankle_R": "foot_R"}
var rig := RigPose.new()


## RigPose(docs/04 §8)가 만든 연속 프레임을 그대로 적용한다. 180° 대체 회전 없음.
func _pose_model(t: Dictionary, delta: float) -> void:
	var inv := skeleton.global_transform.affine_inverse()
	var local := {}
	for key in t:
		if t[key] is Vector3 and key != "up":
			local[key] = inv * (t[key] as Vector3)
	var frames := rig.solve(local, logic.session.body.angle, logic.session.body.yaw)
	_apply_look(frames, inv, delta)
	for entry in RigPose.BONES:
		var idx := skeleton.find_bone(entry[0])
		if idx >= 0 and frames.has(entry[0]):
			skeleton.set_bone_global_pose(idx, frames[entry[0]])


## CH02 캐릭터 시트(2026-11-07, art_source/character/build_climber.py PALETTE와 같은 값).
const CHARACTER_COLORS := {
	"M_hair": Color("6b4129"), "M_skin": Color("e8b48e"), "M_shirt": Color("f1ebe0"), "M_pants": Color("4f6b9e"),
	"M_belt": Color("3a393b"), "M_buckle": Color("8c8c8c"), "M_chalk": Color("7a7472"), "M_chalk_rim": Color("4a4645"),
	"M_shoe": Color("a39c94"), "M_strap": Color("c4beb5"), "M_rubber": Color("3d3a38"),
	"M_face_eye": Color("2a1d18"), "M_face_hi": Color("ffffff"), "M_face_mouth": Color("8a3a34"), "M_face_brow": Color("4a2c1c"),
	"M_face_cheek": Color("f29a8a"), "M_face_teeth": Color("fbf7f0"),
}
const LOOK_MAX_DEG := 80.0   # 머리를 돌리는 최대 각
const LOOK_BACK_DEG := 125.0 # 정상·추락 때 어깨 너머로 돌아보는 각
const LOOK_SPEED := 6.0      # 1/s, 목표 방향으로 따라가는 빠르기
var face_meshes := {}        # 표정 이름 -> MeshInstance3D(FX_face_*)
var face_now := ""
var _look := Quaternion.IDENTITY


## 표정(표현 전용): 떨어지는 중 놀람, 정상을 잡으면 기쁨, 팔 힘이 45 아래이거나 자세가 무너지는 중이면 힘씀, 그 밖에는 평온.
static func expression_for(falling: bool, at_goal: bool, min_stamina: float, rebalancing: bool) -> String:
	if falling:
		return "scared"
	if at_goal:
		return "happy"
	if min_stamina < 45.0 or rebalancing:
		return "effort"
	return "calm"


func _set_face(name: String) -> void:
	if name == face_now or not face_meshes.has(name):
		return
	face_now = name
	for k in face_meshes:
		face_meshes[k].visible = k == name


func _update_face() -> void:
	var s = logic.session
	var st: Dictionary = s.rules.stamina
	var low := 100.0
	for v in st.values():
		low = minf(low, v)
	_set_face(expression_for(s.falling, s.goal_ticks > 0, low, s.rules.phase == ClimbRules.Phase.REBALANCING))


## 끌고 있는 손발(손 우선)의 말단 위치를 본다. 없으면 정면으로 돌아온다. 얼굴이 벽을 보므로 옆을 볼 때 옆얼굴이 보인다.
func _look_target() -> Variant:
	var best: Variant = null
	for limb in [&"LH", &"RH", &"LF", &"RF"]:
		var l: Dictionary = logic.session.limbs[limb]
		if l.state == "Dragging":
			var p: Vector2 = l.pos
			best = Vector3(p.x, p.y, CONTACT_DEPTH)
			break
	return best


func _apply_look(frames: Dictionary, inv: Transform3D, delta: float) -> void:
	if not frames.has("head"):
		return
	var head: Transform3D = frames["head"]
	var want := Quaternion.IDENTITY
	var target: Variant = _look_target()
	var body_up0: Vector3 = (head.basis * Vector3.UP).normalized()
	var side0: Vector3 = (head.basis * Vector3.RIGHT).normalized()
	if face_now in ["happy", "scared"]:
		# 정상을 잡았을 때·떨어질 때는 어깨 너머로 카메라 쪽을 돌아본다(표정이 보이는 순간).
		want = Quaternion(body_up0, deg_to_rad(LOOK_BACK_DEG)) * Quaternion(side0, -0.12)
	elif target != null:
		# 옆으로 먼저 돌리고(좌우 1m에 약 80°) 위아래는 조금만 든다. 얼굴이 벽을 보므로 옆으로 돌아야 표정이 보인다.
		var d: Vector3 = (inv * (target as Vector3)) - head.origin
		var body_up: Vector3 = (head.basis * Vector3.UP).normalized()
		var side: Vector3 = (head.basis * Vector3.RIGHT).normalized()
		var yaw := clampf(d.dot(side) * 1.6, -deg_to_rad(LOOK_MAX_DEG), deg_to_rad(LOOK_MAX_DEG))
		var pitch := clampf(d.dot(body_up) * 0.35, -0.25, 0.4)
		want = Quaternion(body_up, -yaw) * Quaternion(side, pitch)
	_look = _look.slerp(want, minf(1.0, LOOK_SPEED * delta))
	frames["head"] = Transform3D(Basis(_look) * head.basis, head.origin)


func _build_model() -> bool:
	if not ResourceLoader.exists("res://art/characters/climber.glb"):
		return false
	var model: Node3D = load("res://art/characters/climber.glb").instantiate()
	add_child(model)
	var found := model.find_children("*", "Skeleton3D", true, false)
	skeleton = found[0] if found.size() > 0 else null
	if skeleton == null:
		model.queue_free()
		return false
	# 휴지 관절 위치는 관절 키로 명시한다(자식 뼈 열거 순서에 의존하지 않음, docs/04 §8.2)
	var rest_poses := {}
	var rest_joints := {}
	for entry in RigPose.BONES:
		var idx := skeleton.find_bone(entry[0])
		if idx >= 0:
			rest_poses[entry[0]] = skeleton.get_bone_global_rest(idx)
	for key in JOINT_BONE:
		if rest_poses.has(JOINT_BONE[key]):
			rest_joints[key] = (rest_poses[JOINT_BONE[key]] as Transform3D).origin
	rest_joints["head_top"] = rest_joints["head"] + Vector3(0, 0.14, 0)
	for s in ["L", "R"]:
		rest_joints["hand_" + s] = rest_joints["wrist_" + s] + (rest_joints["wrist_" + s] - rest_joints["elbow_" + s]).normalized() * 0.09
		rest_joints["toe_" + s] = rest_joints["ankle_" + s] + Vector3(0, -0.05, -0.15)
	rig.setup(rest_poses, rest_joints)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(i)
			var mname: String = m.resource_name if m else ""
			var c: Color = CHARACTER_COLORS.get(mname, (m as BaseMaterial3D).albedo_color if m is BaseMaterial3D else CLOTH_TEAL)
			var face := mname.begins_with("M_face")
			var toon := _toon(c, c.darkened(0.15 if face else 0.45))
			toon.next_pass.set_shader_parameter("width", 0.0 if face else 0.012)
			mi.set_surface_override_material(i, toon)
		if String(mi.name).begins_with("FX_face_"):
			face_meshes[String(mi.name).trim_prefix("FX_face_")] = mi
	_set_face("calm")
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


## 벽 접촉 평면(z = CONTACT_DEPTH)의 월드 좌표 → 화면 픽셀. 기술 UI의 홀드 강조·탭 변환용.
func world_to_screen(p: Vector2) -> Vector2:
	return camera.unproject_position(Vector3(p.x, p.y, CONTACT_DEPTH))


## 화면 픽셀 → 카메라 광선과 z = CONTACT_DEPTH 평면의 교점(벽 좌표).
func screen_to_wall(s: Vector2) -> Vector2:
	var o := camera.project_ray_origin(s)
	var n := camera.project_ray_normal(s)
	if absf(n.z) < 0.0001:
		return Vector2(o.x, o.y)
	var t := (CONTACT_DEPTH - o.z) / n.z
	return Vector2(o.x + n.x * t, o.y + n.y * t)


## 발 아래 작은 삼각형(꼭짓점 위). hollow=true이면 테두리만.
func _tri_mesh(hollow: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	var r := 0.07
	var pts := [Vector3(0, 0, 0), Vector3(-r, -r * 1.4, 0), Vector3(r, -r * 1.4, 0)]
	if hollow:
		st.begin(Mesh.PRIMITIVE_LINES)
		for i in 3:
			st.add_vertex(pts[i])
			st.add_vertex(pts[(i + 1) % 3])
	else:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in pts:
			st.add_vertex(p)
	return st.commit()


func _diamond_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	var r := 0.06
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(0, r, 0), Vector3(-r, 0, 0), Vector3(0, -r, 0), Vector3(0, r, 0), Vector3(0, -r, 0), Vector3(r, 0, 0)]:
		st.add_vertex(v)
	return st.commit()


func _update_foot_marks() -> void:
	for foot in foot_marks:
		var l: Dictionary = logic.session.limbs[foot]
		var attached: bool = l.state in ["Attached", "Armed"]
		var loaded: bool = logic.session.rules.loaded_feet.has(foot)
		var p: Vector2 = l.pos
		for m in foot_marks[foot]:
			m.position = Vector3(p.x, p.y - 0.09, Tuning.CONTACT_DEPTH)
		foot_marks[foot][0].visible = attached and loaded
		foot_marks[foot][1].visible = attached and not loaded
		var flag: bool = l.state == "Flag" or (l.state == "Dragging" and logic.session.rules.flag_ready.has(foot))
		flag_marks[foot].visible = flag
		flag_marks[foot].position = Vector3(p.x, p.y + 0.12, Tuning.CONTACT_DEPTH + 0.12 + (float(l.flag_depth) if l.state == "Flag" else 0.0))
