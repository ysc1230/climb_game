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
	logic.limb_chain_fn = limb_chain_screen
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

## 벽 판 반폭: 기본 1.55m, 가장 바깥 홀드보다 0.45m 넘게(홀드가 벽 판 밖·가장자리에 놓이지 않게, 2026-11-18).
static func wall_half_width(slots: Dictionary) -> float:
	var w := 1.55
	for key in slots:
		w = maxf(w, absf((slots[key].pos as Vector2).x) + 0.45)
	return w


## 벽 위 장식 볼륨 자리 [x, y, 크기]. 벽 가장자리(바깥 0.35m 안)에 두되 어떤 홀드와도 겹치지 않게
## (중심 거리 ≥ 장식 크기 + 0.35m) 고른다. 자리가 없으면 그 장식은 뺀다(2026-11-18 사용자: "홀드가 아닌 것은 벽 밖에
## 두거나 홀드와 절대 겹치지 않게").
static func deco_spots(slots: Dictionary, half_w: float, top: float, r: RandomNumberGenerator, count := 5) -> Array:
	var out := []
	for k in count:
		var size := r.randf_range(0.25, 0.45)
		for attempt in 20:
			var p := Vector2((1 if k % 2 == 0 else -1) * r.randf_range(half_w - 0.35, half_w - 0.1), r.randf_range(0.5, top - 1.5))
			var clear := true
			for key in slots:
				if p.distance_to(slots[key].pos) < size * 0.8 + 0.35:
					clear = false
					break
			if clear:
				out.append([p.x, p.y, size])
				break
	return out


func _build_wall() -> void:
	var top: float = logic.route.slots.values().reduce(func(a, s): return maxf(a, s.pos.y), 0.0) + 2.5
	var half_w := wall_half_width(logic.route.slots)
	# 활성 등반 평면: 슬롯이 놓이는 큰 판(살짝 기울어진 패널로 나눔). 모든 홀드가 판 안에 들어가게 넓힌다
	var y := -0.6
	var i := 0
	while y < top:
		var h := rng.randf_range(0.9, 1.4)
		for col in [-1, 1]:
			var panel := _mesh(_box(Vector3(half_w, h, 0.08)), _toon(WALL_CLAY.lerp(WALL_SAND, rng.randf() * 0.5), WALL_OLIVE, true), true)
			panel.position = Vector3(col * half_w * 0.5, y + h * 0.5, -0.06 - rng.randf() * 0.03)
			panel.rotation_degrees = Vector3(rng.randf_range(-2, 2), rng.randf_range(-3, 3) * col, 0)
			add_child(panel)
		y += h
		i += 1
	# 바닥 매트(윗면 y = MAT_TOP_Y, 낙하 인형이 같은 값을 쓴다)
	var mat := _mesh(_box(Vector3(9.0, 0.25, 4.0)), _toon(Color("4a5a55"), Color("2c3532")), true)
	mat.position = Vector3(0, MAT_TOP_Y - 0.125, 1.6)
	add_child(mat)
	# 좌우 비활성 볼륨: 각진 다면체와 측면 벽(공간감, 판정 없음). 벽 판 바깥에 둔다
	for side in [-1, 1]:
		var wing := _mesh(_box(Vector3(2.4, top + 1.0, 0.2)), _toon(WALL_SAND.darkened(0.08), WALL_OLIVE, true), true)
		wing.position = Vector3(side * (half_w + 1.2), (top - 1.0) * 0.5, 0.35)
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
	# 활성 벽 위의 장식 볼륨(접점 없는 돌출): 가장자리에, 홀드와 겹치지 않는 자리에만
	for d in deco_spots(logic.route.slots, half_w, top, rng):
		var sz: float = d[2]
		var deco := _mesh(_prism(Vector3(sz, sz * 1.4, sz * 0.5)), _toon(WALL_SAND, WALL_OLIVE), true)
		deco.position = Vector3(d[0], d[1], 0.05)
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
## 종류별 메시 변형(작업 4 §4.2, tools/holds/make_holds.py v3). 같은 종류 안에서는 키 해시로 고정된 무작위.
const TYPE_VARIANTS := {
	"jug": ["jug_0", "jug_1", "jug_2"], "crimp": ["crimp_0", "crimp_1", "crimp_2"], "sloper": ["sloper_0", "sloper_1"],
	"pinch": ["pinch_0", "pinch_1"], "pocket": ["pocket_0", "pocket_1"], "foot_chip": ["foot_chip_0", "foot_chip_1", "foot_chip_2"],
	"foot_big": ["foot_big_0", "foot_big_1"], "goal": ["goal_0"],
}
## 옛 형식 슬롯(종류 없음, 시험 루트): 손홀드 반폭으로 종류를 짐작한다(v8 크기 등급).
const LEGACY_HAND := [[0.05, "crimp"], [0.08, "pinch"], [INF, "jug"]]
var _hold_mesh_cache := {}


func _hold_mesh(name: String) -> Mesh:
	if _hold_mesh_cache.is_empty():
		var root := HOLD_MESHES.instantiate()
		for n in root.find_children("*", "MeshInstance3D", true, false):
			_hold_mesh_cache[String(n.name)] = (n as MeshInstance3D).mesh
		root.free()
	return _hold_mesh_cache.get(name)


## 슬롯에 놓을 홀드 메시 이름: 종류의 변형 중 키 해시로 고른다. 옛 형식은 반폭으로 종류를 짐작.
static func hold_variant(key: String, slot: Dictionary, is_goal: bool) -> String:
	var h := absi(hash(key))
	var type := str(slot.get("hold_type", ""))
	if is_goal:
		type = "goal"
	elif type == "":
		type = "foot_chip"
		if slot.has("hand_area"):
			for c in LEGACY_HAND:
				if float(slot.hand_area.half_width) < float(c[0]):
					type = c[1]
					break
	var list: Array = TYPE_VARIANTS[type]
	return list[h % list.size()]


## 메시 면의 역할: 0 몸체, 1 윗날, 2 어두운 면(볼트·저그 속·포켓 구멍). glTF는 안 쓴 재질 칸을 빼므로 순서가 아니라
## 재질 이름(*_body, *_lip, bolt)으로 정한다.
static func surface_role(mesh: Mesh, si: int) -> int:
	var m := mesh.surface_get_material(si)
	var n := m.resource_name if m != null else ""
	if n.ends_with("_lip"):
		return 1
	if n == "bolt":
		return 2
	return 0


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
		var mats := [_toon(cols[0], cols[0].darkened(0.45)), _toon(cols[1], cols[1].darkened(0.35)), _toon(cols[0].darkened(0.62), INK)]
		for m in mats.slice(0, 2):
			m.set_shader_parameter("speckle", true)
		for si in mesh.get_surface_count():
			var m: ShaderMaterial = mats[surface_role(mesh, si)]
			m.next_pass.set_shader_parameter("width", 0.006)
			hold.set_surface_override_material(si, m)
		var p: Vector2 = slot.pos
		hold.position = Vector3(p.x, p.y, 0.0)
		var tilt := 0.0 if str(slot.get("hold_type", "")) != "" else deg_to_rad(rng.randf_range(-8, 8))  # 종류 홀드는 rot_deg 그대로
		hold.rotation = Vector3(0, 0, ang + tilt)
		hold.scale = Vector3.ONE * hold_view_scale(slot, mesh, is_goal) * rng.randf_range(0.95, 1.05)
		add_child(hold)
		climber_pose.surface_depth[key] = mesh.get_aabb().end.z * hold.scale.z  # 홀드 겉면(손발을 여기 얹는다)
		climber_pose.surface_top[key] = mesh.get_aabb().end.y * hold.scale.y  # 홀드 윗면(발끝을 여기 얹는다)
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
## 끄는 손발의 잡힐 자리 고리(흰색, 벽 면). 잡힐 후보가 있으면 후보 점에 붙는다.
var reach_rings := {}


func _update_reach_rings() -> void:
	for limb in logic.session.limbs:
		if not reach_rings.has(limb):
			var ring := _mesh(_torus(0.02, 0.003), _overlay(Color(1, 1, 1, 0.8)), false)
			ring.rotation_degrees = Vector3(90, 0, 0)
			add_child(ring)
			reach_rings[limb] = ring
		var l: Dictionary = logic.session.limbs[limb]
		var r: MeshInstance3D = reach_rings[limb]
		r.visible = l.state == "Dragging" and not logic.session.selecting
		if r.visible:
			var p := ReachMarker.ring_point(l)
			r.position = Vector3(p.x, p.y, CONTACT_DEPTH + 0.01)


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
	parts.head = _mesh(_sphere(0.11), _toon(Color("3b2e26"), INK), false)  # 뒷머리(더미 머리, docs/39)
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
	if _shake > 0.0:  # 높은 곳 착지 흔들림(0.4초쯤)
		var s := Time.get_ticks_msec() / 1000.0
		camera.position += Vector3(sin(s * 90.0), sin(s * 71.0 + 1.1), 0) * 0.03 * _shake
		_shake = maxf(_shake - delta * 2.5, 0.0)
	_spawn_puffs()
	var t := _fall_targets(delta)
	if skeleton:
		_pose_model(t, delta)
		_update_face()
	else:
		_pose_capsules(t)
	_update_hold_glow()
	_update_reach_rings()
	_update_foot_marks()


var climber_pose := ClimberPose.new()
const MAT_TOP_Y := -0.075
const WALL_Z := 0.02
## 물리 낙하 장면(FallSim, docs/superpowers/specs/2026-11-19-1-feel-design.md §1.2). logic.fall_request가 오면 시작.
var fall_sim: FallSim = null
var _fall_angle := 0.0
var _last_t := {}


## 낙하 장면이면 인형 점, 아니면 평소 목표. 장면이 끝나면 logic에 알린다.
func _fall_targets(delta: float) -> Dictionary:
	if not logic.fall_request.is_empty() and fall_sim == null and not _last_t.is_empty():
		var req: Dictionary = logic.fall_request
		var pins := {}
		for hand in req.hands:
			var s := "L" if hand == PoseSolver.LH else "R"
			var at := 0.0 if hand == req.first else FallSim.RELEASE_DELAY
			pins["hand_" + s] = at
			pins["wrist_" + s] = at
		fall_sim = FallSim.new()
		fall_sim.start(_last_t, req.vel, pins, MAT_TOP_Y, WALL_Z)
		logic.fall_request = {}
	if fall_sim != null:
		if logic.fall_skip:
			fall_sim.skip()
			logic.fall_skip = false
		fall_sim.step(minf(delta, 1.0 / 30.0))
		var imp := fall_sim.take_impact()
		if not imp.is_empty():
			_on_landing(imp)
		var t: Dictionary = fall_sim.points().duplicate()
		var up := ((t.chest as Vector3) - (t.pelvis as Vector3)).normalized()
		t["up"] = up
		_fall_angle = rad_to_deg(atan2(-up.x, up.y))
		# 카메라가 떨어지는 몸을 따라 내려가 매트가 보이게
		var want := maxf((t.pelvis as Vector3).y + 0.12 * logic.PLAY_H, 1.4)
		logic.cam_y = lerpf(logic.cam_y, want, 1.0 - exp(-6.0 * delta))
		if fall_sim.done():
			logic.on_fall_scene_done()
		if logic.session.halted != &"fall" and not logic.session.falling:
			fall_sim = null  # 다시 시작됨
		return t
	var t := _pose_targets(delta)
	_last_t = t
	return t


## 착지 순간: 쿵 소리·진동·팁(logic), 매트 눌림 자국·먼지, 높으면 화면 흔들림.
func _on_landing(imp: Dictionary) -> void:
	var kind: StringName = imp.kind
	var pos: Vector3 = imp.pos
	logic.on_landing(kind)
	_shake = {&"low": 0.0, &"mid": 0.4, &"high": 1.0}.get(kind, 0.0)
	var size: float = {&"low": 0.55, &"mid": 0.75, &"high": 0.95}.get(kind, 0.6)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.25), Color(0, 0, 0, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	var q := QuadMesh.new()
	q.size = Vector2(size, size * 0.8)
	var dent := MeshInstance3D.new()
	dent.mesh = q
	dent.material_override = mat
	dent.rotation = Vector3(-PI * 0.5, 0, 0)
	dent.position = Vector3(pos.x, MAT_TOP_Y + 0.003, pos.z + 0.15)
	add_child(dent)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color", Color(1, 1, 1, 0), 0.9).set_delay(0.25)
	tw.tween_callback(dent.queue_free)
	for dx in [-0.15, 0.15]:
		logic.puffs.append({"kind": &"dust", "pos": Vector2(pos.x + dx, MAT_TOP_Y + 0.05), "z": pos.z})


var _shake := 0.0


const TREMBLE_KEYS := ["pelvis", "spine", "chest", "neck", "head", "head_top", "shoulder_L", "shoulder_R", "hip_L", "hip_R"]


## 판정 상태 → 표현용 3D 관절 위치(ClimberPose, docs/04 §8).
## 떨어지기 직전(위험 경고 중)에는 몸통이 덜덜 떨린다(표현만, 남은 시간이 줄수록 세게).
func _pose_targets(delta: float) -> Dictionary:
	var t := climber_pose.compute(logic.session, delta)
	if logic.danger.danger:
		var s := Time.get_ticks_msec() / 1000.0
		var amp: float = 0.004 + 0.008 * (1.0 - float(logic.danger.frac))
		var off: Vector3 = Vector3(sin(s * 71.0), sin(s * 53.0 + 1.3), 0) * amp
		for key in TREMBLE_KEYS:
			if t.has(key):
				t[key] = (t[key] as Vector3) + off
	# 손 힘 경고 떨림(GripWarning, 표현만): 그 손의 팔꿈치 아래만 흔든다
	for hand in [PoseSolver.LH, PoseSolver.RH]:
		var tr := GripWarning.tremble(int(logic.grip_level[hand])) if logic.warnings else Vector2.ZERO
		if tr.x > 0.0:
			var s2 := Time.get_ticks_msec() / 1000.0
			var o := Vector3(sin(TAU * tr.y * s2), sin(TAU * tr.y * s2 * 1.31 + 0.7), 0) * tr.x
			var side := "L" if hand == PoseSolver.LH else "R"
			for key in ["wrist_" + side, "hand_" + side]:
				if t.has(key):
					t[key] = (t[key] as Vector3) + o
	return t


func _pose_capsules(t: Dictionary) -> void:
	var up: Vector3 = t.up
	_place_segment(parts.hips, t.pelvis + up * -0.02, t.pelvis + up * 0.12, 0.13)
	_place_segment(parts.torso, t.pelvis + up * 0.16, t.pelvis + up * 0.45, 0.15)
	parts.head.position = t.head + up * 0.125 + Vector3(0, 0, 0.02)  # 더미 머리 가운데(목 위 0.125)
	parts.pack.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(logic.session.body.angle)), t.pelvis + up * 0.42 + Vector3(0, 0, 0.17))
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
	var free_feet := {"L": ClimberPose._free(logic.session, &"LF"), "R": ClimberPose._free(logic.session, &"RF")}
	var frames := rig.solve(local, _fall_angle if fall_sim != null else logic.session.body.angle, logic.session.body.yaw, free_feet)
	_apply_look(frames, inv, delta)
	_grip_hands(frames, delta)
	for name in RigPose.bone_names():
		var idx := skeleton.find_bone(name)
		if idx >= 0 and frames.has(name):
			skeleton.set_bone_global_pose(idx, frames[name])
	_curl_fingers(frames, delta)


## 손가락 말아 쥐기(docs/36, 2026-11-13 사용자: "홀드를 잡고 있으면 손가락을 구부리는 모션으로"):
## 홀드를 잡은 손(Attached·Armed)은 아래팔·손을 길이축으로 돌려 손바닥(휴지 T자에서 아래)이 벽을 보게 하고(_grip_hands),
## 손 뼈(손가락 첫 마디)와 손가락 뼈(끝 마디)를 손바닥 쪽으로 접는다(_curl_fingers). 떼면 펴진다(1/s 8로 부드럽게).
## 손가락 뼈(finger_L/R)가 없는 모델이면 아무것도 하지 않는다.
const CURL_HAND_DEG := 60.0   # 손 뼈를 손바닥 쪽으로 접는 각(손가락 첫 마디)
const CURL_FINGER_DEG := 75.0 # 손가락 뼈를 더 접는 각(끝 마디, 손 뼈 기준)
const CURL_SPEED := 8.0       # 1/s
const PALM_REST := Vector3.DOWN  # 휴지 T자 손바닥 방향
var finger_rest := {}         # "L"/"R" -> {idx, hand_idx, rest(손 기준 손가락 휴지 Transform), len}
var curl := {"L": 0.0, "R": 0.0}


## 잡은 정도(0~1)를 갱신하고, 잡은 손은 아래팔·손을 손바닥이 벽(−Z)을 보게 돌린다(잡은 정도만큼).
func _grip_hands(frames: Dictionary, delta: float) -> void:
	for s in ["L", "R"]:
		var l: Dictionary = logic.session.limbs[StringName(s + "H")]
		var want := 1.0 if l.state in ["Attached", "Armed"] else 0.0
		curl[s] = move_toward(curl[s], want, CURL_SPEED * delta)
		if curl[s] <= 0.001:
			continue
		for name in ["forearm_" + s, "hand_" + s]:
			if not frames.has(name) or not rig.rest_basis.has(name):
				continue
			var f: Transform3D = frames[name]
			var dir: Vector3 = (f.basis * rig.rest_basis[name].inverse() * rig.rest_dir[name]).normalized()
			frames[name] = Transform3D(rig._twist(f.basis, name, dir, PALM_REST, Vector3.FORWARD, curl[s]), f.origin)


func _curl_fingers(frames: Dictionary, _delta: float) -> void:
	for s in finger_rest:
		var hand_key: String = "hand_" + s
		if not frames.has(hand_key):
			continue
		var fr: Dictionary = finger_rest[s]
		var hand: Transform3D = frames[hand_key]
		var dir: Vector3 = (hand.basis * fr.hand_axis).normalized()
		var palm: Vector3 = (hand.basis * rig.rest_basis[hand_key].inverse() * PALM_REST).normalized()
		var axis := dir.cross(palm)
		if axis.length() > 0.05 and curl[s] > 0.001:
			var q := Basis(axis.normalized(), deg_to_rad(CURL_HAND_DEG) * curl[s])
			hand = Transform3D(q * hand.basis, hand.origin)
			skeleton.set_bone_global_pose(fr.hand_idx, hand)
			var finger: Transform3D = hand * fr.rest
			var fq := Basis(axis.normalized(), deg_to_rad(CURL_FINGER_DEG) * curl[s])
			skeleton.set_bone_global_pose(fr.idx, Transform3D(fq * finger.basis, finger.origin))
		else:
			skeleton.set_bone_global_pose(fr.idx, hand * fr.rest)


const LOOK_MAX_DEG := 80.0   # 머리를 돌리는 최대 각
const LOOK_BACK_DEG := 125.0 # 정상·추락 때 어깨 너머로 돌아보는 각
const LOOK_SPEED := 6.0      # 1/s, 목표 방향으로 따라가는 빠르기
var face_meshes := {}        # 표정 이름 -> MeshInstance3D(FX_face_*)
var face_now := ""
var _look := Quaternion.IDENTITY


## 표정(표현 전용): 떨어지는 중·떨어지기 직전(위험 경고) 놀람, 정상을 잡으면 기쁨,
## 팔 힘이 45 아래이거나 자세가 무너지는 중이면 힘씀, 그 밖에는 평온.
static func expression_for(falling: bool, at_goal: bool, min_stamina: float, rebalancing: bool, danger := false) -> String:
	if falling or (danger and not at_goal):
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
	_set_face(expression_for(s.falling, s.goal_ticks > 0, low, s.rules.phase == ClimbRules.Phase.REBALANCING, logic.danger.danger))


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
	if face_now == "happy" or logic.session.falling:
		# 정상을 잡았을 때·떨어질 때는(떨어지기 직전 경고 중에는 돌아보지 않는다 — 벽을 보고 버텨야 함) 어깨 너머로 카메라 쪽을 돌아본다(표정이 보이는 순간).
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


## 캐릭터 모델: data/characters.json에서 저장된 외형의 몸(남성·여성) 모델을 쓴다(docs/37 §7).
## 모델이 없거나 뼈대가 맞지 않으면 캡슐 인형. 2026-11-13 옛 CH02·모듈 시제품은 지웠다.
func _build_model() -> bool:
	var asm := CharacterAssembler.load_catalog()
	var g := get_node_or_null("/root/Game")
	var look: Dictionary = asm.normalize(g.progress.look if g != null else {})
	var path := asm.model_path(str(look.body))
	LimbIK.reset_leg_shape()
	if path == "" or not ResourceLoader.exists(path):
		return false
	var model: Node3D = load(path).instantiate()
	add_child(model)
	asm.apply(model, look)
	var found := model.find_children("*", "Skeleton3D", true, false)
	skeleton = found[0] if found.size() > 0 else null
	if skeleton == null or not CharacterAssembler.compatible(skeleton):
		skeleton = null  # 뼈 길이가 지금 몸과 다르면 캡슐 인형(2026-11-11 B안)
		model.queue_free()
		return false
	var leg := CharacterAssembler.leg_shape(skeleton)  # 화면 다리 관절·길이는 모델마다(docs/37 §7)
	LimbIK.set_leg_shape(float(leg.raise), float(leg.upper), float(leg.lower))
	# 휴지 관절 위치는 관절 키로 명시한다(자식 뼈 열거 순서에 의존하지 않음, docs/04 §8.2)
	var rest_poses := {}
	var rest_joints := {}
	for name in RigPose.bone_names():
		var idx := skeleton.find_bone(name)
		if idx >= 0:
			rest_poses[name] = skeleton.get_bone_global_rest(idx)
	for key in JOINT_BONE:
		if rest_poses.has(JOINT_BONE[key]):
			rest_joints[key] = (rest_poses[JOINT_BONE[key]] as Transform3D).origin
	rest_joints["head_top"] = rest_joints["head"] + Vector3(0, 0.14, 0)
	for s in ["L", "R"]:
		rest_joints["hand_" + s] = rest_joints["wrist_" + s] + (rest_joints["wrist_" + s] - rest_joints["elbow_" + s]).normalized() * Anatomy.HAND_LENGTH
		rest_joints["toe_" + s] = rest_joints["ankle_" + s] + Vector3(0, -0.05, -0.15)
	rig.setup(rest_poses, rest_joints)
	finger_rest.clear()
	for s in ["L", "R"]:
		var fi := skeleton.find_bone("finger_" + s)
		var hi := skeleton.find_bone("hand_" + s)
		if fi >= 0 and hi >= 0:
			var hr := skeleton.get_bone_global_rest(hi)
			var frt := skeleton.get_bone_global_rest(fi)
			finger_rest[s] = {"idx": fi, "hand_idx": hi, "rest": hr.affine_inverse() * frt,
				"hand_axis": hr.basis.inverse() * (frt.origin - hr.origin).normalized()}
	CharacterAssembler.style(model, toon_shader, outline_shader, INK)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
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


## 팔다리 뼈대의 화면 점(팔: 어깨·팔꿈치·손목, 다리: 엉덩이·무릎·발목). 2D 겹쳐 그리기용(docs/49 팔다리 힘 분포).
const LIMB_CHAINS := {&"LH": ["upperarm_L", "forearm_L", "hand_L"], &"RH": ["upperarm_R", "forearm_R", "hand_R"],
	&"LF": ["thigh_L", "shin_L", "foot_L"], &"RF": ["thigh_R", "shin_R", "foot_R"]}


func limb_chain_screen(limb: StringName) -> PackedVector2Array:
	var out := PackedVector2Array()
	if skeleton == null or camera == null:
		return out
	for b in LIMB_CHAINS[limb]:
		var i := skeleton.find_bone(b)
		if i < 0:
			return PackedVector2Array()
		out.append(camera.unproject_position((skeleton.global_transform * skeleton.get_bone_global_pose(i)).origin))
	return out


## 잡을 때 초크 가루·발 먼지(표현만, docs/superpowers/specs/2026-11-19-1-feel-design.md §1.4). logic.puffs를 가져가 비운다.
func _spawn_puffs() -> void:
	for p in logic.puffs:
		var kind: StringName = p.kind
		var e := CPUParticles3D.new()
		e.one_shot = true
		e.emitting = false
		e.amount = {&"chalk": 12, &"chalk_small": 6, &"dust": 6}.get(kind, 8)
		e.lifetime = 0.4
		e.explosiveness = 0.95
		e.direction = Vector3(0, 0.3, 1)
		e.spread = 70.0
		e.initial_velocity_min = 0.15
		e.initial_velocity_max = 0.45
		e.gravity = Vector3(0, -0.6, 0)
		e.scale_amount_min = 0.6
		e.scale_amount_max = 1.2
		var m := SphereMesh.new()
		m.radius = 0.008
		m.height = 0.016
		e.mesh = m
		var col := Color(1, 1, 1, 0.85) if kind != &"dust" else Color(0.72, 0.66, 0.6, 0.7)
		var pm := _unshaded(col)
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		e.material_override = pm
		e.position = Vector3((p.pos as Vector2).x, (p.pos as Vector2).y, float(p.get("z", CONTACT_DEPTH + 0.06)))
		add_child(e)
		e.emitting = true
		get_tree().create_timer(1.0).timeout.connect(e.queue_free)
	logic.puffs.clear()
