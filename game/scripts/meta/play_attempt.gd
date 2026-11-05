class_name PlayAttempt
extends RefCounted
## 플레이 한 번(시도)의 시간·추락 수(docs/18). 노드 없음.
## 시도는 문제를 열 때, [다시], 추락 뒤 자동 재시작(respawn)마다 새로 시작한다(Ruling I).
## 시간은 일시정지·기술 고르는 중에는 흐르지 않는다. 튜토리얼 단계는 멈춤 없이 바로 시작한다(사용자 결정 2026-11-04).

var seconds := 0.0
var falls_from := 0   # 이 시도가 시작될 때의 session.falls


## 새 시도. session_falls는 지금 session.falls.
func start(session_falls: int) -> void:
	seconds = 0.0
	falls_from = session_falls


## 이 시도에서의 추락 수.
func falls(session_falls: int) -> int:
	return session_falls - falls_from


## 세션 틱 결과를 본다. respawn이면 새 시도.
func on_result(result: String, session_falls: int) -> void:
	if result == "respawn":
		start(session_falls)


## 진행한 틱의 시간을 더한다. 고르는 중이면 0초(돌려주는 값도 그 dt — 튜토리얼 observe에 넘긴다).
func tick(dt: float, selecting: bool) -> float:
	var d := 0.0 if selecting else dt
	seconds += d
	return d


## 단계에서 반짝여 표시할 홀드: mark_slot(목표가 이벤트일 때 따로 지정)이 있으면 그것,
## 없으면 goal_event.slot. route에 없으면 "".
static func goal_slot(step: Dictionary, route: RouteDef) -> String:
	var key := str(step.get("mark_slot", step.get("goal_event", {}).get("slot", "")))
	return key if key != "" and route.slots.has(key) else ""
