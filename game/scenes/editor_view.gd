extends "res://scenes/play_3d.gd"
## 문제 만들기 화면의 3D 벽(작업 6 §2): 플레이 장면과 같은 벽·홀드 그림을 정면 카메라로 그린다. 판정·캐릭터 없음.
## 홀드를 고칠 때마다 rebuild로 벽·홀드를 다시 만든다. 위아래 이동(cam_y)·확대(zoom_h, 보이는 높이 m)는 편집 UI가 정한다.


## 플레이 장면의 logic 자리(벽·홀드 만들기가 route·cam_y만 읽는다).
class Stub:
	var route: RouteDef
	var cam_y := 1.6

const ZOOM_MIN := 1.8
const ZOOM_MAX := 5.2
var zoom_h := 4.6
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


func rebuild(d: RouteDraft) -> void:
	for n in _built:
		n.queue_free()
	_built.clear()
	for n in wall_root.get_children():
		wall_root.remove_child(n)
		n.queue_free()
	hold_glows.clear()
	_wings.clear()
	_neighbors.clear()
	var before := {}
	for c in get_children():
		before[c] = true
	logic.route = d.build(Vector2(0, 0.75))
	fold = WallProfile.new(logic.route, -1.5, _wall_top() + 3.0)
	rng.seed = 1230
	_build_wall()
	_build_holds()
	for c in get_children():
		if not before.has(c):
			_built.append(c)


func _process(_delta: float) -> void:
	_update_camera()


func _update_camera() -> void:
	var dist := (zoom_h * 0.5) / tan(deg_to_rad(camera.fov * 0.5))
	camera.position = Vector3(0, logic.cam_y, CONTACT_DEPTH + dist)
	camera.rotation = Vector3.ZERO
