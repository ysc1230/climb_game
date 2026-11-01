class_name PlayAttempt
extends RefCounted
## 플레이 한 번(시도)의 시간·추락 수와 튜토리얼 "보기" 상태(docs/28 §6.1, docs/18). 노드 없음.
## 시도는 문제를 열 때, [다시], 추락 뒤 자동 재시작(respawn)마다 새로 시작한다(Ruling I).
## 시간은 일시정지·기술 고르는 중·보기 상태에서는 흐르지 않는다.

var seconds := 0.0
var falls_from := 0   # 이 시도가 시작될 때의 session.falls
## 튜토리얼 단계 "보기": 시간이 멈추고(세션을 진행하지 않음) 화면을 누르면 시작.
var intro := false


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


## 이번 틱에 세션을 진행할지. 보기 상태면 false.
func blocks_tick() -> bool:
	return intro


## 진행한 틱의 시간을 더한다. 고르는 중이면 0초(돌려주는 값도 그 dt — 튜토리얼 observe에 넘긴다).
func tick(dt: float, selecting: bool) -> float:
	var d := 0.0 if selecting or intro else dt
	seconds += d
	return d


func begin_intro() -> void:
	intro = true


## 보기를 끝내고 단계를 시작한다. 보기 중이었으면 true.
func end_intro() -> bool:
	var was := intro
	intro = false
	return was


## 단계 목표가 가리키는 홀드(goal_event.slot이 route에 있으면 그 키, 없으면 "").
static func intro_slot(step: Dictionary, route: RouteDef) -> String:
	var key := str(step.get("goal_event", {}).get("slot", ""))
	return key if key != "" and route.slots.has(key) else ""
