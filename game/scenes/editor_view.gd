extends "res://scenes/play_3d.gd"
## 문제 만들기 화면의 3D 벽(작업 6 §2): 플레이 장면과 같은 벽·홀드 그림. 판정·캐릭터 없음.
## 홀드를 고칠 때마다 rebuild로 벽·홀드를 다시 만든다. 끄는 동안은 preview_hold로 그 홀드만 옮겨 그린다.
## 카메라: 지금 높이(cam_y)의 벽면을 정면으로 보고, 두 손가락 시점(cam_yaw·cam_pitch)과 확대(zoom_h, 보이는 높이 m)를 더한다.


## 플레이 장면의 logic 자리(벽·홀드 만들기가 route·cam_y만 읽는다).
class Stub:
	var route: RouteDef
	var cam_y := 1.6

const ZOOM_MIN := 1.8
const ZOOM_MAX := 12.0
const TURN := 0.006                     # 끈 픽셀당 도는 각(라디안, 플레이와 같음)
const YAW_MAX := deg_to_rad(60.0)
const PITCH_MAX := deg_to_rad(45.0)
var zoom_h := 4.6
var cam_yaw := 0.0
var cam_pitch := 0.0
var top_h := 6.5                        # 그리는 벽 위끝(초안의 놓을 수 있는 높이)
var _built: Array = []


func _ready() -> void:
	rng.seed = 1230
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
	for n in _built:
		n.queue_free()
	_built.clear()
	for n in wall_root.get_children():
		wall_root.remove_child(n)
		n.queue_free()
	hold_glows.clear()
	hold_nodes.clear()
	_wings.clear()
	_neighbors.clear()
	var before := {}
	for c in get_children():
		before[c] = true
	logic.route = d.build(Vector2(0, 0.75))
	top_h = d.max_y()
	fold = WallProfile.new(logic.route, -1.5, top_h + 3.0)
	rng.seed = 1230
	_build_wall()
	_build_holds()
	for c in get_children():
		if not before.has(c):
			_built.append(c)


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


func _process(_delta: float) -> void:
	_update_camera()


func _update_camera() -> void:
	if fold == null:
		return
	var dist := (zoom_h * 0.5) / tan(deg_to_rad(camera.fov * 0.5))
	var b := fold.basis_at(logic.cam_y)
	var look := fold.point(Vector3(0, logic.cam_y, CONTACT_DEPTH))
	camera.position = look + b * (Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch) * Vector3(0, 0, dist))
	camera.position = fold.push_in_front(camera.position, CAM_WALL_GAP)
	camera.position.y = maxf(camera.position.y, CAM_MIN_Y)  # 천장 쪽을 볼 때 매트 아래로 내려가지 않게
	camera.look_at(look, b.y)
	for w in _wings:
		w.visible = absf(cam_yaw) < deg_to_rad(10.0)  # 옆벽(장식)이 돈 카메라를 가린다
	for nb in _neighbors:
		(nb[1] as Node3D).visible = cam_yaw * float(nb[0]) < deg_to_rad(20.0)
