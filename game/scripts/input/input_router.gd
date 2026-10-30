class_name InputRouter
extends RefCounted
## docs/03 입력 소유권 계약. 터치 이벤트를 팔다리 명령으로 바꾼다. 노드에 의존하지 않는다.
## 명령: {type: "arm"|"detach"|"move"|"release"|"cancel", limb, delta(Vector2, 월드 m)}
## - 패드 안에서 시작한 터치만 배정, 같은 패드의 두 번째 터치·중앙 시작 터치는 무시
## - 터치 종료까지 소유권 유지(패드 밖으로 나가도), 데드존은 시작점부터의 직선 거리
## - 취소(cancel_all)는 정상 release로 전달하지 않는다

var pads := {}          # limb -> {center: Vector2 px, radius: float px}
var deadzone_px := 10.0
var sensitivity := 1.0
var generation := 0
var _bindings := {}     # touch index -> {limb, origin, last, dragging, pad_px}
var _gesture_seq := 0


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
	if limb == &"" or _limb_bound(limb):
		return []
	_gesture_seq += 1
	_bindings[index] = {"limb": limb, "origin": pos, "last": pos, "dragging": not attached_now, "pad_px": pads[limb].radius * 2.0, "gesture": _gesture_seq}
	return [{"type": "arm" if attached_now else "detach", "limb": limb}]


func touch_drag(index: int, pos: Vector2) -> Array:
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
	out.append({"type": "move", "limb": b.limb, "delta": to_world(screen_delta, b.pad_px)})
	return out


func touch_up(index: int) -> Array:
	if not _bindings.has(index):
		return []
	var b: Dictionary = _bindings[index]
	_bindings.erase(index)
	return [{"type": "release" if b.dragging else "disarm", "limb": b.limb}]


## 시스템 중단·창 전환. 모든 소유권을 지우고 세대를 올린다.
func cancel_all() -> Array:
	var out := []
	for b in _bindings.values():
		out.append({"type": "cancel", "limb": b.limb})
	_bindings.clear()
	generation += 1
	return out


## 패드 지름만큼 움직이면 월드 1.0m(감도 1). 화면 Y 아래 → 월드 Y 위로 뒤집는다.
func to_world(screen_delta: Vector2, pad_diameter_px: float) -> Vector2:
	return Vector2(screen_delta.x, -screen_delta.y) * sensitivity / pad_diameter_px
