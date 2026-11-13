class_name InputRouter
extends RefCounted
## docs/03 입력 소유권 계약. 터치 이벤트를 팔다리 명령으로 바꾼다. 노드에 의존하지 않는다.
## 명령: {type: "arm"|"detach"|"move"|"release"|"cancel", limb, delta(Vector2, 월드 m)}
## - release에는 speed(m/s, 월드): 놓기 직전 0.1초 동안의 손가락 이동 경로 길이 / 0.1 (세션은 지금 쓰지 않음, 데드포인트 제거)
## - 패드 안에서 시작한 터치만 배정, 같은 패드의 두 번째 터치·중앙 시작 터치는 무시
## - 터치 종료까지 소유권 유지(패드 밖으로 나가도), 데드존은 시작점부터의 직선 거리
## - 취소(cancel_all)는 정상 release로 전달하지 않는다

var pads := {}          # limb -> {center: Vector2 px, radius: float px}
var deadzone_px := 10.0
var sensitivity := 1.0
var generation := 0
var _bindings := {}     # touch index -> {limb, origin, last, dragging, pad_px}
var _gesture_seq := 0
## 몸통 끌기 영역(docs/03 v0.9): 네 패드 사이 가운데. 여기서 시작한 터치는 팔다리 대신 몸통(골반 목표)을 움직인다.
var body_area := Rect2()
const BODY := &"BODY"
const SPEED_WINDOW := 0.1  # 속도를 재는 구간(초)


func set_pad(limb: StringName, center: Vector2, diameter_px: float) -> void:
	pads[limb] = {"center": center, "radius": diameter_px * 0.5}


func owner_of(index: int) -> StringName:
	return _bindings[index].limb if _bindings.has(index) else &""


func active_limbs() -> Array:
	return _bindings.values().map(func(b): return b.limb)


func _limb_bound(limb: StringName) -> bool:
	for b in _bindings.values():
		if b.limb == limb:
			return true
	return false


func _pad_at(pos: Vector2) -> StringName:
	for limb in pads:
		if pos.distance_to(pads[limb].center) <= pads[limb].radius:
			return limb
	return &""


## attached_now: 누를 때 팔다리가 슬롯에 붙어 있는지. 붙어 있으면 arm, 아니면 바로 Dragging.
func touch_down(index: int, pos: Vector2, attached_now: bool) -> Array:
	if _bindings.has(index):
		return []
	var limb := _pad_at(pos)
	if limb == &"" and body_area.has_point(pos) and not _limb_bound(BODY):
		_gesture_seq += 1
		_bindings[index] = {"limb": BODY, "origin": pos, "last": pos, "dragging": true, "moves": [], "pad_px": _body_pad_px(), "gesture": _gesture_seq}
		return [{"type": "body_start", "limb": BODY}]
	if limb == &"" or _limb_bound(limb):
		return []
	_gesture_seq += 1
	_bindings[index] = {"limb": limb, "origin": pos, "last": pos, "dragging": not attached_now, "moves": [], "pad_px": pads[limb].radius * 2.0, "gesture": _gesture_seq}
	return [{"type": "arm" if attached_now else "detach", "limb": limb}]


## 패드 그림의 손잡이 위치(패드 가운데 기준 px, 반지름 안): 그 패드를 누르고 있는 손가락. 없으면 null. 표시만.
func knob(limb: StringName):
	for b in _bindings.values():
		if b.limb == limb:
			return (b.last - pads[limb].center).limit_length(pads[limb].radius)
	return null


## time_s: 이벤트 시각(초). 생략하면 엔진 시계를 쓴다(시험은 직접 넣는다).
func touch_drag(index: int, pos: Vector2, time_s: float = -1.0) -> Array:
	if not _bindings.has(index):
		return []
	var b: Dictionary = _bindings[index]
	var out := []
	var screen_delta := Vector2.ZERO
	if not b.dragging:
		var from_origin: Vector2 = pos - b.origin
		if from_origin.length() <= deadzone_px:
			b.last = pos
			return []
		b.dragging = true
		out.append({"type": "detach", "limb": b.limb})
		screen_delta = from_origin - from_origin.normalized() * deadzone_px
	else:
		screen_delta = pos - b.last
	b.last = pos
	var world_delta := to_world(screen_delta, b.pad_px)
	var now := _now(time_s)
	b.moves.append({"t": now, "len": world_delta.length()})
	while b.moves.size() > 0 and b.moves[0].t < now - 1.0:
		b.moves.pop_front()
	out.append({"type": "body_move" if b.limb == BODY else "move", "limb": b.limb, "delta": world_delta})
	return out


func touch_up(index: int, time_s: float = -1.0) -> Array:
	if not _bindings.has(index):
		return []
	var b: Dictionary = _bindings[index]
	_bindings.erase(index)
	if b.limb == BODY:
		return [{"type": "body_end", "limb": BODY}]
	if not b.dragging:
		return [{"type": "disarm", "limb": b.limb}]
	var now := _now(time_s)
	# 속도 = 놓기 직전 0.1초 구간에 들어온 drag 이동량(월드)의 경로 길이 합 / 0.1 (끝점 변위가 아니라 경로 길이)
	var path := 0.0
	for m in b.moves:
		if m.t >= now - SPEED_WINDOW:
			path += m.len
	return [{"type": "release", "limb": b.limb, "speed": path / SPEED_WINDOW}]


func _now(time_s: float) -> float:
	return time_s if time_s >= 0.0 else Time.get_ticks_msec() * 0.001


## 시스템 중단·창 전환. 모든 소유권을 지우고 세대를 올린다.
func cancel_all() -> Array:
	var out := []
	for b in _bindings.values():
		out.append({"type": "body_end" if b.limb == BODY else "cancel", "limb": b.limb})
	_bindings.clear()
	generation += 1
	return out


## 패드 지름만큼 움직이면 월드 1.0m(감도 1). 화면 Y 아래 → 월드 Y 위로 뒤집는다.
func to_world(screen_delta: Vector2, pad_diameter_px: float) -> Vector2:
	return Vector2(screen_delta.x, -screen_delta.y) * sensitivity / pad_diameter_px


## 몸통 끌기의 화면→월드 환산 기준: 패드 지름(패드와 같은 감도). 패드가 없으면 200px.
func _body_pad_px() -> float:
	for limb in pads:
		return pads[limb].radius * 2.0
	return 200.0
