class_name Progress
extends RefCounted
## docs/28 §5.3·§6·§7.2·§9 진행 기록과 해금 계산. 해금은 저장하지 않고 기록에서 매번 계산한다.
## 해금은 보이는 버튼·열리는 문제만 바꾸며 판정 수치에는 영향이 없다.

const SCHEMA_VERSION := 1
const BASIC_COURSE := "C_BASIC"
const BASIC_TUTORIAL := "C_BASIC_T"   # courses.json의 C_BASIC 튜토리얼 route_id
const GRADE_CLEAR_NEEDED := 2   # 다음 등급을 여는 완등 수
const SLOT_ORDER: Array[String] = ["tutorial", "easy", "normal", "hard"]
const TEXT_FIRST_RUN := "기본 조작을 먼저 해 주세요"
const TEXT_PREV_STEP := "앞 단계를 먼저 깨 주세요"

var seq := 0
var cleared := {}   # route_id -> {content_version, no_fall, time, best_seconds}
var tutorials := {}   # route_id -> true
var basic_skipped := false
var last_tab := "general"
## 플레이 난이도(2026-11-08): "" 아직 안 고름, "beginner" 초급(떨어지기 직전 슬로우모션), "intermediate" 중급(그대로).
var level := ""
var look := {}  # 캐릭터 외형 {body, hair, top, bottom, chalk, shoes}(docs/34 §7). 비면 기본(남성 기본 조합)
var seen_tips: Array = []  # 처음 한 번 안내를 본 것(docs/33 §5). 진행 초기화 때 함께 지운다
const LEVELS: Array[String] = ["beginner", "intermediate", "advanced"]  # advanced 고급(2026-11-10): 경고·알림 없음


## 을/를 조사. 마지막 한글 음절에 받침이 있으면 "을", 없으면 "를".
static func object_particle(word: String) -> String:
	for i in range(word.length() - 1, -1, -1):
		var c := word.unicode_at(i)
		if c >= 0xAC00 and c <= 0xD7A3:
			return "을" if (c - 0xAC00) % 28 != 0 else "를"
	return "를"


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "seq": seq, "cleared": cleared, "tutorials": tutorials,
		"basic_skipped": basic_skipped, "last_tab": last_tab, "level": level, "seen_tips": seen_tips, "look": look}


static func from_dict(d: Dictionary) -> Progress:
	var p := Progress.new()
	p.seq = int(d.get("seq", 0))
	p.cleared = d.get("cleared", {}).duplicate(true)
	p.tutorials = d.get("tutorials", {}).duplicate(true)
	p.basic_skipped = bool(d.get("basic_skipped", false))
	p.last_tab = str(d.get("last_tab", "general"))
	p.level = str(d.get("level", ""))
	p.seen_tips = Array(d.get("seen_tips", [])).map(func(x): return str(x))
	var lk = d.get("look", {})
	p.look = lk.duplicate() if lk is Dictionary else {}
	if not p.level in LEVELS:
		p.level = ""
	return p


## 첫 실행 잠금: 기본 조작 튜토리얼이 있는데 아직 안 깼고 건너뛰지도 않았을 때만.
## 튜토리얼이 없으면(2026-11-11 사용자: 튜토리얼을 모두 지우고 하나씩 다시 만듦) 잠그지 않는다.
func first_run_locked(index: ContentIndex) -> bool:
	return is_first_run() and index != null and index.route(BASIC_TUTORIAL) != null


## C_BASIC 튜토리얼 미완료이고 건너뜀도 아님.
func is_first_run() -> bool:
	if basic_skipped:
		return false
	return not tutorials.has(BASIC_TUTORIAL)


func is_cleared(route_id: String) -> bool:
	return cleared.has(route_id)


func tutorial_done(route_id: String) -> bool:
	return tutorials.has(route_id)


## 그 등급 문제 중 완등한 개수.
func cleared_count(grade: String, index: ContentIndex) -> int:
	var n := 0
	for r in index.general(grade):
		if cleared.has(r.route_id):
			n += 1
	return n


## 다음 등급을 여는 앞 등급: 그 등급보다 낮은 등급 중 문제가 있는 가장 가까운 등급("" = 없음).
## 문제가 없는 등급은 건너뛴다(V1이 비어 있으면 V2는 V0 완등으로 열린다).
func prerequisite_grade(grade: String, index: ContentIndex) -> String:
	for m in range(grade.substr(1).to_int() - 1, -1, -1):
		if not index.general("V%d" % m).is_empty():
			return "V%d" % m
	return ""


## 앞 등급에서 필요한 완등 수: 2개, 그 등급 문제가 2개보다 적으면 전부.
func clears_needed(prev: String, index: ContentIndex) -> int:
	return mini(GRADE_CLEAR_NEEDED, index.general(prev).size())


func grade_unlocked(grade: String, index: ContentIndex) -> bool:
	var n := grade.substr(1).to_int()
	var prev := prerequisite_grade(grade, index) if n > 0 else ""
	if prev == "":
		return not first_run_locked(index)
	return cleared_count(prev, index) >= clears_needed(prev, index)


func grade_lock_text(grade: String, index: ContentIndex) -> String:
	if grade_unlocked(grade, index):
		return ""
	var n := grade.substr(1).to_int()
	var prev := prerequisite_grade(grade, index) if n > 0 else ""
	if prev == "":
		return TEXT_FIRST_RUN
	return "%s에서 %d개 더 완등하면 열려요" % [prev, clears_needed(prev, index) - cleared_count(prev, index)]


## 튜토리얼을 마친 버튼 과정의 버튼 기술.
func unlocked_buttons(index: ContentIndex) -> Array[StringName]:
	var out: Array[StringName] = []
	var buttons := TechniqueDefs.button_ids()
	for c in index.courses():
		if c.kind != "button" or not tutorials.has(c.tutorial):
			continue
		for t in c.techniques:
			if t in buttons and not out.has(t):
				out.append(t)
	return out


## "" 이면 열림.
func route_lock_text(route: RouteDef, index: ContentIndex) -> String:
	if route.mode == "course":
		if route.course_id == BASIC_COURSE and route.course_slot == "tutorial":
			return ""
		if first_run_locked(index):
			return TEXT_FIRST_RUN
		return "" if _previous_step_done(route, index) else TEXT_PREV_STEP
	var g := grade_lock_text(route.grade, index)
	if g != "":
		return g
	var open := unlocked_buttons(index)
	var buttons := TechniqueDefs.button_ids()
	for t in route.required_techniques:
		if t in buttons and not t in open:
			var name: String = str(TechniqueJudge.defs()[t].name_ko)
			return "%s%s 배우면 열려요" % [name, object_particle(name)]
	return ""


func _previous_step_done(route: RouteDef, index: ContentIndex) -> bool:
	var slot := SLOT_ORDER.find(route.course_slot)
	if slot <= 0:
		return true
	var course := index.course(route.course_id)
	var prev_slot: String = SLOT_ORDER[slot - 1]
	if prev_slot == "tutorial":
		return tutorials.has(course.get("tutorial", ""))
	for id in course.get("problems", []):
		var r := index.route(id)
		if r != null and r.course_slot == prev_slot:
			return cleared.has(id)
	return true


func record_clear(route: RouteDef, seconds: float, falls: int) -> void:
	var old: Dictionary = cleared.get(route.route_id, {})
	var best := seconds
	if old.has("best_seconds"):
		best = minf(float(old.best_seconds), seconds)
	cleared[route.route_id] = {
		"content_version": route.content_version,
		"no_fall": bool(old.get("no_fall", false)) or falls == 0,
		"time": bool(old.get("time", false)) or (route.time_medal_seconds > 0.0 and seconds <= route.time_medal_seconds),
		"best_seconds": best,
	}


func record_tutorial(route_id: String) -> void:
	tutorials[route_id] = true


func skip_basic() -> void:
	basic_skipped = true
