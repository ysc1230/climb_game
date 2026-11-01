extends Node
## 자동 로드 Game(docs/28 §5). 진행·콘텐츠 목록을 들고 홈 ↔ 플레이 장면을 바꾼다.
## 기록·해금 판단은 노드 없는 PlayFlow가 맡고 여기서는 장면 전환과 홈 위치만 기억한다.
## 헤드리스 테스트(--script)에서도 문제없게 _ready에서는 아무것도 읽지 않고, 처음 쓸 때 읽는다.

const HOME_SCENE := "res://scenes/home.tscn"
const PLAY_SCENE := "res://scenes/play_3d.tscn"

var progress: Progress:
	get:
		return get_flow().progress
var index: ContentIndex:
	get:
		return get_flow().index
var current_route_id: String:
	get:
		return get_flow().current_route_id if _flow != null else ""
	set(v):
		get_flow().current_route_id = v
## 홈으로 돌아갈 때 열 위치 {tab, grade?, course?}. 홈이 한 번 읽고 비운다.
var home_focus := {}
## 첫 실행 기본 조작 튜토리얼로 한 번 보냈는지(이번 실행 동안).
var first_run_sent := false

var _flow: PlayFlow


func get_flow() -> PlayFlow:
	if _flow == null:
		_flow = PlayFlow.new(ContentIndex.load_all(), SaveStore.load(), SaveStore.DEFAULT_PATH)
	return _flow


## 문제를 연다(play_3d 장면).
func play(route_id: String) -> void:
	current_route_id = route_id
	get_tree().change_scene_to_file(PLAY_SCENE)


## 홈으로. focus를 주면 그 위치, 아니면 지금 문제의 목록(등급 또는 과정 화면)을 연다.
func home(focus := {}) -> void:
	if not focus.is_empty():
		home_focus = focus
	elif current_route_id != "":
		home_focus = get_flow().list_target(current_route_id)
	current_route_id = ""
	get_tree().change_scene_to_file(HOME_SCENE)


func finish_clear(seconds: float, falls: int) -> Dictionary:
	return get_flow().finish_clear(seconds, falls)


func finish_tutorial() -> bool:
	return get_flow().finish_tutorial()


func skip_basic() -> bool:
	return get_flow().skip_basic()


func allowed_buttons_for(route: RouteDef, tutorial: TutorialRunner = null) -> Array[StringName]:
	return get_flow().allowed_buttons_for(route, tutorial)
