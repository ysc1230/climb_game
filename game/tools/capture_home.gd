extends SceneTree
## 홈 일반 탭 확인용(작업 3): 등급 설명 카드, 문제 카드, 기록 지우기 확인 창, 홀드 사전(작업 4). 진행 기록은 메모리에서만 바꾼다(저장 안 함).
## godot --path game --resolution 1600x720 --script res://tools/capture_home.gd -- <out_prefix>

var home: Node
var frame := 0
var prefix := "user://home"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		prefix = args[0]


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s_%s.png" % [prefix, name])
	print("saved %s_%s.png" % [prefix, name])


func _process(_d: float) -> bool:
	frame += 1
	var g = root.get_node_or_null("Game")
	if frame == 1:
		g.first_run_sent = true  # 첫 실행 튜토리얼로 넘어가지 않게(홈만 찍음)
		if g.progress.level == "":
			g.progress.level = "intermediate"
		g.progress.seen_tips.erase("grade_V0")
		g.progress.cleared["G_V3_03"] = {"content_version": 2, "no_fall": true, "time": true, "flash": true, "best_score": 87, "best_seconds": 74.2}
		g.home_focus = {"tab": "general", "grade": "V0"}
		home = load("res://scenes/home.tscn").instantiate()
		root.add_child(home)
		return false
	if frame == 15:
		_shot("grade_card")
		home.grade_card = ""
		home.queue_redraw()
	if frame == 25:
		_shot("cards")
		home.wipe_ask = "G_V3_03"
		home.queue_redraw()
	if frame == 35:
		_shot("wipe")
		home.wipe_ask = ""
		home.tab = "technique"
		home.tech_view = "holds"
		home.queue_redraw()
	if frame == 45:
		_shot("holds")  # 홀드 사전(작업 4 §4.4)
		home.tab = "make"
		home.queue_redraw()
	if frame == 55:
		_shot("make")  # 만들기 탭(작업 6)
		home.make_view = "browse"
		home.browse_rows = [
			{"id": "a", "code": "AB23CD", "name": "옆으로 비껴", "grade": "V2", "author_name": "클라이머1234", "stars": 12, "clears": 30},
			{"id": "b", "code": "XY45ZW", "name": "작은 저그 길", "grade": "V4", "author_name": "벽타기", "stars": 3, "clears": 7}]
		home.my_stars = {"a": true}
		home.queue_redraw()
	if frame == 65:
		_shot("browse")  # 둘러보기(공유 서버 없이 가짜 목록)
		home.tab = "general"
		home.grade = "V3"
		home.queue_redraw()
	if frame == 75:
		_shot("v3")  # 기록이 있는 등급(메달·최고 기록·기록 지우기)
		home.tab = "technique"
		home.tech_view = "learn"
		home.queue_redraw()
	if frame == 85:
		_shot("learn")  # 기술 탭 처음 배우기(수업 카드)
		g.progress.look["body"] = OS.get_environment("BODY") if OS.get_environment("BODY") != "" else "male"
		home._do("look_open", "")
	if frame == 110:
		_shot("look")  # 캐릭터 고르기(3D 미리보기, 2026-11-22 애니 남성 확인)
		return true
	return false
