extends "res://scenes/play_3d.gd"
## 문제 만들기 화면의 3D 벽(작업 6 §2): 플레이 장면과 같은 벽·홀드 그림. 판정·캐릭터 없음.
## 홀드를 고칠 때마다 rebuild: 벽은 각도·높이가 바뀔 때만 다시 만들고, 홀드는 바뀐 것만 다시 만든다(2026-11-26 최적화, 홀드 300개·벽 100m).
## 끄는 동안은 preview_hold로 그 홀드만 옮겨 그린다.
## 카메라: 땅 기준 수평으로 지금 높이(cam_y)의 벽면 점을 보고, 두 손가락 시점(cam_yaw·cam_pitch)과 확대(zoom_h, 보이는 높이 m)를 더한다.
## 2026-11-26 사용자 "벽각도를 조정하면 벽을 기준으로 땅이 움직여. 땅을 기준으로 벽이 움직이도록", "줌인을 하면 카메라가 벽 각도에 따라 조정되는것같아":
## 카메라는 벽 각도를 따라 돌지 않는다. 벽 각도를 돌리는 동안(hold_cam)은 멈춰 벽만 돌고, 각도가 바뀌면 보는 점이 새 벽으로 미끄러져 간다.


## 플레이 장면의 logic 자리(벽·홀드 만들기가 route·cam_y만 읽는다).
class Stub:
	var route: RouteDef
	var cam_y := 1.6

const ZOOM_MIN := 1.8
const ZOOM_MAX := 12.0
const TURN := 0.006                     # 끈 픽셀당 도는 각(라디안, 플레이와 같음)
const YAW_MAX := deg_to_rad(60.0)
const PITCH_MAX := deg_to_rad(80.0)       # 땅 기준이라 천장(90°)은 올려다봐야 보인다
const LOOK_GLIDE := 6.0                 # 벽 각도가 바뀐 뒤 보는 점이 따라가는 빠르기(1/초)
var zoom_h := 4.6
var cam_yaw := 0.0
var cam_pitch := 0.0
var top_h := 6.5                        # 그리는 벽 위끝(초안의 놓을 수 있는 높이)
var hold_cam := false                   # 벽 각도 조절 원을 끄는 중: 카메라를 멈춘다
var _eye_at := Vector3.INF                # 카메라가 보는 점(월드)
var _glide := false                     # 벽 각도가 바뀌어 보는 점이 새 벽으로 가는 중
var _walls_sig := ""
var _dt := 0.0
var _built: Array = []                  # _build_wall이 만든 것(벽·옆벽·방·매트 …): 벽이 바뀔 때만 지우고 다시
var _wall_key := ""                     # 벽을 다시 접을 때를 가리는 열쇠(각도 구간·높이)
var _deco_key := ""                     # 벽 장식을 다시 놓을 때를 가리는 열쇠(가장자리 홀드 자리)
var _hold_sig := {}                     # 슬롯 키 → 모양 열쇠(자리·종류·크기·방향·합손·탑). 같으면 다시 만들지 않는다


func _ready() -> void:
	rng.seed = 1230
	build_glows = false
	logic = Stub.new()
	logic.route = RouteDraft.new().build(Vector2(0, 0.75))  # 배경·안개 색(_style)이 문제의 벽 꾸밈을 읽는다
	add_child(wall_root)  # 벽·홀드는 접힌 벽(fold) 위에 wall_root 아래로 놓인다(docs/57)
	_build_environment()
	var ui = get_node_or_null("UI/EditorUI")
	if ui != null:
		ui.view = self


func _wall_top() -> float:
	return top_h


func rebuild(d: RouteDraft) -> void:
	logic.route = d.layout_route()
	var key := str([d.walls, d.max_y()])
	# 벽 장식(볼륨)은 벽 가장자리(|x| ≥ 1.2m)에 홀드와 0.71m 넘게 떨어져 놓인다: 그 안에 들 수 있는 가장자리 홀드가 바뀌면 다시 놓는다
	var deco := str(d.holds.filter(func(h): return absf(h.x) > 0.49).map(func(h): return [h.x, h.y]))
	var refold := fold == null or key != _wall_key
	if refold or deco != _deco_key:
		if refold:
			_glide = _glide or (_wall_key != "" and str(d.walls) != _walls_sig)
			_walls_sig = str(d.walls)
			_wall_key = key
			top_h = d.max_y()
			fold = WallProfile.new(logic.route, -1.5, top_h + 3.0)
		_deco_key = deco
		_rebuild_wall()
	_sync_holds()


## 벽(접힌 띠·옆벽·방·매트·볼륨)을 다시 만든다. 홀드는 그대로 두고 _sync_holds가 새 벽에 다시 놓는다.
func _rebuild_wall() -> void:
	for n in _built:
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.queue_free()
	_built.clear()
	_wings.clear()
	_neighbors.clear()
	rng.seed = 1230
	var before := {}
	for c in get_children() + wall_root.get_children():
		before[c] = true
	_build_wall()
	for c in get_children() + wall_root.get_children():
		if not before.has(c):
			_built.append(c)


## 홀드를 초안에 맞춘다: 없어진 것은 지우고, 모양이 바뀐 것·새 것은 다시 만들고, 나머지는 (새 벽에) 다시 놓는다.
func _sync_holds() -> void:
	var slots: Dictionary = logic.route.slots
	for key in hold_nodes.keys():
		var node: Node3D = hold_nodes[key][0]
		if slots.has(key) and _hold_sig.get(key, "") == _sig(key):
			node.transform = _wall_xform(hold_nodes[key][1])  # 새 벽에 다시 놓고, 끌던 미리보기도 되돌린다
			continue
		wall_root.remove_child(node)
		node.queue_free()
		hold_nodes.erase(key)
		_hold_sig.erase(key)
	for key in slots:
		if not hold_nodes.has(key):
			_add_hold(key)
			_hold_sig[key] = _sig(key)


func _sig(key: String) -> String:
	var sl: Dictionary = logic.route.slots[key]
	return str([sl.pos, sl.get("hold_type", ""), sl.get("size", ""), sl.get("rot_deg", 0), sl.has("hand_area"), sl.get("hand_area", {}).get("matchable", false), logic.route.goal_slots.has(key)])


## 끄는 동안: 홀드 id를 벽 좌표로 off만큼 옮기고 rot_deg만큼 더 돌린 모습(시계 방향 +, 초안의 rot와 같음)으로 그린다.
func preview_hold(id: String, off: Vector2, rot_deg: float) -> void:
	var tag := "/%s/" % id
	for key in hold_nodes:
		if not String(key).contains(tag):
			continue
		var t: Transform3D = hold_nodes[key][1]
		(hold_nodes[key][0] as Node3D).transform = _wall_xform(Transform3D(Basis(Vector3.BACK, -deg_to_rad(rot_deg)) * t.basis, t.origin + Vector3(off.x, off.y, 0.0)))


## 두 손가락 끌기 → 시점(벽면 정면 기준 좌우·위아래).
func turn(d: Vector2) -> void:
	cam_yaw = clampf(cam_yaw - d.x * TURN, -YAW_MAX, YAW_MAX)
	cam_pitch = clampf(cam_pitch - d.y * TURN, -PITCH_MAX, PITCH_MAX)


## 판정 벽 좌표 p가 카메라 앞에 있나(뒤의 점은 화면 좌표가 뒤집혀 그리지 않는다).
func in_view(p: Vector2) -> bool:
	return fold != null and not camera.is_position_behind(fold.point(Vector3(p.x, p.y, CONTACT_DEPTH)))


func _process(delta: float) -> void:
	_dt = delta
	_update_camera()


func _update_camera() -> void:
	if fold == null:
		return
	var delta := _dt
	var dist := (zoom_h * 0.5) / tan(deg_to_rad(camera.fov * 0.5))
	var target := fold.point(Vector3(0, logic.cam_y, CONTACT_DEPTH))
	if _eye_at == Vector3.INF:
		_eye_at = target
	elif hold_cam:
		pass
	elif _glide and delta > 0.0:
		_eye_at = _eye_at.lerp(target, 1.0 - exp(-LOOK_GLIDE * delta))
		_glide = _eye_at.distance_to(target) > 0.005
	else:
		_eye_at = target
		_glide = false
	camera.position = _eye_at + Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch) * Vector3(0, 0, dist)
	camera.position = fold.push_in_front(camera.position, CAM_WALL_GAP)
	camera.position.y = maxf(camera.position.y, CAM_MIN_Y)  # 올려다볼 때 매트 아래로 내려가지 않게
	camera.look_at(_eye_at, Vector3.UP)
	for w in _wings:
		w.visible = absf(cam_yaw) < deg_to_rad(10.0)  # 옆벽(장식)이 돈 카메라를 가린다
	for nb in _neighbors:
		(nb[1] as Node3D).visible = cam_yaw * float(nb[0]) < deg_to_rad(20.0)
