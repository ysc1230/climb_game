class_name Progress
extends RefCounted
## docs/28 §5.3·§6·§7.2·§9 진행 기록과 해금 계산. 해금은 저장하지 않고 기록에서 매번 계산한다.
## 해금은 보이는 버튼·열리는 문제만 바꾸며 판정 수치에는 영향이 없다.

const SCHEMA_VERSION := 2  # 2(2026-11-20 작업 3): stats 추가, cleared에 점수·플래시·고스트·이전 판. 판 1도 읽는다
const FALL_HEIGHTS_MAX := 20
const BASIC_COURSE := "C_BASIC"
const BASIC_TUTORIAL := "C_BASIC_T"   # courses.json의 C_BASIC 튜토리얼 route_id
const GRADE_CLEAR_NEEDED := 2   # 다음 등급을 여는 완등 수
const SLOT_ORDER: Array[String] = ["tutorial", "easy", "normal", "hard"]
const TEXT_FIRST_RUN := "기본 조작을 먼저 해 주세요"
const TEXT_PREV_STEP := "앞 단계를 먼저 깨 주세요"

var seq := 0
## route_id -> {content_version, no_fall, time, best_seconds, best_score, best_score_parts, flash, ghost, prev}(완등한 문제만 — 키가 있으면 완등)
## 최고 기록(best_*·flash·ghost)은 도움 없는 시도만. prev: 문제가 바뀌기 전 판의 {best_score, best_seconds, flash}.
var cleared := {}
## route_id -> {content_version, attempts, falls, fall_heights}(시도한 모든 문제, 작업 3). 판정·해금에 쓰지 않는다.
var stats := {}
var tutorials := {}   # route_id -> true
var basic_skipped := false
var last_tab := "general"
## 플레이 난이도(2026-11-08): "" 아직 안 고름, "beginner" 초급(떨어지기 직전 슬로우모션), "intermediate" 중급(그대로).
var level := ""
var look := {}  # 캐릭터 외형 {body, hair, top, bottom, chalk, shoes}(docs/34 §7). 비면 기본(남성 기본 조합)
## 화면 표시 켜고 끄기(설정 탭, docs/49 v0.2). 키가 없으면 DISPLAY_DEFAULTS.
const DISPLAY_DEFAULTS := {"balance": true, "loads": false, "balance_hint": true, "dev_info": false, "ghost": true, "ai_ghost": false}
var display := {}
## 몸 옮기기(작업 2, docs/superpowers/specs/2026-11-19-2-tilt-design.md). body: "drag" 가운데 끌기 | "tilt" 휴대폰 기울이기.
## tilt_sens 1~10, tilt_dead 반응 시작 각도 0~20°, tilt_with_drag 기울이기 중에도 가운데 끌기. 키가 없으면 CONTROL_DEFAULTS.
## 기본 민감도 5·각도 10°(2026-11-20 사용자).
const CONTROL_DEFAULTS := {"body": "drag", "tilt_sens": 5, "tilt_dead": 10.0, "tilt_with_drag": true}
const TILT_SENS_MAX := 10
const TILT_DEAD_MAX := 20.0
var control := {}
## 만들기(작업 6): 올린 내 문제 route_id → {code, visibility, version}, 별명(비면 처음 공유할 때 "클라이머1234"처럼 정함), 받은 공유 문제의 별.
var shared := {}
var nickname := ""
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
		"basic_skipped": basic_skipped, "last_tab": last_tab, "level": level, "seen_tips": seen_tips, "look": look, "display": display, "control": control, "stats": stats,
		"shared": shared, "nickname": nickname}


static func from_dict(d: Dictionary) -> Progress:
	var p := Progress.new()
	p.seq = int(d.get("seq", 0))
	p.cleared = d.get("cleared", {}).duplicate(true)
	p.tutorials = d.get("tutorials", {}).duplicate(true)
	var st = d.get("stats", {})
	p.stats = st.duplicate(true) if st is Dictionary else {}
	p.basic_skipped = bool(d.get("basic_skipped", false))
	p.last_tab = str(d.get("last_tab", "general"))
	p.level = str(d.get("level", ""))
	p.seen_tips = Array(d.get("seen_tips", [])).map(func(x): return str(x))
	var dp = d.get("display", {})
	if dp is Dictionary:
		for key in dp:
			if DISPLAY_DEFAULTS.has(str(key)):
				p.display[str(key)] = bool(dp[key])
	var ct = d.get("control", {})
	if ct is Dictionary:
		for key in ct:
			p.set_control(str(key), ct[key])
	var sh = d.get("shared", {})
	p.shared = sh.duplicate(true) if sh is Dictionary else {}
	p.nickname = str(d.get("nickname", "")).substr(0, 12)
	var lk = d.get("look", {})
	p.look = lk.duplicate() if lk is Dictionary else {}
	if not p.level in LEVELS:
		p.level = ""
	return p


func control_get(key: String) -> Variant:
	return control.get(key, CONTROL_DEFAULTS.get(key))


## 몸 옮기기 설정 하나. 모르는 키·값은 버리고 숫자는 범위로 자른다.
func set_control(key: String, value: Variant) -> void:
	match key:
		"body":
			if str(value) in ["drag", "tilt"]:
				control[key] = str(value)
		"tilt_sens":
			control[key] = clampi(int(value), 1, TILT_SENS_MAX)
		"tilt_dead":
			control[key] = clampf(float(value), 0.0, TILT_DEAD_MAX)
		"tilt_with_drag":
			control[key] = bool(value)


## 화면 표시가 켜져 있는가(설정 탭).
func display_on(key: String) -> bool:
	return bool(display.get(key, DISPLAY_DEFAULTS.get(key, false)))


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


## 그 등급 문제를 하나라도 완등했으면 계속 열림(작업 5 §5.4: 새 등급이 생겨 앞 등급이 바뀌어도 하던 등급이 다시 잠기지 않게).
func grade_unlocked(grade: String, index: ContentIndex) -> bool:
	if cleared_count(grade, index) > 0:
		return true
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


## 완등 기록. extra: {score, parts, helped, ghost}(작업 3). falls는 문제를 연 뒤 추락 수(무추락 메달).
## 돌려줌: {flash, new_best_score, new_best_time}. 도움 시도는 완등만 남기고 최고 기록·플래시·고스트는 건드리지 않는다.
func record_clear(route: RouteDef, seconds: float, falls: int, extra := {}) -> Dictionary:
	var old: Dictionary = cleared.get(route.route_id, {})
	var c := {}
	if not old.is_empty() and int(old.get("content_version", route.content_version)) != route.content_version:
		var prev := {}
		for k in ["best_score", "best_seconds", "flash"]:
			if old.has(k):
				prev[k] = old[k]
		c = {"prev": prev}  # 문제가 바뀜: 이전 판 기록으로 옮기고 새로 잰다(고스트는 홀드가 달라 지움)
	else:
		c = old.duplicate(true)
	c["content_version"] = route.content_version
	c["no_fall"] = bool(c.get("no_fall", false)) or falls == 0
	c["time"] = bool(c.get("time", false)) or (route.time_medal_seconds > 0.0 and seconds <= route.time_medal_seconds)
	var res := {"flash": false, "new_best_score": false, "new_best_time": false}
	if not bool(extra.get("helped", false)):
		if not c.has("best_seconds") or seconds < float(c.best_seconds):
			c["best_seconds"] = seconds
			res.new_best_time = true
			if extra.has("ghost"):
				c["ghost"] = extra.ghost
		if extra.has("score") and (not c.has("best_score") or float(extra.score) > float(c.best_score)):
			c["best_score"] = snappedf(float(extra.score), 0.01)
			c["best_score_parts"] = extra.get("parts", {})
			res.new_best_score = true
		if int(stats.get(route.route_id, {}).get("attempts", 0)) == 1:
			c["flash"] = true
			res.flash = true
	cleared[route.route_id] = c
	return res


## 새 시도 시작(문제를 열 때·[다시]·떨어진 뒤 다시). 돌려줌: 그 문제의 시도 수. 문제가 바뀌었으면 통계를 0부터.
func start_attempt(route: RouteDef) -> int:
	var s := _stats(route)
	s.attempts = int(s.attempts) + 1
	return int(s.attempts)


## 떨어짐 하나와 그 시도에서 가장 높이 올라간 골반 높이(힌트·시범 보기).
func record_fall(route: RouteDef, height: float) -> void:
	var s := _stats(route)
	s.falls = int(s.falls) + 1
	var hs: Array = s.fall_heights
	hs.append(snappedf(height, 0.01))
	while hs.size() > FALL_HEIGHTS_MAX:
		hs.pop_front()


func fall_count(route_id: String) -> int:
	return int(stats.get(route_id, {}).get("falls", 0))


func _stats(route: RouteDef) -> Dictionary:
	var s: Dictionary = stats.get(route.route_id, {})
	if s.is_empty() or int(s.get("content_version", route.content_version)) != route.content_version:
		s = {"content_version": route.content_version, "attempts": 0, "falls": 0, "fall_heights": []}
		stats[route.route_id] = s
	return s


## 이 문제 기록 지우기(작업 3 §3.3): 완등·최고 기록·고스트·시도 통계. 해금은 기록에서 다시 계산된다.
func wipe_route(route_id: String) -> void:
	cleared.erase(route_id)
	stats.erase(route_id)


func record_tutorial(route_id: String) -> void:
	tutorials[route_id] = true


func skip_basic() -> void:
	basic_skipped = true
