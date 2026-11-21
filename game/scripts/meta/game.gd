extends Node
## 자동 로드 Game(docs/28 §5). 진행·콘텐츠 목록을 들고 홈 ↔ 플레이 장면을 바꾼다.
## 기록·해금 판단은 노드 없는 PlayFlow가 맡고 여기서는 장면 전환과 홈 위치만 기억한다.
## 헤드리스 테스트(--script)에서도 문제없게 _ready에서는 아무것도 읽지 않고, 처음 쓸 때 읽는다.

const HOME_SCENE := "res://scenes/home.tscn"
const PLAY_SCENE := "res://scenes/play_3d.tscn"
const EDITOR_SCENE := "res://scenes/editor.tscn"

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
## 만들기 화면에서 고치는 내 문제(작업 6). [올라 보기] 뒤 홈 대신 만들기 화면으로 돌아간다.
var editing_route_id := ""
## 첫 실행 기본 조작 튜토리얼로 한 번 보냈는지(이번 실행 동안).
var first_run_sent := false

var _flow: PlayFlow
var _share: ShareClient


## 공유 서버 연결(작업 6B). 처음 쓸 때 만든다.
func share() -> ShareClient:
	if _share == null:
		_share = ShareClient.new()
		add_child(_share)
	return _share


## 공유 코드로 받은 문제를 연다(받아 둔 파일이 있어야 함).
func play_shared(code: String) -> bool:
	var r := SharedRoutes.load_route(code)
	if r == null or not r.errors.is_empty():
		return false
	get_flow().add_custom(r)
	play(r.route_id)
	return true


func get_flow() -> PlayFlow:
	if _flow == null:
		_flow = PlayFlow.new(ContentIndex.load_all(), SaveStore.load(), SaveStore.DEFAULT_PATH)
		_flow.progress.unlock_all = true  # 실험 앱(experiment/overhang): 모든 등급 열림(2026-11-22 사용자)
	return _flow


## 문제를 연다(play_3d 장면).
func play(route_id: String) -> void:
	current_route_id = route_id
	get_tree().change_scene_to_file(PLAY_SCENE)


## 만들기 화면을 연다(작업 6). route_id가 비면 새 문제.
func edit(route_id := "") -> void:
	editing_route_id = route_id
	current_route_id = ""
	get_tree().change_scene_to_file(EDITOR_SCENE)


## 이 기기에 저장한 내 문제를 연다(인터넷 없이).
func play_custom(route_id: String) -> bool:
	var r := MyRoutes.load_route(route_id)
	if r == null or not r.errors.is_empty():
		return false
	get_flow().add_custom(r)
	play(route_id)
	return true


## 홈으로. 만들기 화면에서 [올라 보기]로 온 문제면 만들기 화면으로 돌아간다. focus를 주면 그 위치, 아니면 지금 문제의 목록(등급 또는 과정 화면)을 연다.
func home(focus := {}) -> void:
	if focus.is_empty() and editing_route_id != "" and current_route_id == editing_route_id:
		current_route_id = ""
		get_tree().change_scene_to_file(EDITOR_SCENE)
		return
	if not focus.is_empty():
		home_focus = focus
	elif current_route_id != "":
		home_focus = get_flow().list_target(current_route_id)
	current_route_id = ""
	get_tree().change_scene_to_file(HOME_SCENE)


func finish_clear(seconds: float, falls: int, extra := {}) -> Dictionary:
	var res := get_flow().finish_clear(seconds, falls, extra)
	# 받은 공유 문제를 완등하면 서버에 완등 기록(별 자격·완등 수). 실패해도 게임은 그대로.
	if current_route_id.begins_with("S_") and share().enabled():
		var meta: Dictionary = SharedRoutes.load_entry(current_route_id.trim_prefix("S_")).get("meta", {})
		if str(meta.get("id", "")) != "":
			share().rows(func(): return share().api.record_clear(str(meta.id), int(meta.get("version", 1))))
	return res


func finish_tutorial() -> bool:
	return get_flow().finish_tutorial()


func skip_basic() -> bool:
	return get_flow().skip_basic()


func allowed_buttons_for(route: RouteDef, tutorial: TutorialRunner = null) -> Array[StringName]:
	return get_flow().allowed_buttons_for(route, tutorial)
