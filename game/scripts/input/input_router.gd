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
## 다이노(Tuning.DYNO_*): 몸 영역을 탭하고 DYNO_DOUBLE_TAP 안에 다시 누른 터치는 다이노 준비 터치다.
## 명령: dyno_start / dyno_move(delta 월드) / dyno_end.
const DYNO := &"DYNO"
var _last_body_up := -INF
## 두 손가락 시점(오버행 실험, 2026-11-22 사용자: 오르면서 시점 돌리기): camera_enabled면 가운데에 둘째 손가락이 올 때
## 몸 옮기기를 끝내고 두 손가락 모두 시점 터치가 된다. 명령: cam_start / cam_orbit(delta 화면 px, 두 손가락 중점 이동) /
## cam_zoom(ratio = 이전 거리 / 지금 거리, 벌리면 1보다 작음 = 가까이). 한 손가락만 남아도 뗄 때까지 시점 터치.
const CAM := &"CAM"
var camera_enabled := false
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
func touch_down(index: int, pos: Vector2, attached_now: bool, time_s: float = -1.0) -> Array:
	if _bindings.has(index):
		return []
	var limb := _pad_at(pos)
	if camera_enabled and limb == &"" and body_area.has_point(pos) and (_limb_bound(BODY) or _limb_bound(CAM)):
		var out := []
		for i in _bindings:
			if _bindings[i].limb == BODY:
				_bindings[i].limb = CAM
				out.append({"type": "body_end", "limb": BODY})
		if _bindings.values().filter(func(x): return x.limb == CAM).size() >= 2:
			return out  # 시점은 두 손가락까지
		_gesture_seq += 1
		_bindings[index] = {"limb": CAM, "origin": pos, "last": pos, "dragging": true, "moves": [], "pad_px": _body_pad_px(), "gesture": _gesture_seq}
		out.append({"type": "cam_start", "limb": CAM})
		return out
	if limb == &"" and body_area.has_point(pos) and not _limb_bound(BODY) and not _limb_bound(DYNO) and _now(time_s) - _last_body_up <= Tuning.DYNO_DOUBLE_TAP:
		_gesture_seq += 1
		_last_body_up = -INF
		_bindings[index] = {"limb": DYNO, "origin": pos, "last": pos, "dragging": true, "moves": [], "pad_px": _body_pad_px(), "gesture": _gesture_seq}
		return [{"type": "dyno_start", "limb": DYNO}]
	if limb == &"" and body_area.has_point(pos) and not _limb_bound(BODY):
		_gesture_seq += 1
		_bindings[index] = {"limb": BODY, "origin": pos, "last": pos, "dragging": true, "moves": [], "pad_px": _body_pad_px(), "gesture": _gesture_seq}
		return [{"type": "body_start", "limb": BODY}]
	if limb == &"" or _limb_bound(limb):
		return []
	_gesture_seq += 1
	_bindings[index] = {"limb": limb, "origin": pos, "last": pos, "dragging": not attached_now, "moves": [], "pad_px": pads[limb].radius * 2.0, "gesture": _gesture_seq}
	return [{"type": "arm" if attached_now else "detach", "limb": limb}]


## 다이노 준비 터치: {origin, last, cancel_r(px), inside(취소 원 안인가)}. 없으면 {}. 화면 표시용.
func dyno_touch() -> Dictionary:
	for b in _bindings.values():
		if b.limb == DYNO:
			var r: float = b.pad_px * Tuning.DYNO_CANCEL_ZONE
			return {"origin": b.origin, "last": b.last, "cancel_r": r, "inside": (b.last - b.origin).length() <= r}
	return {}


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
	if b.limb == CAM:
		return _cam_drag(index, pos)
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
	out.append({"type": "body_move" if b.limb == BODY else ("dyno_move" if b.limb == DYNO else "move"), "limb": b.limb, "delta": world_delta})
	return out


func touch_up(index: int, time_s: float = -1.0) -> Array:
	if not _bindings.has(index):
		return []
	var b: Dictionary = _bindings[index]
	_bindings.erase(index)
	if b.limb == CAM:
		return []
	if b.limb == BODY:
		_last_body_up = _now(time_s)
		return [{"type": "body_end", "limb": BODY}]
	if b.limb == DYNO:
		# 처음 누른 자리(취소 원) 안에서 떼면 취소(2026-11-18 사용자)
		if (b.last - b.origin).length() <= b.pad_px * Tuning.DYNO_CANCEL_ZONE:
			return [{"type": "dyno_cancel", "limb": DYNO}]
		return [{"type": "dyno_end", "limb": DYNO}]
	if not b.dragging:
		return [{"type": "disarm", "limb": b.limb}]
	var now := _now(time_s)
	# 속도 = 놓기 직전 0.1초 구간에 들어온 drag 이동량(월드)의 경로 길이 합 / 0.1 (끝점 변위가 아니라 경로 길이)
	var path := 0.0
	for m in b.moves:
		if m.t >= now - SPEED_WINDOW:
			path += m.len
	return [{"type": "release", "limb": b.limb, "speed": path / SPEED_WINDOW}]


## 시점 손가락 하나가 움직임: 두 손가락이면 중점 이동(돌리기)과 거리 변화(확대), 하나면 그 이동만 돌리기.
func _cam_drag(index: int, pos: Vector2) -> Array:
	var b: Dictionary = _bindings[index]
	var others := _bindings.keys().filter(func(i): return i != index and _bindings[i].limb == CAM)
	var out := []
	if others.is_empty():
		out.append({"type": "cam_orbit", "limb": CAM, "delta": pos - b.last})
	else:
		var o: Vector2 = _bindings[others[0]].last
		out.append({"type": "cam_orbit", "limb": CAM, "delta": (pos - b.last) * 0.5})
		var before := o.distance_to(b.last)
		var after := o.distance_to(pos)
		if before > 1.0 and after > 1.0 and absf(after - before) > 0.5:
			out.append({"type": "cam_zoom", "limb": CAM, "ratio": before / after})
	b.last = pos
	return out


func _now(time_s: float) -> float:
	return time_s if time_s >= 0.0 else Time.get_ticks_msec() * 0.001


## 시스템 중단·창 전환. 모든 소유권을 지우고 세대를 올린다.
func cancel_all() -> Array:
	var out := []
	for b in _bindings.values():
		if b.limb == CAM:
			continue
		out.append({"type": "body_end" if b.limb == BODY else ("dyno_cancel" if b.limb == DYNO else "cancel"), "limb": b.limb})
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
