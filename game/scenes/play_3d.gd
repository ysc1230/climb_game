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
## 벽·홀드·표시·캐릭터 묶음. 2026-11-24 꺾이는 벽(docs/57)부터는 통째로 기울이지 않고 각자를 접힌 벽(fold) 위에 놓는다:
## 판정 벽 좌표(x, s = 벽면을 따라 잰 높이, z) → fold.point(월드). 구간이 하나면 예전 회전(X축 θ)과 같다.
## 매트·조명·카메라·낙하 장면은 월드 좌표.
var wall_root := Node3D.new()
var fold: WallProfile
## 캐릭터 틀: 골반 높이의 벽면 틀(fold.frame). 관절은 하나씩 접어 이 틀 좌표로 옮긴다(꺾이는 곳에 걸치면 몸이 벽을 따라 굽음).
var char_root := Node3D.new()
var _char_s := 0.0  # 캐릭터 틀을 잡은 벽면 높이(낙하 장면 동안은 시작 때 값)


func _ready() -> void:
	rng.seed = 1230
	logic = $UI/PlayTest
	logic.draw_world = false
	logic.w2s_fn = world_to_screen
	logic.limb_chain_fn = limb_chain_screen
	logic.s2w_fn = screen_to_wall
	fold = WallProfile.new(logic.route, -1.5, _wall_top() + 3.0)
	add_child(wall_root)
	wall_root.add_child(char_root)
	_build_environment()
	_build_wall()
	_build_holds()
	if not _build_model():
		_build_character()
	# 발 하중 표시(docs/25): 채운 삼각형 = Loaded, 빈 삼각형 = Attached·Unloaded
	for foot in [&"LF", &"RF"]:
		var filled := _mesh(_tri_mesh(false), _overlay(TARGET_CREAM), false)
		var hollow := _mesh(_tri_mesh(true), _overlay(TARGET_CREAM), false)
		wall_root.add_child(filled)
		wall_root.add_child(hollow)
		foot_marks[foot] = [filled, hollow]
		var diamond := _mesh(_diamond_mesh(), _overlay(Color("a8d8d0")), false)
		wall_root.add_child(diamond)
		flag_marks[foot] = diamond


# ---------- 접힌 벽 위에 놓기(docs/57) ----------

## 벽 판 위끝(가장 높은 슬롯 + 2.5m).
func _wall_top() -> float:
	return logic.route.slots.values().reduce(func(a, s): return maxf(a, s.pos.y), 0.0) + 2.5


## 판정 벽 좌표의 틀(위치 t.origin, 벽 틀 기준 회전 t.basis)을 접힌 벽 위 월드 틀로.
func _wall_xform(t: Transform3D) -> Transform3D:
	return Transform3D(fold.basis_at(t.origin.y) * t.basis, fold.point(t.origin))


## node를 판정 벽 좌표 p(벽 틀 기준 회전 b)에 놓는다.
func _on_wall(node: Node3D, p: Vector3, b := Basis()) -> void:
	node.transform = _wall_xform(Transform3D(b, p))


## 접힌 띠 메시: 벽면 높이 from_s~to_s를 따라 (펼친 좌표의) 두 점 a(x, z)·b(x, z) 사이를 잇는다. UV = (가로 거리, s)로 합판 무늬.
## 꺾이는 곳(각도가 변하는 구간)만 5cm마다 나누고 곧은 곳은 STRIP_FLAT m마다(100m 벽이 5cm마다면 띠 하나 2100칸, 2026-11-26 최적화).
func _fold_strip(a: Vector2, b: Vector2, from_s: float, to_s: float, fine := STRIP_FINE) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := strip_rows(fold, from_s, to_s, fine)
	var w := a.distance_to(b)
	for i in rows.size() - 1:
		var sa: float = rows[i]
		var sb: float = rows[i + 1]
		var q := [fold.point(Vector3(a.x, sa, a.y)), fold.point(Vector3(b.x, sa, b.y)), fold.point(Vector3(b.x, sb, b.y)), fold.point(Vector3(a.x, sb, a.y))]
		var uv := [Vector2(a.x, sa), Vector2(a.x + w, sa), Vector2(a.x + w, sb), Vector2(a.x, sb)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[k])
			st.add_vertex(q[k])
	st.generate_normals()
	if logic.route.wall_style == "rock":
		st.generate_tangents()  # 바위 셰이더가 법선을 흔들 때만 쓴다
	return st.commit()


const STRIP_FINE := 0.05   # 꺾이는 곳의 띠 칸 높이(m)
const STRIP_FLAT := 4.0    # 곧은 곳의 띠 칸 최대 높이(m)


## 띠를 나눌 벽면 높이들: 각도가 변하는 칸은 STRIP_FINE마다, 곧은 곳은 STRIP_FLAT까지 한 칸.
static func strip_rows(f: WallProfile, from_s: float, to_s: float, fine := STRIP_FINE) -> PackedFloat32Array:
	var n := maxi(2, int(ceil((to_s - from_s) / fine)))
	var rows := PackedFloat32Array([from_s])
	var prev_s := from_s
	var prev_a := f.angle_rad(from_s)
	for i in range(1, n + 1):
		var s := from_s + (to_s - from_s) * i / n
		var a := f.angle_rad(s)
		var bend := absf(a - prev_a) > 1e-5
		if bend and rows[rows.size() - 1] < prev_s - 1e-6:
			rows.append(prev_s)  # 곧은 곳이 끝나고 꺾이기 시작하는 자리
		if bend or i == n or s - rows[rows.size() - 1] >= STRIP_FLAT - 1e-6:
			rows.append(s)
		prev_s = s
		prev_a = a
	return rows


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

## 해 그림자 진하기(0 = 없음, 1 = Godot 기본). 홀드가 다른 홀드 그림자에 묻히지 않을 만큼 연하게.
const SHADOW_OPACITY := 0.22

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _style().bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("7a5c50")
	env.ambient_light_energy = 0.65
	env.fog_enabled = true
	env.fog_light_color = _style().fog
	env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("f0d6c2")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	# 2026-11-23 사용자 "홀드가 안 보여, 그림자를 엄청 연하게": 홀드·볼륨·몸 그림자가 벽의 다른 홀드를 덮었다.
	# 빛 세기는 그대로(세게 하면 캐릭터 색이 바뀜) 두고 그림자 진하기만 낮춘다.
	sun.shadow_opacity = SHADOW_OPACITY
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


const WALL_PLY := Color("c27a52")   # 합판 판넬(참고 그림의 주황 합판, 0.20까지)
const VOLUME_SAND := Color("d2b07a")  # 볼륨(모래·황토색, 0.20까지)
## 벽 꾸밈(2026-11-25 사용자 "벽이 너무 예쁘지 않아" → 설계자 추천 실내 암장): 문제 JSON wall_style.
## gym = 차분한 남회색 판넬(색 홀드가 눈에 띔), rock = 자연 암벽(바위 셰이더, 하늘·땅 배경, 바위색 홀드에 초크).
## 캐릭터 색이 바뀌지 않게 주변광·해는 그대로 두고 벽·배경·안개만 바꾼다.
const STYLES := {
	"gym": {"wall": Color("5f6975"), "wall_shade": Color("2c323b"), "wing": Color("49515c"), "wing_shade": Color("262b33"),
		"volumes": [Color("3f444c"), Color("5f7790"), Color("4b5566")], "bolt": Color("15181c"), "room": Color("2a2e34"),
		"bg": Color("23272d"), "fog": Color("8a9098"),
		"mat": Color("3d4f6e"), "floor": Color("33373d"), "trim": Color("1f2226"), "neighbors": true},
	"rock": {"wall": Color("847f7a"), "wall_shade": Color("47433f"), "wing": Color("726d68"), "wing_shade": Color("3a3632"),
		"volumes": [Color("847f7a")], "bolt": Color("15181c"), "room": Color("9cc0e2"), "mat": Color("3d4f6e"),
		"bg": Color("9cc0e2"), "fog": Color("b8cde0"), "ground": Color("6b6152")},
}
## 자연 암벽 홀드: 바위색 몸 + 초크 묻은 윗날. 정상은 그대로 금색.
const ROCK_HOLDS := {"hand": [Color("8a7f74"), Color("f2efe9")], "match": [Color("7d8592"), Color("dfe8f5")], "foot": [Color("6e655c"), Color("cfc7bd")]}


func _style() -> Dictionary:
	return STYLES.get(logic.route.wall_style, STYLES.gym)


## 벽 재질: 실내는 합판 무늬(판넬·볼트), 자연 암벽은 바위 무늬.
func _wall_mat(col: Color, shade_col: Color) -> ShaderMaterial:
	var rock: bool = logic.route.wall_style == "rock"
	var m := _toon(col, shade_col, not rock)
	m.set_shader_parameter("wall_uv", true)
	m.set_shader_parameter("rock_pattern", rock)
	m.set_shader_parameter("bolt_color", _style().bolt)
	return m
const MAT_GRAY := Color("6b6f72")


func _build_wall() -> void:
	var top := _wall_top()
	var half_w := wall_half_width(logic.route.slots)
	# 활성 등반 면: 접힌 띠 한 장(구간마다 각도, docs/57). 합판 판넬·이음선·볼트 구멍은 셰이더가 벽면 좌표(UV)로 그린다(작업 4 §4.3)
	var st: Dictionary = _style()
	var wall_m := _wall_mat(st.wall, st.wall_shade)
	# 앞면이 카메라 쪽(Godot 앞면 = 시계 방향 감김)이 되게 오른쪽 → 왼쪽으로 잇는다
	var wall := _mesh(_fold_strip(Vector2(half_w, -0.02), Vector2(-half_w, -0.02), -0.6, top), wall_m, true)
	wall_root.add_child(wall)
	# 바닥 매트(윗면 y = MAT_TOP_Y, 낙하 인형이 같은 값을 쓴다): 1m 이음선. 2026-11-25 사용자 "벽·주변 사물 개선":
	# 벽과 같은 회갈색이라 바닥과 벽이 갈리지 않아 남색 크래시 패드로(실내 암장 흔한 색, 홀드 색과 겹치지 않음)
	var mat_col: Color = st.get("mat", MAT_GRAY)
	var mat_m := _toon(mat_col, mat_col.darkened(0.45))
	mat_m.set_shader_parameter("mat_pattern", true)
	var mat := _mesh(_box(Vector3(9.0, 0.25, 4.0)), mat_m, true)
	mat.position = Vector3(0, MAT_TOP_Y - 0.125, 1.6)
	add_child(mat)
	# 암장 실내(안쪽 면만 보이는 큰 상자): 시점을 돌리거나 확대해도 매트 끝 밖·벽 뒤의 빈 공간이 보이지 않게(2026-11-24 사용자)
	var room_m := _toon(st.room, st.room.darkened(0.35))
	room_m.next_pass = null  # 외곽선 껍데기는 안쪽 면 상자에 맞지 않는다
	# 높은 벽(만들기 화면 100m까지, 2026-11-25)은 방이 벽 끝·앞으로 나온 천장 끝까지 덮게 키운다(작으면 방 천장이 벽을 가림)
	var tip := fold.point(Vector3(0, top, 0))
	var room_h := maxf(14.0, tip.y + 6.0)
	var box := _box(Vector3(26.0, room_h, maxf(26.0, 2.0 * (tip.z + 10.0 - 1.0))))
	box.flip_faces = true
	var room := _mesh(box, room_m, false)
	room.position = Vector3(0, MAT_TOP_Y - 0.25 + room_h * 0.5, 1.0)
	add_child(room)
	if st.has("floor"):  # 실내: 매트 밖은 어두운 고무 바닥(벽·매트와 갈리게)
		var fm := _toon(st.floor, st.floor.darkened(0.4))
		fm.next_pass = null
		var floor_mesh := _mesh(_box(Vector3(25.8, 0.02, 25.8)), fm, false)
		floor_mesh.position = Vector3(0, MAT_TOP_Y - 0.24, 1.0)
		add_child(floor_mesh)
	if st.has("trim"):  # 벽 위 끝 마감(어두운 덮개): 벽이 허공에서 끊겨 보이지 않게
		var tm := _toon(st.trim, st.trim)
		var cap := _mesh(_box(Vector3(2.0 * half_w, 0.08, 0.14)), tm, true)
		_on_wall(cap, Vector3(0, top - 0.04, 0.05))
		wall_root.add_child(cap)
	if st.get("neighbors", false):
		_add_neighbor_walls(half_w, top)
	if st.has("ground"):  # 자연 암벽: 하늘색 상자 바닥에 흙 땅
		var gm := _toon(st.ground, st.ground.darkened(0.4))
		gm.next_pass = null
		var ground := _mesh(_box(Vector3(25.8, 0.02, 25.8)), gm, false)
		ground.position = Vector3(0, MAT_TOP_Y - 0.24, 1.0)
		add_child(ground)
	# 옆벽: 같은 합판 톤을 어둡게, 화면 밖으로 빠지게(판정 없음). 벽 가장자리에서 앞으로 38° 벌어진 띠, 벽과 같이 접힘
	for side in [-1, 1]:
		var wm := _wall_mat(st.wing, st.wing_shade)
		wm.set_shader_parameter("rock_bump", 0.0)
		var inner := Vector2(side * half_w, -0.02)
		var outer := inner + Vector2(side * 2.4 * cos(deg_to_rad(38.0)), 2.4 * sin(deg_to_rad(38.0)))
		var wing := _mesh(_fold_strip(inner if side < 0 else outer, outer if side < 0 else inner, -1.0, top + 0.5, 0.15), wm, true)  # 장식이라 꺾임을 성기게
		wall_root.add_child(wing)
		_wings.append(wing)
	# 만든 문제의 볼륨(2026-11-28): 잡고 딛는 덩어리. 장식 볼륨과 달리 벽 안에 놓인다
	volume_nodes.clear()
	for v in logic.route.volumes:
		_add_route_volume(v)
	# 볼륨: 벽에 붙은 삼각기둥·상자(볼트). 벽 가장자리, 홀드와 겹치지 않는 자리에만(deco_spots)
	var k := 0
	if logic.route.wall_style == "rock":
		return  # 자연 암벽에는 볼륨(인공 덩어리)이 없다
	for d in deco_spots(logic.route.slots, half_w, top, rng):
		_add_volume(Vector2(d[0], d[1]), d[2], k % 2 == 0)
		k += 1


## 벽에 붙은 볼륨 하나. tri: 삼각기둥(세로 능선이 벽에서 튀어나옴), 아니면 납작한 상자. 겉면에 볼트 머리 몇 개.
func _add_volume(p: Vector2, size: float, tri: bool) -> void:
	var vols: Array = _style().volumes
	var vc: Color = vols[rng.randi() % vols.size()]
	var m := _toon(vc.darkened(rng.randf() * 0.12), vc.darkened(0.5))  # 홀드보다 먼저 눈에 띄지 않게
	m.set_shader_parameter("speckle", logic.route.wall_style != "rock")
	m.set_shader_parameter("rock_pattern", logic.route.wall_style == "rock")
	var out := size * (0.7 if tri else 0.45)
	var v: MeshInstance3D
	if tri:
		# 가로 능선: 윗빗면은 밝고 아랫빗면은 그늘(주광이 위에서) — 정면 카메라에서도 입체로 읽힌다
		v = _mesh(_prism(Vector3(size, out, size * 1.5)), m, true)
		_on_wall(v, Vector3(p.x, p.y, -0.02 + out * 0.5), Basis(Vector3(0, 0, 1), PI / 2.0 + deg_to_rad(rng.randf_range(-10, 10))) * Basis(Vector3(1, 0, 0), PI / 2.0))
	else:
		# 네모뿔(밑면이 벽에 붙음): 납작한 밝은 상자에 볼트 점 셋은 "…" 이름표처럼 보였다(2026-11-25 사용자 "주변 사물 개선")
		var pyr := CylinderMesh.new()
		pyr.radial_segments = 4
		pyr.rings = 1
		pyr.bottom_radius = size * 0.7
		pyr.top_radius = size * 0.08
		pyr.height = out * 0.7
		v = _mesh(pyr, m, true)
		_on_wall(v, Vector3(p.x, p.y, -0.02 + out * 0.35), Basis(Vector3.BACK, deg_to_rad(rng.randf_range(0, 90))) * Basis(Vector3.RIGHT, PI / 2.0))
	wall_root.add_child(v)
	return  # 볼트 머리는 그리지 않는다: 점 셋이 "…" 이름표처럼 보였다(2026-11-25)
	var bolt_m := _toon(INK, INK)
	for i in 3:
		var b := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.012
		cyl.bottom_radius = 0.012
		cyl.height = 0.006
		cyl.radial_segments = 6
		b.mesh = cyl
		b.material_override = bolt_m
		var t := (float(i) - 1.0) * 0.35
		if tri:
			# 윗빗면 가운데 줄
			_on_wall(b, Vector3(p.x + t * size, p.y + size * 0.25, -0.02 + out * 0.5 + 0.004), Basis(Vector3.RIGHT, PI / 2.0))
		else:
			_on_wall(b, Vector3(p.x + t * size * 0.6, p.y + size * 0.2, -0.02 + out * 0.6 + 0.004), Basis(Vector3.RIGHT, PI / 2.0))
		wall_root.add_child(b)


## 이웃 벽(배경, 판정 없음): 옆벽 바깥에 다른 등반 벽 두 면. 시점을 넓히거나 돌려도 회색 빈 공간 대신 암장 안처럼 보인다.
## 홀드와 헷갈리지 않게 홀드는 두지 않고 어두운 판넬과 볼륨만. 벽 접기(wall_root)를 따르지 않는 월드 고정.
func _add_neighbor_walls(half_w: float, top: float) -> void:
	var st: Dictionary = _style()
	var h := maxf(top + 0.8, 4.5)
	for side in [-1, 1]:
		var m := _toon(st.wing.darkened(0.25), st.wing_shade.darkened(0.25), true)
		m.set_shader_parameter("bolt_color", st.bolt)
		var panel := _mesh(_box(Vector3(5.0, h, 0.2)), m, true)
		_neighbors.append([side, panel])
		var x: float = side * (half_w + 2.4 * cos(deg_to_rad(38.0)) + 2.3)
		panel.transform = Transform3D(Basis(Vector3.UP, -side * deg_to_rad(55.0)), Vector3(x, MAT_TOP_Y + h * 0.5 - 0.25, 2.6))
		add_child(panel)
		var vols: Array = st.volumes
		for i in 4:
			var pyr := CylinderMesh.new()
			pyr.radial_segments = 4 if i % 2 == 0 else 3
			pyr.rings = 1
			var size := rng.randf_range(0.35, 0.6)
			pyr.bottom_radius = size
			pyr.top_radius = size * 0.08
			pyr.height = size * 0.6
			var vc: Color = vols[(i + (1 if side > 0 else 0)) % vols.size()]
			var vm := _toon(vc.darkened(0.15), vc.darkened(0.55))
			var v := _mesh(pyr, vm, true)
			var local := Vector3(rng.randf_range(-1.8, 1.8), rng.randf_range(-h * 0.35, h * 0.35), 0.1 + size * 0.3)
			v.transform = Transform3D(Basis(Vector3.BACK, rng.randf() * PI) * Basis(Vector3.RIGHT, PI / 2.0), local)
			panel.add_child(v)  # 판넬과 같이 숨긴다


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
var hold_nodes := {}  # 슬롯 키 → [홀드 메시, 판정 벽 좌표 틀]: 만들기 화면이 끄는 홀드만 바로 옮겨 그린다
var build_glows := true  # 만들기 화면은 빛 메시를 쓰지 않는다(홀드 300개면 메시 300개 더)
var _hold_mats := {}     # 종류(hand·match·foot·goal, 암벽) → 면 역할별 재질 3개. 홀드마다 새로 만들지 않고 나눠 쓴다


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
	if is_goal and type in ["", "goal"]:  # 만든 문제의 탑은 고른 종류 모양(색은 탑 금색)
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
	if is_goal and str(slot.get("hold_type", "")) in ["", "goal"]:
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
		_add_hold(key)


# ---------- 볼륨(2026-11-28) ----------

var volume_nodes := {}  # 볼륨 id → MeshInstance3D(월드 좌표 메시)
## 홀드 쓰임 색(손 초록·발 보라·탑 금색)과 헷갈리지 않는 회청·모래색(2026-11-28: 보라 볼륨이 발 홀드처럼 보였다)
const VOLUME_COLORS := [Color("5f7790"), Color("7d8794"), Color("9a8466"), Color("6b7f99")]


func _add_route_volume(v: Dictionary) -> void:
	var vc: Color = VOLUME_COLORS[absi(hash(str(v.id))) % VOLUME_COLORS.size()]
	var m := _toon(vc, vc.darkened(0.5))
	m.set_shader_parameter("speckle", true)
	var node := _mesh(volume_mesh(fold, v), m, true)
	wall_root.add_child(node)
	volume_nodes[v.id] = node


## 볼륨 메시(월드 좌표): 바닥 네 모서리와 겉면 네 모서리(깊이 Volumes.depth_at)를 접힌 벽에 놓고 겉면·옆면을 잇는다.
## 면마다 바깥을 보도록 감는 방향을 맞춘다(삼각의 얇은 쪽처럼 넓이 없는 면은 뺀다).
static func volume_mesh(f: WallProfile, v: Dictionary) -> ArrayMesh:
	var c := Volumes.center(v)
	var h := Volumes.side(v) * 0.5
	var corners := [c + Vector2(-h, -h), c + Vector2(h, -h), c + Vector2(h, h), c + Vector2(-h, h)]
	var base: Array = corners.map(func(p): return f.point(Vector3(p.x, p.y, 0.0)))
	var top: Array = corners.map(func(p): return f.point(Vector3(p.x, p.y, Volumes.depth_at(v, p))))
	var mid := f.point(Vector3(c.x, c.y, Volumes.depth_at(v, c) * 0.5))
	var faces: Array = [top]
	for i in 4:
		faces.append([base[i], base[(i + 1) % 4], top[(i + 1) % 4], top[i]])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for poly in faces:
		var p0: Vector3 = poly[0]
		var n: Vector3 = ((poly[1] as Vector3) - p0).cross((poly[2] as Vector3) - p0)
		if n.length() < 1e-6:
			n = ((poly[2] as Vector3) - p0).cross((poly[3] as Vector3) - p0)
		if n.length() < 1e-6:
			continue  # 넓이 없는 면
		var cen: Vector3 = ((poly[0] as Vector3) + poly[1] + poly[2] + poly[3]) * 0.25
		var pts: Array = poly if n.dot(cen - mid) < 0.0 else [poly[3], poly[2], poly[1], poly[0]]  # Godot 앞면은 시계 방향
		for tri in [[0, 1, 2], [0, 2, 3]]:
			var a: Vector3 = pts[tri[0]]
			var b: Vector3 = pts[tri[1]]
			var d: Vector3 = pts[tri[2]]
			if (b - a).cross(d - a).length() < 1e-8:
				continue
			for q in [a, b, d]:
				st.add_vertex(q)
	st.generate_normals()
	return st.commit()


## 볼륨 면 칸(발 비비기): 메시 없이 면 위에 얇은 빛판, 발끝은 딛은 자리의 면 깊이(ClimberPose.face_volume).
func _add_volume_face(key: String) -> void:
	var vid := key.get_slice("/", 1)
	var v: Dictionary = {}
	for w in logic.route.volumes:
		if w.id == vid:
			v = w
	if v.is_empty():
		return
	var c := Volumes.center(v)
	var dz := Volumes.depth_at(v, c)
	var face := Basis(Quaternion(Vector3(0, 0, 1), Volumes.normal_at(v, c)))
	var node := Node3D.new()
	var t := Transform3D(face, Vector3(c.x, c.y, dz))
	_on_wall(node, t.origin, t.basis)
	wall_root.add_child(node)
	hold_nodes[key] = [node, t]
	climber_pose.surface_depth[key] = dz
	climber_pose.surface_top[key] = 0.0
	climber_pose.face_volume[key] = v
	if not build_glows:
		return
	var plate := BoxMesh.new()
	var sd := Volumes.side(v) * 0.9
	plate.size = Vector3(sd, sd, 0.01)
	var glow := MeshInstance3D.new()
	glow.mesh = plate
	var gm := _overlay(Color(1, 1, 1, 0.0))
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.material_override = gm
	_on_wall(glow, Vector3(c.x, c.y, dz + 0.01), face)
	glow.visible = false
	wall_root.add_child(glow)
	hold_glows[key] = glow


## 볼륨 모서리 칸: 홀드 메시 대신 모서리를 따라 빛나는 띠(잡을 수 있을 때·튜토리얼 목표)와 손발 깊이(모서리 깊이).
func _add_volume_edge(key: String) -> void:
	var slot: Dictionary = logic.route.slots[key]
	var vid := key.get_slice("/", 1)
	var sid := key.get_slice("/", 2)
	var v: Dictionary = {}
	for w in logic.route.volumes:
		if w.id == vid:
			v = w
	if v.is_empty():
		return
	var e: Dictionary = {}
	for x in Volumes.edges(v):
		if x.slot_id == sid:
			e = x
	if e.is_empty():
		return
	var p: Vector2 = slot.pos
	var along_x := sid in ["edge_t", "edge_b"]
	var node := Node3D.new()
	var t := Transform3D(Basis(), Vector3(p.x, p.y, float(e.depth)))
	_on_wall(node, t.origin)
	wall_root.add_child(node)
	hold_nodes[key] = [node, t]
	climber_pose.surface_depth[key] = float(e.depth)  # 손은 모서리 겉(앞면 깊이)을 감싼다
	climber_pose.surface_top[key] = 0.0              # 발끝은 모서리 위(윗면)에
	if not build_glows:
		return
	var bar := BoxMesh.new()
	var len := Volumes.side(v)
	bar.size = Vector3(len, 0.05, 0.05) if along_x else Vector3(0.05, len, 0.05)
	var glow := MeshInstance3D.new()
	glow.mesh = bar
	var gm := _overlay(Color(1, 1, 1, 0.0))
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.material_override = gm
	_on_wall(glow, Vector3(p.x, p.y, float(e.depth)))
	glow.visible = false
	wall_root.add_child(glow)
	hold_glows[key] = glow


## 홀드 하나(메시·재질·빛)를 벽에 놓는다.
func _add_hold(key: String) -> void:
	var slot: Dictionary = logic.route.slots[key]
	if slot.get("hold_type", &"") == &"volume":
		_add_volume_edge(key)
		return
	if slot.get("hold_type", &"") == &"volume_face":
		_add_volume_face(key)
		return
	var is_goal: bool = logic.route.goal_slots.has(key)
	var hand: bool = slot.has("hand_area")
	# 발 쓰임(칸 foot_1)은 손으로도 잡히지만(2026-11-26 모든 홀드는 손·발 홀드) 발 홀드 색으로
	var foot_kind := not hand or key.ends_with("/foot_1")
	var kind := "goal" if is_goal else ("foot" if foot_kind else ("match" if slot.hand_area.get("matchable", false) else "hand"))
	var variant := hold_variant(key, slot, is_goal)
	var mesh := _hold_mesh(variant)
	var ang: float = (slot.hand_area.dir as Vector2).angle() if hand else (slot.foot_area.up as Vector2).angle() - PI / 2.0
	var hold := MeshInstance3D.new()
	hold.mesh = mesh
	var mats := _hold_materials(kind)
	for si in mesh.get_surface_count():
		hold.set_surface_override_material(si, mats[surface_role(mesh, si)])
	var p: Vector2 = slot.pos
	var tilt := 0.0 if str(slot.get("hold_type", "")) != "" else deg_to_rad(rng.randf_range(-8, 8))  # 종류 홀드는 rot_deg 그대로
	var sc := hold_view_scale(slot, mesh, is_goal) * rng.randf_range(0.95, 1.05)
	# 볼륨 면에 놓인 홀드: 그 면 깊이에, 면 기울기대로 붙인다(2026-11-28)
	var vol := Volumes.at(logic.route.volumes, p)
	var mz := 0.0 if vol.is_empty() else Volumes.depth_at(vol, p)
	var face := Basis() if vol.is_empty() else Basis(Quaternion(Vector3(0, 0, 1), Volumes.normal_at(vol, p)))
	var hb := face * Basis(Vector3.BACK, ang + tilt)
	_on_wall(hold, Vector3(p.x, p.y, mz), hb.scaled(Vector3.ONE * sc))
	wall_root.add_child(hold)
	hold_nodes[key] = [hold, Transform3D(hb.scaled(Vector3.ONE * sc), Vector3(p.x, p.y, mz))]
	climber_pose.surface_depth[key] = mz + mesh.get_aabb().end.z * sc  # 홀드 겉면(손발을 여기 얹는다)
	climber_pose.surface_top[key] = mesh.get_aabb().end.y * sc  # 홀드 윗면(발끝을 여기 얹는다)
	if not build_glows:
		return
	var glow := MeshInstance3D.new()
	glow.mesh = mesh
	var gm := _overlay(Color(1, 1, 1, 0.0))
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.material_override = gm
	_on_wall(glow, Vector3(p.x, p.y, mz + 0.004), hb.scaled(Vector3.ONE * sc * 1.18))
	glow.visible = false
	wall_root.add_child(glow)
	hold_glows[key] = glow


## 종류별 홀드 재질 [몸체, 윗날, 어두운 면](surface_role 순서). 같은 종류 홀드가 나눠 쓴다.
func _hold_materials(kind: String) -> Array:
	var rock: bool = logic.route.wall_style == "rock" and ROCK_HOLDS.has(kind)
	var mk := kind + ("|rock" if rock else "")
	if not _hold_mats.has(mk):
		var cols: Array = ROCK_HOLDS[kind] if rock else HOLD_COLORS[kind]
		var mats := [_toon(cols[0], cols[0].darkened(0.45)), _toon(cols[1], cols[1].darkened(0.35)), _toon(cols[0].darkened(0.62), INK)]
		for i in 3:
			if i < 2:
				mats[i].set_shader_parameter("speckle", true)
			mats[i].next_pass.set_shader_parameter("width", 0.006)
		_hold_mats[mk] = mats
	return _hold_mats[mk]


## 홀드 빛: 끄는 손발 아래 지금 놓으면 잡히는 홀드(세션 후보)는 흰색으로 깜빡이며 빛나고,
## 튜토리얼 목표 홀드는 노란색으로 깜빡인다. 잡을 수 있는 쪽이 우선이다.
## 끄는 손발의 잡힐 자리 고리(흰색, 벽 면). 잡힐 후보가 있으면 후보 점에 붙는다.
var reach_rings := {}


func _update_reach_rings() -> void:
	for limb in logic.session.limbs:
		if not reach_rings.has(limb):
			var ring := _mesh(_torus(0.02, 0.003), _overlay(Color(1, 1, 1, 0.8)), false)
			wall_root.add_child(ring)
			reach_rings[limb] = ring
		var l: Dictionary = logic.session.limbs[limb]
		var r: MeshInstance3D = reach_rings[limb]
		r.visible = l.state == "Dragging" and not logic.session.selecting
		if r.visible:
			var gd := ReachMarker.grip_guide(logic.session, limb)  # 손: 잡을 자리 안내 색(초록·주황·빨강)
			(r.material_override as StandardMaterial3D).albedo_color = Color(ReachMarker.GUIDE_COLORS[gd.level], 0.95) if not gd.is_empty() else Color(1, 1, 1, 0.8)
			var p := ReachMarker.ring_point(l)
			_on_wall(r, Vector3(p.x, p.y, CONTACT_DEPTH + 0.01 + Volumes.depth_near(logic.route.volumes, p, 0.02)), Basis(Vector3.RIGHT, PI / 2.0))  # 볼륨 겉면 위에(2026-11-28: 볼륨 속에 숨었다)


func _update_hold_glow() -> void:
	var t := Time.get_ticks_msec() * 0.001
	var fast := 0.5 + 0.5 * sin(TAU * 2.2 * t)
	var slow := 0.5 + 0.5 * sin(TAU * 1.2 * t)
	var grab := {}   # 홀드 → 빛 색(손은 잡기 안내 색, 발은 흰색)
	if not logic.session.selecting:
		for limb in logic.session.limbs:
			var l: Dictionary = logic.session.limbs[limb]
			var gd := ReachMarker.grip_guide(logic.session, limb)
			if not gd.is_empty():
				grab[gd.key] = ReachMarker.GUIDE_COLORS[gd.level]
			elif l.state == "Dragging" and not l.cand.is_empty():
				grab[l.cand.key] = Color.WHITE
	var goal: String = logic._tutorial_goal_key()
	for key in hold_glows:
		var g: MeshInstance3D = hold_glows[key]
		var m := g.material_override as StandardMaterial3D
		if grab.has(key):
			g.visible = true
			m.albedo_color = Color(grab[key], 0.35 + 0.6 * fast)
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
		char_root.add_child(p)


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


## 낙하 장면이면 인형 점, 아니면 평소 목표. 장면이 끝나면 logic에 알린다. 돌려주는 점은 캐릭터 틀(char_root) 좌표.
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
		fall_sim.start(_to_world(_last_t), fold.basis_at(_char_s) * (req.vel as Vector3), pins, MAT_TOP_Y, WALL_Z, 0.0, fold.world_profile(WALL_Z))
		fall_sim.set_volumes(fold, logic.route.volumes)  # 떨어지는 몸이 볼륨을 뚫지 않게(2026-11-28)
		logic.fall_request = {}
	if fall_sim != null:
		if logic.fall_skip:
			fall_sim.skip()
			logic.fall_skip = false
		fall_sim.step(minf(delta, 1.0 / 30.0))
		var imp := fall_sim.take_impact()
		if not imp.is_empty():
			_on_landing(imp)
		var tw: Dictionary = fall_sim.points()
		var t := _to_char(tw)  # 캐릭터 틀은 떨어지기 시작한 높이 그대로
		var up := ((t.chest as Vector3) - (t.pelvis as Vector3)).normalized()
		t["up"] = up
		_fall_angle = rad_to_deg(atan2(-up.x, up.y))
		# 카메라가 떨어지는 몸을 따라 내려가 매트가 보이게(벽면 높이)
		var want := maxf(fold.nearest_s(tw.pelvis) + 0.12 * logic.PLAY_H, 1.4)  # 아래로 꺾이는 벽에서도 몸 가까운 벽면
		logic.cam_y = lerpf(logic.cam_y, want, 1.0 - exp(-6.0 * delta))
		if fall_sim.done():
			logic.on_fall_scene_done()
		if logic.session.halted != &"fall" and not logic.session.falling:
			fall_sim = null  # 다시 시작됨
		return t
	var t := _pose_targets(delta)
	_last_t = t
	# 캐릭터 틀 = 골반 높이의 벽면 틀(docs/57 §5). 몸은 그 틀로 통째로, 잡은 손발 끝만 접힌 벽의 홀드 자리에
	_char_s = (t.pelvis as Vector3).y
	char_root.transform = fold.frame(_char_s)
	var held := {}
	for limb in PoseSolver.LIMBS:
		held[limb] = logic.session.limbs[limb].state in ["Attached", "Armed"]
	return climber_to_char(t, fold, held, logic.route.volumes)


const UPPER_KEYS := ["spine", "chest", "neck", "head", "head_top", "shoulder_L", "elbow_L", "wrist_L", "hand_L", "shoulder_R", "elbow_R", "wrist_R", "hand_R"]
const LOWER_KEYS := ["hip_L", "knee_L", "ankle_L", "toe_L", "hip_R", "knee_R", "ankle_R", "toe_R"]
const LIMB_KEYS := {&"LH": ["shoulder_L", "elbow_L", "wrist_L", "hand_L"], &"RH": ["shoulder_R", "elbow_R", "wrist_R", "hand_R"],
	&"LF": ["hip_L", "knee_L", "ankle_L", "toe_L"], &"RF": ["hip_R", "knee_R", "ankle_R", "toe_R"]}


## 판정 벽 좌표 관절 → 캐릭터 틀(골반 높이의 벽면 틀) 좌표. 골반은 접힌 벽 위 제자리, 윗몸(척추·머리·팔)과 아랫몸(다리)은
## 각각 골반을 축으로 통째로 돌려 놓는다(뼈 길이 그대로, 허리에서 꺾임). 도는 방향은 잡은 손(딛은 발)이 접힌 벽의 홀드에
## 가장 잘 닿는 벽 방향(골반 높이 ~ 손발 높이 사이). 잡은 손발 끝(손목·발목)은 실제 홀드 자리로 옮기고 팔꿈치·무릎을
## 두 마디 IK로 다시 푼다. 점마다 접으면 크게 꺾이는 벽에서 몸이 찌그러지고 손가락이 늘어났다(2026-11-27 사용자
## "거의 누워있는 벽에서 무게중심에 따라 캐릭터가 엄청 찌그러져", "다음 홀드를 향해 뻗으면 손가락이 엄청 늘어지는").
static func climber_to_char(t: Dictionary, f: WallProfile, held: Dictionary, vols: Array = []) -> Dictionary:
	var sp: float = (t.pelvis as Vector3).y
	var fi := f.frame(sp).affine_inverse()
	var pel: Vector3 = fi * f.point(t.pelvis)
	var out := {"pelvis": pel}
	for k in t:
		if not (t[k] is Vector3) or k == "up":
			out[k] = t[k]
	var hands := PoseSolver.LIMBS.filter(func(l): return PoseSolver.is_hand(l) and held.get(l, false))
	var feet := PoseSolver.LIMBS.filter(func(l): return not PoseSolver.is_hand(l) and held.get(l, false))
	for part in [[UPPER_KEYS, hands, TORSO_KEYS], [LOWER_KEYS, feet, []]]:
		var rot := _part_basis(t, f, fi, pel, part[1], part[2])
		for k in part[0]:
			if t.has(k):
				out[k] = pel + rot * ((t[k] as Vector3) - (t.pelvis as Vector3))
	for k in t:  # 나머지 점(있으면)은 그대로 접는다
		if t[k] is Vector3 and not out.has(k):
			out[k] = fi * f.point(t[k])
	_shift_to_reach(out, t, f, fi, hands + feet)
	for limb in hands + feet:
		var ks: Array = LIMB_KEYS[limb]
		if not (t.has(ks[0]) and t.has(ks[1]) and t.has(ks[2])):
			continue
		var target: Vector3 = fi * f.point(t[ks[2]])
		var l1: float = (t[ks[1]] as Vector3).distance_to(t[ks[0]])
		var l2: float = (t[ks[2]] as Vector3).distance_to(t[ks[1]])
		if target.distance_to(out[ks[2]]) < 0.001:  # 이미 제자리: 팔꿈치·무릎이 벽에 들어갔으면만 돌린다(판정 자세에서도 생김)
			out[ks[1]] = _clear_mid(f, fi, out[ks[0]], target, out[ks[1]], l1, l2, (t[ks[1]] as Vector3).y, vols)
			continue
		var root: Vector3 = out[ks[0]]
		var old_dir: Vector3 = ((out[ks[2]] as Vector3) - (out[ks[1]] as Vector3)).normalized()
		var to := target - root
		var short := to.length() - (l1 + l2 - 0.001)
		if short > 0.0:  # 닿지 않으면 어깨(엉덩이)를 그 홀드 쪽으로 내민다(SHOULDER_REACH·HIP_REACH까지)
			root += to.normalized() * minf(short, SHOULDER_REACH if PoseSolver.is_hand(limb) else HIP_REACH)
			out[ks[0]] = root
			to = target - root
		if to.length() > l1 + l2 - 0.001:  # 그래도 닿지 않으면 팔·다리를 다 편 끝(홀드 조금 앞)
			target = root + to.normalized() * (l1 + l2 - 0.001)
		var mid := _clear_mid(f, fi, root, target, out[ks[1]], l1, l2, (t[ks[1]] as Vector3).y, vols)
		var new_dir: Vector3 = (target - mid).normalized()
		if out.has(ks[3]) and old_dir.length() > 0.5 and new_dir.length() > 0.5:
			out[ks[3]] = target + Quaternion(old_dir, new_dir) * ((out[ks[3]] as Vector3) - (out[ks[2]] as Vector3))
		out[ks[1]] = mid
		out[ks[2]] = target
	# 떠 있는 손발(뻗는 중·딛지 않은 발)도 그 높이의 접힌 벽면에서 판정 깊이만큼 떨어진 곳에 둔다. 통째로 돌리기만 하면
	# 위로 기운 벽에서 손이 벽 속으로 들어갔다(2026-11-27 사용자 "벽 각도에 맞춰서 벽과 특정 거리를 두고 손을 뻗도록").
	for limb in PoseSolver.LIMBS:
		if held.get(limb, false):
			continue
		var ks: Array = LIMB_KEYS[limb]
		if not (t.has(ks[0]) and t.has(ks[1]) and t.has(ks[2])):
			continue
		var l1: float = (t[ks[1]] as Vector3).distance_to(t[ks[0]])
		var l2: float = (t[ks[2]] as Vector3).distance_to(t[ks[1]])
		var root: Vector3 = out[ks[0]]
		var target: Vector3 = fi * f.point(t[ks[2]])
		var to := target - root
		if to.length() > l1 + l2 - 0.001:
			target = root + to.normalized() * (l1 + l2 - 0.001)
		out[ks[1]] = _clear_mid(f, fi, root, target, out[ks[1]], l1, l2, (t[ks[1]] as Vector3).y, vols)
		out[ks[2]] = target
		if t.has(ks[3]):  # 손끝·발끝도 접힌 벽을 따라 같은 쪽으로(길이 그대로)
			var dir: Vector3 = fi * f.point(t[ks[3]]) - fi * f.point(t[ks[2]])
			if dir.length() > 0.001:
				out[ks[3]] = target + dir.normalized() * (t[ks[3]] as Vector3).distance_to(t[ks[2]])
	_clear_head(out, f, fi, sp, vols)
	return out


const BODY_REACH := 0.12   # 어깨·엉덩이를 내밀어도 닿지 않는 손발이 있으면 몸 전체를 그쪽으로 옮기는 최대 거리(m)


## 앞으로 튀어나온 능선을 사이에 두고 골반과 잡은 발(손)이 갈리면, 펼친 평면보다 접힌 벽에서 거리가 멀어져 다 펴도 닿지 않았다
## (150° → 225°에서 발목이 홀드에서 15cm, 2026-11-28). 내민 뒤에도 모자라는 만큼 몸 전체를 옮긴다. 가장 많이 모자라는 것이 줄 때만.
static func _shift_to_reach(out: Dictionary, t: Dictionary, f: WallProfile, fi: Transform3D, limbs: Array) -> void:
	var lack := func(off: Vector3) -> Array:
		var sum := Vector3.ZERO
		var worst := 0.0
		for limb in limbs:
			var ks: Array = LIMB_KEYS[limb]
			if not (t.has(ks[0]) and t.has(ks[1]) and t.has(ks[2])):
				continue
			var reach: float = (t[ks[1]] as Vector3).distance_to(t[ks[0]]) + (t[ks[2]] as Vector3).distance_to(t[ks[1]])
			reach += SHOULDER_REACH if PoseSolver.is_hand(limb) else HIP_REACH
			var to: Vector3 = fi * f.point(t[ks[2]]) - ((out[ks[0]] as Vector3) + off)
			var short := to.length() - reach
			if short > 0.0:
				sum += to.normalized() * short
				worst = maxf(worst, short)
		return [sum, worst]
	var r0: Array = lack.call(Vector3.ZERO)
	if r0[1] <= 0.0:
		return
	var off: Vector3 = (r0[0] as Vector3).limit_length(BODY_REACH)
	if (lack.call(off)[1] as float) >= r0[1]:
		return
	for k in out:
		if out[k] is Vector3 and k != "up":
			out[k] += off


## 가슴·목·머리가 벽면에서 HEAD_CLEAR보다 가까우면 그 마디부터 위를 바로 아래 마디를 축으로(벽 x축) 벽에서 젖힌다.
## 어깨·팔은 그대로라 잡은 손은 홀드 위에 남는다. 능선(오버행 → 누운 벽)에서 머리 15cm·목 10cm가 벽 속이었다(2026-11-28).
const HEAD_CHAIN := ["spine", "chest", "neck", "head", "head_top"]
const HEAD_CLEAR := 0.1
const HEAD_BEND := {"chest": 0.35, "neck": 0.7, "head": 0.7}   # 마디마다 더 젖히는 최대 각(라디안)


static func _clear_head(out: Dictionary, f: WallProfile, fi: Transform3D, sp: float, vols: Array) -> void:
	var fr := fi.affine_inverse()
	var gap := func(m: Vector3) -> float:
		var w := fr * m
		return f.signed_dist(w, sp + m.y, 0.6, 0.02) - Volumes.depth_near(vols, Vector2(w.x, sp + m.y), 0.05)  # 캐릭터 틀 y ≈ 골반에서 벽면을 따라 잰 높이
	for i in range(1, 4):
		var k: String = HEAD_CHAIN[i]
		if not (out.has(k) and out.has(HEAD_CHAIN[i - 1])):
			return
		var d0: float = gap.call(out[k])
		if d0 >= HEAD_CLEAR:
			continue
		var piv: Vector3 = out[HEAD_CHAIN[i - 1]]
		var best_a := 0.0
		var best_d := d0
		var lim: float = HEAD_BEND[k]
		for n in range(1, 13):
			for sgn in [1.0, -1.0]:
				var a: float = sgn * lim * n / 12.0
				var d: float = gap.call(piv + ((out[k] as Vector3) - piv).rotated(Vector3.RIGHT, a))
				if d > best_d + 1e-4:
					best_d = d
					best_a = a
			if best_d >= HEAD_CLEAR:
				break
		if best_a != 0.0:
			for j in range(i, HEAD_CHAIN.size()):
				if out.has(HEAD_CHAIN[j]):
					out[HEAD_CHAIN[j]] = piv + ((out[HEAD_CHAIN[j]] as Vector3) - piv).rotated(Vector3.RIGHT, best_a)


const MID_CLEAR := 0.04        # 팔꿈치·무릎이 벽면에서 떨어져야 하는 거리(m). 이보다 가까우면 IK 방향을 돌린다


## 두 마디 IK의 가운데 관절(캐릭터 틀). 원래 방향(pole)의 관절이 벽면에 MID_CLEAR보다 가까우면(위로 기운 벽·천장),
## 뼈 축을 돌며 8방향을 보고 벽에서 떨어진 것 중 원래 방향에 가장 가까운 것(없으면 가장 먼 것). s: 그 관절의 판정 높이.
static func _clear_mid(f: WallProfile, fi: Transform3D, root: Vector3, target: Vector3, pole: Vector3, l1: float, l2: float, s: float, vols: Array = []) -> Vector3:
	var fr := fi.affine_inverse()
	var mid := LimbIK.two_bone(root, target, pole, l1, l2)
	# 볼륨이 있는 자리는 볼륨 겉면을 벽면으로 본다(2026-11-28: 상자 위 모서리를 잡은 팔꿈치가 상자 속 20cm). 벽 x는 캐릭터·월드 x와 같다
	var gap := func(m: Vector3) -> float:
		var w := fr * m
		return _surface_dist(f, w, s) - Volumes.depth_near(vols, Vector2(w.x, s), 0.05)
	var d0: float = gap.call(mid)
	if d0 >= MID_CLEAR:
		return mid
	var axis := (target - root).normalized()
	var u := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.UP).normalized()
	var v := axis.cross(u)
	var c := (root + target) * 0.5
	var want := (mid - c).normalized()
	var best := mid
	var best_d := d0
	var best_dot := -INF
	for i in 8:
		var a := TAU * i / 8.0
		var m := LimbIK.two_bone(root, target, c + (u * cos(a) + v * sin(a)), l1, l2)
		var d: float = gap.call(m)
		var dot := (m - c).normalized().dot(want)
		if (d >= MID_CLEAR and (best_d < MID_CLEAR or dot > best_dot)) or (best_d < MID_CLEAR and d > best_d):
			best = m
			best_d = d
			best_dot = dot
	return best


## 월드 점 w가 접힌 벽면 앞(+)·뒤(−)로 떨어진 거리(m): 판정 높이 s ±0.6m 벽면 선을 2cm마다 훑어 가장 가까운 곳의 법선 쪽.
static func _surface_dist(f: WallProfile, w: Vector3, s: float, step := 0.02) -> float:
	return f.signed_dist(w, s, 0.6, step)


const PART_LEAN_EXTRA := 0.5   # 벽 방향 범위 밖으로 더 기울여 보는 각(라디안, 약 29°)
const SHOULDER_REACH := 0.12   # 손이 홀드에 닿지 않을 때 어깨를 내미는 최대 거리(m)
const HIP_REACH := 0.07        # 발이 닿지 않을 때 엉덩이를 내미는 최대 거리(m)
const PART_LEAN_STEPS := 16


## 윗몸·아랫몸을 돌릴 방향(캐릭터 틀 기준 회전): 골반 높이 ~ 잡은 손발 높이의 벽 방향(앞뒤로 PART_LEAN_EXTRA 더) 중, 잡은 손발 끝이
## 팔·다리 길이 안에 들고(못 닿는 거리 합이 가장 작고) 펼친 자세와 가장 가까운 것. 잡은 손발이 없으면 골반 높이.
## clear: 벽면에서 TORSO_CLEAR 넘게 떨어져야 하는 점(윗몸: 가슴·머리). 손이 닿는 것과 함께 본다(벌점 TORSO_WEIGHT/m).
## 2026-11-28 벽 모양 점검: 1m부터 천장인 벽에서 천장 아래 선 머리가 천장 속 34cm, 지그재그·무작위 벽에서 9~16cm.
## 능선(앞으로 튀어나온 꺾임)은 이것만으로 다 풀리지 않는다(판정 자세가 꺾인 벽을 모르는 구조, docs/52).
const TORSO_KEYS := ["chest", "head"]
const TORSO_CLEAR := 0.06
const TORSO_WEIGHT := 5.0


static func _part_basis(t: Dictionary, f: WallProfile, fi: Transform3D, pel: Vector3, limbs: Array, clear: Array = []) -> Basis:
	var sp: float = (t.pelvis as Vector3).y
	if limbs.is_empty():
		return fi.basis * f.basis_at(sp)
	var lo := f.angle_rad(sp)
	var hi := lo
	for limb in limbs:
		var e: Vector3 = t[LIMB_KEYS[limb][2]]
		lo = minf(lo, f.angle_rad(e.y))
		hi = maxf(hi, f.angle_rad(e.y))
	lo -= PART_LEAN_EXTRA
	hi += PART_LEAN_EXTRA
	var best := Basis()
	var best_cost := INF
	for i in PART_LEAN_STEPS + 1:
		var rot := fi.basis * Basis(Vector3.RIGHT, lerpf(lo, hi, float(i) / PART_LEAN_STEPS))
		var cost := 0.0
		for limb in limbs:
			var ks: Array = LIMB_KEYS[limb]
			var root: Vector3 = pel + rot * ((t[ks[0]] as Vector3) - (t.pelvis as Vector3))
			var end: Vector3 = pel + rot * ((t[ks[2]] as Vector3) - (t.pelvis as Vector3))
			var target: Vector3 = fi * f.point(t[ks[2]])
			var reach: float = (t[ks[1]] as Vector3).distance_to(t[ks[0]]) + (t[ks[2]] as Vector3).distance_to(t[ks[1]])
			cost += maxf(0.0, root.distance_to(target) - reach + 0.01) * 10.0 + end.distance_to(target)
		if not clear.is_empty():
			var fr := fi.affine_inverse()
			for k in clear:
				if t.has(k):
					var w: Vector3 = fr * (pel + rot * ((t[k] as Vector3) - (t.pelvis as Vector3)))
					cost += maxf(0.0, TORSO_CLEAR - _surface_dist(f, w, (t[k] as Vector3).y, 0.05)) * TORSO_WEIGHT
		if cost < best_cost - 1e-6:
			best_cost = cost
			best = rot
	return best


## 판정 벽 좌표 관절 → 월드(접힌 벽). 점은 하나씩 접고, 방향 "up"은 골반 높이의 벽 틀로 돌린다.
func _to_world(t: Dictionary) -> Dictionary:
	var out := {}
	var b := fold.basis_at((t.pelvis as Vector3).y) if t.has("pelvis") else Basis()
	for k in t:
		if t[k] is Vector3:
			out[k] = (b * (t[k] as Vector3)) if k == "up" else fold.point(t[k] as Vector3)
		else:
			out[k] = t[k]
	return out


## 월드 관절 → 캐릭터 틀(char_root) 좌표.
func _to_char(t: Dictionary) -> Dictionary:
	var out := {}
	var g := char_root.transform.affine_inverse()
	for k in t:
		if t[k] is Vector3:
			out[k] = (g.basis * (t[k] as Vector3)) if k == "up" else (g * (t[k] as Vector3))
		else:
			out[k] = t[k]
	return out


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
		logic.puffs.append({"kind": &"dust", "pos": Vector2(pos.x + dx, MAT_TOP_Y + 0.05), "z": pos.z, "world": true})


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


var rig := RigPose.new()


## RigPose(docs/04 §8)가 만든 연속 프레임을 그대로 적용한다. 180° 대체 회전 없음.
func _pose_model(t: Dictionary, delta: float) -> void:
	var inv := skeleton.global_transform.affine_inverse() * char_root.global_transform  # t는 캐릭터 틀 좌표
	var local := {}
	for key in t:
		if t[key] is Vector3 and key != "up":
			local[key] = inv * (t[key] as Vector3)
	var free_feet := {"L": ClimberPose._free(logic.session, &"LF"), "R": ClimberPose._free(logic.session, &"RF")}
	_update_curl(delta)
	var frames := rig.solve(local, _fall_angle if fall_sim != null else logic.session.body.angle, float(t.get("yaw", logic.session.body.yaw)), free_feet, curl)
	_apply_look(frames, inv, delta)
	for name in RigPose.bone_names():
		var idx := skeleton.find_bone(name)
		if idx >= 0 and frames.has(name):
			skeleton.set_bone_global_pose(idx, frames[name])
	_curl_fingers(frames, delta)


## 손가락 말아 쥐기(docs/36, 2026-11-13 사용자: "홀드를 잡고 있으면 손가락을 구부리는 모션으로"):
## 홀드를 잡은 손(Attached·Armed)은 아래팔·손을 길이축으로 돌려 손바닥(휴지 T자에서 아래)이 벽을 보게 하고(RigPose.solve grip),
## 손 뼈(손가락 첫 마디)와 손가락 뼈(끝 마디)를 손바닥 쪽으로 접는다(_curl_fingers). 떼면 펴진다(1/s 8로 부드럽게).
## 손가락 뼈(finger_L/R)가 없는 모델이면 아무것도 하지 않는다.
const CURL_HAND_DEG := 60.0   # 손 뼈를 손바닥 쪽으로 접는 각(손가락 첫 마디)
const CURL_FINGER_DEG := 75.0 # 손가락 뼈를 더 접는 각(끝 마디, 손 뼈 기준)
const CURL_SPEED := 8.0       # 1/s
const PALM_REST := Vector3.DOWN  # 휴지 T자 손바닥 방향
var finger_rest := {}         # "L"/"R" -> {idx, hand_idx, rest(손 기준 손가락 휴지 Transform), len}
var curl := {"L": 0.0, "R": 0.0}


## 잡은 정도(0~1)를 갱신한다. 잡은 손의 아래팔·손 돌리기는 RigPose.solve(grip)가 한다.
func _update_curl(delta: float) -> void:
	for s in ["L", "R"]:
		var l: Dictionary = logic.session.limbs[StringName(s + "H")]
		var want := 1.0 if l.state in ["Attached", "Armed"] else 0.0
		curl[s] = move_toward(curl[s], want, CURL_SPEED * delta)


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
const LOOK_BACK_DEG := 125.0 # 정상 때 어깨 너머로 돌아보는 각
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
			best = char_root.transform.affine_inverse() * fold.point(Vector3(p.x, p.y, CONTACT_DEPTH + Volumes.depth_near(logic.route.volumes, p, 0.02)))  # 캐릭터 틀 좌표
			break
	return best


## 어깨 너머로 돌아보는가: 정상을 잡았을 때만. 떨어질 때·착지 장면은 몸이 벽을 본 채라 머리만 뒤로 돌면 무서워 보여 돌아보지 않는다(2026-11-20 사용자).
static func looks_back(happy: bool, falling: bool) -> bool:
	return happy and not falling


func _apply_look(frames: Dictionary, inv: Transform3D, delta: float) -> void:
	if not frames.has("head"):
		return
	var head: Transform3D = frames["head"]
	var want := Quaternion.IDENTITY
	var target: Variant = _look_target()
	var body_up0: Vector3 = (head.basis * Vector3.UP).normalized()
	var side0: Vector3 = (head.basis * Vector3.RIGHT).normalized()
	if looks_back(face_now == "happy", logic.session.falling or fall_sim != null):
		# 정상을 잡았을 때는 어깨 너머로 카메라 쪽을 돌아본다(표정이 보이는 순간).
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
	char_root.add_child(model)
	asm.apply(model, look)
	var found := model.find_children("*", "Skeleton3D", true, false)
	skeleton = found[0] if found.size() > 0 else null
	if skeleton == null or not CharacterAssembler.compatible(skeleton):
		skeleton = null  # 뼈 길이가 지금 몸과 다르면 캡슐 인형(2026-11-11 B안)
		model.queue_free()
		return false
	var leg := CharacterAssembler.leg_shape(skeleton)  # 화면 다리 관절·길이는 모델마다(docs/37 §7)
	LimbIK.set_leg_shape(float(leg.raise), float(leg.upper), float(leg.lower))
	rig.setup_from_skeleton(skeleton)
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


const CAM_MIN_Y := 0.6  # 기운 벽에서 카메라 최저 높이(m, 매트 위)
const CAM_WALL_GAP := 0.8  # 시점 카메라가 벽면에서 떨어지는 최소 거리(m)
var _wings: Array[MeshInstance3D] = []  # 옆벽: 비스듬히·옆 시점에서는 카메라를 가려 숨긴다
var _neighbors := []  # [side, 판넬]: 이웃 벽(배경). 카메라가 그쪽으로 돌면 가리므로 숨긴다


func _update_camera() -> void:
	var size := get_viewport().get_visible_rect().size
	if size.y <= 0:
		return
	# 높이 3.8m를 기본으로, 중앙 56% 폭에 3.4m가 들어가지 않으면 시야를 넓힌다(docs/05 고정 플레이 창).
	var visible_h := maxf(PLAY_H, PLAY_W * size.y / maxf(size.x * 0.56, 1.0))
	var dist := (visible_h * 0.5) / tan(deg_to_rad(camera.fov * 0.5))
	# 기운 벽: 벽 면의 지금 높이를 보되, 카메라는 기운 각의 1/4만 아래에서 올려다본다(벽 법선 쪽에 서면 매트 밑으로 들어감).
	# 매트 위 CAM_MIN_Y 아래로는 내려가지 않는다. 수직 벽은 이전과 같다.
	# 손가락 시점(logic.cam_yaw·cam_pitch·cam_zoom, [시점]으로 조정): 카메라가 몸 높이를 중심으로 벽 앞을 돈다.
	var th := fold.angle_rad(logic.cam_y)  # 꺾이는 벽(docs/57): 카메라 높이의 벽 각도(경계에서 부드럽게 바뀜)
	var yaw: float = logic.cam_yaw
	var free_cam: bool = logic.route.wall_deg > 0.0 or yaw != 0.0 or logic.cam_pitch != 0.0 or logic.cam_zoom != 1.0
	for w in _wings:
		w.visible = absf(yaw) < deg_to_rad(10.0)  # 옆벽(장식)이 돈 카메라를 가린다
	for nb in _neighbors:
		(nb[1] as Node3D).visible = yaw * float(nb[0]) < deg_to_rad(20.0)
	var look := fold.point(Vector3(logic.session.body.pos.x * smoothstep(0.0, 0.3, absf(yaw)), logic.cam_y, CONTACT_DEPTH))
	camera.position = look + Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, th * 0.25 + float(logic.cam_pitch)) * Vector3(0, 0, dist * float(logic.cam_zoom))
	if free_cam:
		# 돌리거나 기운 벽에서 카메라가 벽면을 뚫고 뒤(빈 공간)를 보지 않게 벽면 앞으로 밀고, 매트 아래로 내려가지 않게
		camera.position = fold.push_in_front(camera.position, CAM_WALL_GAP, logic.route.volumes)
		camera.position.y = maxf(camera.position.y, CAM_MIN_Y)
		camera.look_at(look, Vector3.UP)
	else:
		camera.rotation = Vector3.ZERO


## 벽 접촉 면(z = CONTACT_DEPTH, 접힌 벽)의 판정 좌표 → 화면 픽셀. 기술 UI의 홀드 강조·탭 변환용.
func world_to_screen(p: Vector2) -> Vector2:
	return camera.unproject_position(fold.point(Vector3(p.x, p.y, CONTACT_DEPTH + Volumes.mount_depth(logic.route.volumes, p))))


## 화면 픽셀 → 카메라 광선과 접촉 면의 교점(판정 벽 좌표). 꺾이는 벽은 그 높이의 접평면과 몇 번 교차해 맞춘다.
func screen_to_wall(s: Vector2) -> Vector2:
	var y: float = logic.cam_y
	var hit := Vector2(0, y)
	var zv := 0.0
	for i in 6:
		var gi := fold.frame(y).affine_inverse()
		var o := gi * camera.project_ray_origin(s)
		var n := gi.basis * camera.project_ray_normal(s)
		if absf(n.z) < 0.0001:
			return Vector2(o.x, y + o.y)
		var t := (CONTACT_DEPTH + zv - o.z) / n.z
		var nh := Vector2(o.x + n.x * t, y + o.y + n.y * t)
		var nz := Volumes.mount_depth(logic.route.volumes, nh)  # 볼륨 겉면을 누르면 그 면(2026-11-28)
		if absf(nh.y - hit.y) < 0.002 and absf(nh.x - hit.x) < 0.002 and absf(nz - zv) < 0.002:
			hit = nh
			break
		hit = nh
		zv = nz
		y = hit.y
	return hit


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
			_on_wall(m, Vector3(p.x, p.y - 0.09, Tuning.CONTACT_DEPTH + Volumes.depth_near(logic.route.volumes, p, 0.02)))
		foot_marks[foot][0].visible = attached and loaded
		foot_marks[foot][1].visible = attached and not loaded
		var flag: bool = l.state == "Flag" or (l.state == "Dragging" and logic.session.rules.flag_ready.has(foot))
		flag_marks[foot].visible = flag
		_on_wall(flag_marks[foot], Vector3(p.x, p.y + 0.12, Tuning.CONTACT_DEPTH + 0.12 + (float(l.flag_depth) if l.state == "Flag" else 0.0)))


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
		var pp := Vector3((p.pos as Vector2).x, (p.pos as Vector2).y, float(p.get("z", CONTACT_DEPTH + 0.06)))
		if p.get("world", false):
			e.position = pp  # 착지 먼지는 월드(매트)
		else:
			_on_wall(e, pp)  # 나머지는 벽 좌표(접힌 벽 위)
		(self if p.get("world", false) else wall_root).add_child(e)
		e.emitting = true
		get_tree().create_timer(1.0).timeout.connect(e.queue_free)
	logic.puffs.clear()
