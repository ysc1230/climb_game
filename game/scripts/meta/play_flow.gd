class_name PlayFlow
extends RefCounted
## 홈과 플레이를 잇는 노드 없는 흐름(docs/28 §5). 자동 로드 Game이 이것을 들고 장면만 바꾼다.
## 모드별 보이는 기술 버튼(§5.5), 완등·튜토리얼 기록과 저장(§9), [다음]·[목록] 위치를 정한다.
## 해금은 보이는 버튼만 바꾸며 판정 수치에는 영향이 없다.

var index: ContentIndex
var progress: Progress
var save_path := SaveStore.DEFAULT_PATH
var current_route_id := ""


func _init(p_index: ContentIndex, p_progress: Progress, p_save_path := SaveStore.DEFAULT_PATH) -> void:
	index = p_index
	progress = p_progress
	save_path = p_save_path


func current_route() -> RouteDef:
	return index.route(current_route_id) if current_route_id != "" else null


## 플레이 중 기술 패널에 보일 버튼 기술(§5.5).
## 일반: 해금된 버튼. 과정 튜토리얼: 그 과정 기술만(지금 단계에 rules.techniques가 있으면 그것). 과정 문제: 과정 기술 ∪ 해금.
func allowed_buttons_for(route: RouteDef, tutorial: TutorialRunner = null) -> Array[StringName]:
	var out: Array[StringName] = []
	if route == null:
		return out
	if route.mode != "course":
		return progress.unlocked_buttons(index)
	if route.course_slot == "tutorial":
		if tutorial != null and tutorial.current().get("rules", {}).has("techniques"):
			return tutorial.allowed_buttons()
		return _course_buttons(route.course_id)
	out = _course_buttons(route.course_id)
	for t in progress.unlocked_buttons(index):
		if not out.has(t):
			out.append(t)
	return out


func _course_buttons(course_id: String) -> Array[StringName]:
	var out: Array[StringName] = []
	var buttons := TechniqueDefs.button_ids()
	for t in index.course(course_id).get("techniques", []):
		if t in buttons and not out.has(t):
			out.append(t)
	return out


## 지금 문제 완등을 기록하고 저장한다. 이번 시도의 메달 {cleared, no_fall, time, seconds, falls, saved}를 돌려준다.
## 튜토리얼(메달 없음)과 없는 문제는 기록하지 않고 빈 사전.
func finish_clear(seconds: float, falls: int) -> Dictionary:
	var route := current_route()
	if route == null or route.course_slot == "tutorial":
		return {}
	progress.record_clear(route, seconds, falls)
	return {
		"cleared": true,
		"no_fall": falls == 0,
		"time": route.time_medal_seconds > 0.0 and seconds <= route.time_medal_seconds,
		"seconds": seconds,
		"falls": falls,
		"saved": SaveStore.save(progress, save_path),
	}


## 지금 튜토리얼 완료를 기록하고 저장한다.
func finish_tutorial() -> bool:
	if current_route_id == "":
		return false
	progress.record_tutorial(current_route_id)
	return SaveStore.save(progress, save_path)


func skip_basic() -> bool:
	progress.skip_basic()
	return SaveStore.save(progress, save_path)


## 캐릭터 외형을 저장한다(docs/34 §7).
func set_look(look: Dictionary) -> void:
	if progress.look == look:
		return
	progress.look = look.duplicate()
	SaveStore.save(progress, save_path)


## 처음 한 번 안내를 봤다고 저장한다(docs/33 §5).
func mark_tip(id: String) -> void:
	if progress.seen_tips.has(id):
		return
	progress.seen_tips.append(id)
	SaveStore.save(progress, save_path)


## 처음 배우기 수업 순서(docs/42 §4.2). 튜토리얼 완료 화면의 [다음: 수업]이 이 순서를 따른다.
const BASIC_SEQUENCE: Array[String] = ["C_BASIC", "C_FEET", "C_BODY", "C_ARM"]


## route_id가 기본 과정 튜토리얼이면 다음 기본 과정 튜토리얼 {route_id, name}. 마지막이거나 아니면 {}.
func next_basic_tutorial(route_id: String) -> Dictionary:
	var r := index.route(route_id)
	if r == null or r.mode != "course":
		return {}
	var i := BASIC_SEQUENCE.find(r.course_id)
	if i < 0 or i + 1 >= BASIC_SEQUENCE.size():
		return {}
	var c := index.course(BASIC_SEQUENCE[i + 1])
	var tid := str(c.get("tutorial", ""))
	if tid == "" or index.route(tid) == null:
		return {}
	return {"route_id": tid, "name": str(c.get("name_ko", ""))}


## 난이도(초급·중급)를 고르고 저장한다. 모르는 값은 무시.
func set_level(level: String) -> void:
	if not level in Progress.LEVELS or progress.level == level:
		return
	progress.level = level
	SaveStore.save(progress, save_path)


## 초급 도움(버틸 시간 10배·해결 안내·되돌리기, play_test)을 켜는가.
func level() -> String:
	return progress.level if progress.level in Progress.LEVELS else "intermediate"


func beginner_assist() -> bool:
	return progress.level == "beginner"


func set_last_tab(tab: String) -> void:
	if progress.last_tab == tab:
		return
	progress.last_tab = tab
	SaveStore.save(progress, save_path)


## 같은 목록에서 다음 문제 ID(일반: 같은 등급 다음 order, 과정: 다음 슬롯). 파일이 없으면 "".
## 잠김 여부는 보지 않는다(부르는 쪽이 progress.route_lock_text로 확인).
func next_route_id(route_id: String) -> String:
	var r := index.route(route_id)
	if r == null:
		return ""
	if r.mode != "course":
		var list := index.general(r.grade)
		for i in list.size():
			if list[i].route_id == route_id:
				return list[i + 1].route_id if i + 1 < list.size() else ""
		return ""
	var course := index.course(r.course_id)
	var slot := Progress.SLOT_ORDER.find(r.course_slot)
	if slot < 0 or slot + 1 >= Progress.SLOT_ORDER.size():
		return ""
	var want: String = Progress.SLOT_ORDER[slot + 1]
	for id in course.get("problems", []):
		var p := index.route(id)
		if p != null and p.course_slot == want:
			return id
	return ""


## [목록]이 돌아갈 홈 위치: 일반 {tab, grade} / 과정 {tab, course}.
func list_target(route_id: String) -> Dictionary:
	var r := index.route(route_id)
	if r == null:
		return {"tab": progress.last_tab}
	if r.mode == "course":
		return {"tab": "technique", "course": r.course_id}
	return {"tab": "general", "grade": r.grade}
