class_name TiltMapper
extends RefCounted
## 휴대폰 기울이기 → 몸(골반) 목표 옮김(docs/superpowers/specs/2026-11-19-2-tilt-design.md). 노드 없음.
## 위치 방식: 기울인 만큼 그 자리. 좌우로 기울이면 좌우, 화면 위쪽을 앞으로 숙이면 위, 뒤로 젖히면 아래.
## 기준(0°)은 첫 값 또는 recalibrate() 뒤 첫 값. 각도에는 저역 통과 필터(프레임당 FILTER 섞기).
## 중력 벡터는 화면 기준(x 오른쪽, y 위, z 화면 밖, 땅 쪽을 가리킴)으로 가정한다. Godot 안드로이드가 화면 회전에
## 맞춰 돌려 준다고 보고(screen_aligned) — 기기 확인 전. 돌려 주지 않는 기기면 orientation으로 돌린다.

const FILTER := 0.15
## 민감도 1~10 → 반응 시작 각도에서 끝까지 가는 데 더 기울일 각도(°). 1~5는 처음 값 그대로, 6~10을 더함(2026-11-20).
const RANGES := [25.0, 20.0, 15.0, 11.0, 8.0, 6.5, 5.0, 4.0, 3.0, 2.5]

var sensitivity := 5
var deadzone := 10.0
var screen_aligned := true
var orientation := DisplayServer.SCREEN_LANDSCAPE
var _ref := Vector2.ZERO
var _ang := Vector2.ZERO
var _has_ref := false


static func range_deg(sens: int) -> float:
	return RANGES[clampi(sens, 1, RANGES.size()) - 1]


static func available(g: Vector3) -> bool:
	return g.length() > 0.5


## 기기 축 → 화면 축(센서가 화면 회전을 따르지 않을 때만).
static func to_screen(g: Vector3, orient: int, aligned: bool) -> Vector3:
	if aligned:
		return g
	if orient == DisplayServer.SCREEN_REVERSE_LANDSCAPE:
		return Vector3(g.y, -g.x, g.z)
	return Vector3(-g.y, g.x, g.z)


## 화면 기준 중력 → (좌우 기울기, 앞뒤 숙임)°.
static func angles(g: Vector3) -> Vector2:
	var n := g.normalized()
	return Vector2(rad_to_deg(asin(clampf(n.x, -1.0, 1.0))), rad_to_deg(atan2(-n.z, -n.y)))


## 다음 값을 기준으로 다시 잡는다(문제 시작·다시 시작).
func recalibrate() -> void:
	_has_ref = false


## {offset: Vector2(m, 위 +), active: 반응 범위를 벗어났는가}
func update(g: Vector3) -> Dictionary:
	if not available(g):
		return {"offset": Vector2.ZERO, "active": false}
	var a := angles(to_screen(g, orientation, screen_aligned))
	if not _has_ref:
		_ref = a
		_ang = a
		_has_ref = true
	# 좌우는 ±90° 안(asin), 앞뒤는 ±180°에서 넘어가므로 각도 차로 섞는다
	_ang = Vector2(_ang.x + (a.x - _ang.x) * FILTER, _ang.y + rad_to_deg(angle_difference(deg_to_rad(_ang.y), deg_to_rad(a.y))) * FILTER)
	var d := Vector2(_ang.x - _ref.x, rad_to_deg(angle_difference(deg_to_rad(_ref.y), deg_to_rad(_ang.y))))
	var r := range_deg(sensitivity)
	var out := Vector2.ZERO
	var active := false
	for i in 2:
		var v := d[i]
		if absf(v) > deadzone:
			active = true
			out[i] = clampf(signf(v) * (absf(v) - deadzone) / r, -1.0, 1.0) * Tuning.BODY_GOAL_MAX
	return {"offset": out, "active": active}
