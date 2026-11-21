class_name FallSim
extends RefCounted
## 표현 전용 낙하·착지 장면(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.2). 판정의 낙하(ClimbSession._fall_tick)와 별개다.
## 2026-11-20 사용자: 매트에 누워 끝나 "죽은것처럼 보여" → 높지 않으면 무릎을 굽혔다 서고, 높으면 뒤로 굴렀다 일어선다.
## 공중: 골반이 시작 속도·중력대로 떨어지고(물리), 자세는 시작 자세에서 다리를 아래로 둔 낙하 자세로 바뀐다.
## 착지: 발이 매트에 닿은 높이(손발을 놓은 순간 발과 매트 사이)로 종류를 정하고, 열쇠 자세를 이어 움직인다.
##   낮음(1m 미만): 살짝 앉았다 섬 → 벽을 올려다봄. 중간(1~2m): 깊게 앉음 → 뒤로 구름 → 앉음 → 섬.
##   높음(2m 이상, 또는 몸이 35° 넘게 기울어 떨어짐): 뒤로 굴러 잠깐 누움 → 고개를 털며 앉음 → 섬.
## 열쇠 자세는 매개변수(골반 높이·몸 기울기·발 자리·팔 방향)로 두고 그 사이를 보간한 뒤 뼈 길이대로 점을 만든다.
## 내부는 1/120초 고정 걸음이라 기기 프레임 수와 상관없이 같은 장면이다.

const RELEASE_DELAY := 0.12  # 아직 붙은 손을 놓기까지(초)
const GRAVITY := 9.8
const STEP := 1.0 / 120.0
const LOW_MAX := 1.0         # m, 발 높이가 이보다 낮으면 낮음
const MID_MAX := 2.0         # m, 이보다 낮으면 중간, 아니면 높음
const TILT_HIGH := 35.0      # 도, 몸이 이보다 기울어 떨어지면 높음
const ANKLE_H := 0.07        # 서 있을 때 발목 높이(매트 위)
const STAND_TOP := 1.75      # m, 선 자세 머리 꼭대기 높이(기운 벽에서 이 높이의 벽면보다 앞에 선다)
const BLEND := 0.15          # 착지 순간 자세를 열쇠 자세로 넘기는 시간(초)
const NAMES := ["pelvis", "spine", "chest", "neck", "head", "head_top",
	"shoulder_L", "elbow_L", "wrist_L", "hand_L", "shoulder_R", "elbow_R", "wrist_R", "hand_R",
	"hip_L", "knee_L", "ankle_L", "toe_L", "hip_R", "knee_R", "ankle_R", "toe_R"]

## 열쇠 자세. h: 서 있는 골반 높이에 대한 비율, dz: 착지 자리에서 골반이 뒤(+z)로 간 거리, lean: 몸 기울기(도, + 뒤로),
## fz·fy: 발 자리(착지 자리 기준 앞뒤, 매트 위 높이), arm: 팔 방향(x는 바깥쪽), head: 고개 뒤로 젖힘(도), shake: 고개 털기 세기.
const AIR := {"h": 0.97, "dz": 0.0, "lean": -5.0, "fz": 0.0, "fy": 0.0, "arm": Vector3(0.3, 0.85, -0.25), "head": 0.0, "shake": 0.0}
const STAND := {"h": 1.0, "dz": 0.03, "lean": 0.0, "fz": 0.0, "fy": 0.0, "arm": Vector3(0.12, -1.0, 0.05), "head": 0.0, "shake": 0.0}
const LOOK := {"h": 1.0, "dz": 0.03, "lean": 0.0, "fz": 0.0, "fy": 0.0, "arm": Vector3(0.12, -1.0, 0.05), "head": 25.0, "shake": 0.0}
const SQUAT := {"h": 0.72, "dz": 0.05, "lean": -18.0, "fz": 0.0, "fy": 0.0, "arm": Vector3(0.2, -0.3, -0.8), "head": 0.0, "shake": 0.0}
const SQUAT_DEEP := {"h": 0.5, "dz": 0.08, "lean": -30.0, "fz": 0.0, "fy": 0.0, "arm": Vector3(0.25, -0.2, -0.9), "head": 0.0, "shake": 0.0}
const SIT := {"h": 0.14, "dz": 0.3, "lean": 25.0, "fz": -0.15, "fy": 0.0, "arm": Vector3(0.4, -0.6, 0.6), "head": -5.0, "shake": 0.0}
const SIT_SHAKE := {"h": 0.14, "dz": 0.3, "lean": 15.0, "fz": -0.15, "fy": 0.0, "arm": Vector3(0.4, -0.6, 0.6), "head": -5.0, "shake": 1.0}
const LIE := {"h": 0.15, "dz": 0.45, "lean": 70.0, "fz": 0.1, "fy": 0.3, "arm": Vector3(0.85, -0.2, 0.2), "head": -15.0, "shake": 0.0}
const CROUCH := {"h": 0.55, "dz": 0.12, "lean": -25.0, "fz": 0.0, "fy": 0.0, "arm": Vector3(0.2, -0.4, -0.8), "head": 0.0, "shake": 0.0}
## 종류별 [열쇠 자세, 그 자세까지 걸리는 초].
const SEQ := {
	&"low": [[SQUAT, 0.16], [STAND, 0.4], [LOOK, 0.3], [LOOK, 0.25]],
	&"mid": [[SQUAT_DEEP, 0.12], [SIT, 0.2], [LIE, 0.22], [SIT, 0.3], [CROUCH, 0.28], [STAND, 0.35]],
	&"high": [[SQUAT_DEEP, 0.1], [SIT, 0.15], [LIE, 0.2], [LIE, 0.5], [SIT_SHAKE, 0.4], [CROUCH, 0.3], [STAND, 0.4]],
}

var elapsed := 0.0
var _mat := 0.0
var _wall := 0.0
var _tan := 0.0  # 기운 벽(experiment/overhang): 높이 y의 벽면 z = _wall + max(y, 0)·tanθ
var _start := {}        # 시작 점
var _pins := {}         # 점 이름 → 놓는 시각
var _hold := 0.0        # 남은 손을 놓기까지(이 동안은 매달린 그대로)
var _len := {}          # 뼈 길이
var _stand_h := 0.9     # 서 있는 골반 높이(매트 위)
var _kind: StringName = &"low"
var _pel := Vector3.ZERO
var _vel := Vector3.ZERO
var _air_t := 0.0
var _land_t := -1.0     # 착지 뒤 지난 시간(<0이면 공중)
var _landed_at := -1.0
var _base := Vector3.ZERO
var _snap := {}         # 착지 순간 점(열쇠 자세로 넘기는 출발점)
var _impact := {}
var _pos := {}
var _acc := 0.0
var _done := false


## points: 이름 → Vector3(NAMES). vel: 시작 몸 속도. pins: 아직 붙은 손 점 → 놓는 시각.
## wall_deg: 벽 기울기(오버행 +). 벽면이 위로 갈수록 앞(+z)으로 나온다.
func start(points: Dictionary, vel: Vector3, pins: Dictionary, mat_top_y: float, wall_z: float, wall_deg := 0.0) -> void:
	_mat = mat_top_y
	_wall = wall_z
	_tan = tan(deg_to_rad(clampf(wall_deg, 0.0, 80.0)))
	_start = {}
	for k in NAMES:
		var p: Vector3 = points.get(k, points.get("pelvis", Vector3.ZERO))
		_start[k] = Vector3(p.x, maxf(p.y, _mat), maxf(p.z, wall_at(p.y)))
	_pins = pins.duplicate()
	_hold = 0.0
	for k in _pins:
		_hold = maxf(_hold, float(_pins[k]))
	_measure()
	_pel = _start.pelvis
	_vel = vel
	var up: Vector3 = (_start.chest as Vector3) - (_start.pelvis as Vector3)
	var tilt := rad_to_deg(atan2(absf(up.x), maxf(up.y, 1e-6))) if up.y > 0.0 else 180.0
	var feet := minf((_start.ankle_L as Vector3).y, (_start.ankle_R as Vector3).y) - ANKLE_H - _mat
	var drop := maxf(feet, _air_base(_pel).y - _mat)
	_kind = &"high" if tilt > TILT_HIGH or drop >= MID_MAX else (&"mid" if drop >= LOW_MAX else &"low")
	elapsed = 0.0
	_air_t = 0.0
	_land_t = -1.0
	_landed_at = -1.0
	_impact = {}
	_acc = 0.0
	_done = false
	_pos = _start.duplicate()


func _measure() -> void:
	var s: Dictionary = _start
	var d := func(a: String, b: String) -> float: return (s[a] as Vector3).distance_to(s[b])
	_len = {"spine": d.call("pelvis", "spine"), "chest": d.call("spine", "chest"), "neck": d.call("chest", "neck"),
		"head": d.call("neck", "head"), "top": d.call("head", "head_top"),
		"ua": (d.call("shoulder_L", "elbow_L") + d.call("shoulder_R", "elbow_R")) * 0.5,
		"fa": (d.call("elbow_L", "wrist_L") + d.call("elbow_R", "wrist_R")) * 0.5,
		"hand": (d.call("wrist_L", "hand_L") + d.call("wrist_R", "hand_R")) * 0.5,
		"thigh": (d.call("hip_L", "knee_L") + d.call("hip_R", "knee_R")) * 0.5,
		"shin": (d.call("knee_L", "ankle_L") + d.call("knee_R", "ankle_R")) * 0.5,
		"foot": maxf((d.call("ankle_L", "toe_L") + d.call("ankle_R", "toe_R")) * 0.5, 0.05),
		"hipw": d.call("hip_L", "hip_R") * 0.5, "shw": d.call("shoulder_L", "shoulder_R") * 0.5}
	var neck_mid: Vector3 = ((s.shoulder_L as Vector3) + (s.shoulder_R as Vector3)) * 0.5
	_len["shdrop"] = clampf((s.neck as Vector3).y - neck_mid.y, -0.1, 0.1)
	_stand_h = ANKLE_H + 0.97 * (_len.thigh + _len.shin)


## 공중 자세의 발 아래 가상 바닥(골반에서 낙하 자세의 골반 높이만큼 아래).
func _air_base(pel: Vector3) -> Vector3:
	return pel - Vector3(0, AIR.h * _stand_h, AIR.dz)


func kind() -> StringName:
	return _kind


func landed() -> bool:
	return _land_t >= 0.0


func landed_at() -> float:
	return _landed_at


## 착지 순간 한 번: {pos: 매트 위 착지 자리, kind}. 그 뒤로는 빈 값.
func take_impact() -> Dictionary:
	var i := _impact
	_impact = {}
	return i


func step(dt: float) -> void:
	if _done or dt <= 0.0:
		return
	_acc += dt
	while _acc >= STEP - 1e-9 and not _done:
		_acc -= STEP
		_tick(STEP)
	_pos = _frame()


func _tick(dt: float) -> void:
	elapsed += dt
	if elapsed < _hold:
		return
	if _land_t < 0.0:
		_air_t += dt
		_vel.y -= GRAVITY * dt
		_vel.x *= exp(-2.0 * dt)
		_pel += _vel * dt
		_pel.z = lerpf(_pel.z, maxf(_pel.z, wall_at(_pel.y) + 0.3), 1.0 - exp(-4.0 * dt))
		if _air_base(_pel).y <= _mat:
			_pel.y = _mat + AIR.h * _stand_h
			# 무릎·손이 벽에 닿지 않게. 기운 벽은 선 머리 높이(STAND_TOP)의 벽면보다 앞에 선다
			_base = Vector3(_pel.x, _mat, maxf(_pel.z - AIR.dz, maxf(_wall + 0.35, wall_at(_mat + STAND_TOP) + 0.15)))
			_snap = _frame_air()
			_land_t = 0.0
			_landed_at = elapsed
			_impact = {"pos": _base, "kind": _kind}
		return
	_land_t += dt
	if _land_t >= _total():
		_done = true


func _total() -> float:
	var t := 0.0
	for k in SEQ[_kind]:
		t += float(k[1])
	return t


func _frame() -> Dictionary:
	if elapsed < _hold:
		return _start.duplicate()
	if _land_t < 0.0:
		return _frame_air()
	var keys: Array = SEQ[_kind]
	var prev: Dictionary = AIR
	var t := _land_t
	var cur: Dictionary = keys[keys.size() - 1][0]
	for k in keys:
		var dur := float(k[1])
		if t <= dur:
			cur = _mix(prev, k[0], smoothstep(0.0, 1.0, t / maxf(dur, 1e-6)))
			break
		t -= dur
		prev = k[0]
	var pts := _build(_base, cur, _land_t)
	if _land_t < BLEND:
		var w := smoothstep(0.0, 1.0, _land_t / BLEND)
		for k in pts:
			pts[k] = (_snap[k] as Vector3).lerp(pts[k], w)
	return _clamp(pts)


## 공중: 시작 자세(골반을 따라 옮김)에서 낙하 자세로 0.2초에 걸쳐 바뀐다.
func _frame_air() -> Dictionary:
	var built := _build(_air_base(_pel), AIR, 0.0)
	var w := smoothstep(0.0, 1.0, _air_t / 0.2)
	var shift: Vector3 = _pel - (_start.pelvis as Vector3)
	var pts := {}
	for k in NAMES:
		pts[k] = ((_start[k] as Vector3) + shift).lerp(built[k], w)
	return _clamp(pts)


func _clamp(pts: Dictionary) -> Dictionary:
	for k in pts:
		var p: Vector3 = pts[k]
		pts[k] = Vector3(p.x, maxf(p.y, _mat), maxf(p.z, wall_at(p.y)))
	return pts


## 높이 y의 벽면 z(수직 벽은 _wall 그대로).
func wall_at(y: float) -> float:
	return _wall + maxf(y, 0.0) * _tan


static func _mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out := {}
	for k in a:
		out[k] = lerp(a[k], b[k], w)
	return out


## 열쇠 자세 매개변수 → 뼈 길이를 지킨 점들. base: 착지 자리(매트 위).
func _build(base: Vector3, c: Dictionary, t: float) -> Dictionary:
	var L := _len
	var lean := deg_to_rad(float(c.lean))
	var u := Vector3(0, cos(lean), sin(lean))
	var fw := Vector3(0, sin(lean), -cos(lean))  # 몸 앞(벽 쪽)
	var pel := base + Vector3(0, maxf(float(c.h) * _stand_h, 0.1), float(c.dz))
	var p := {"pelvis": pel}
	p.spine = pel + u * L.spine
	p.chest = (p.spine as Vector3) + u * L.chest
	p.neck = (p.chest as Vector3) + u * L.neck
	var hl := lean + deg_to_rad(float(c.head))
	var hu := Vector3(sin(t * 22.0) * 0.35 * float(c.shake), cos(hl), sin(hl)).normalized()
	p.head = (p.neck as Vector3) + hu * L.head
	p.head_top = (p.head as Vector3) + hu * L.top
	var arm: Vector3 = c.arm
	for s in ["L", "R"]:
		var x := -1.0 if s == "L" else 1.0
		var sh: Vector3 = (p.neck as Vector3) - u * L.shdrop + Vector3(x * L.shw, 0, 0) + fw * 0.05
		var a := Vector3(arm.x * x, arm.y, arm.z).normalized()
		# 손이 매트 아래로 가면 팔을 매트 위에 짚게 편다(뼈 길이 그대로)
		var min_y := clampf((_mat + 0.02 - sh.y) / (L.ua + L.fa + L.hand), -1.0, 1.0)
		if a.y < min_y:
			var flat := Vector2(a.x, a.z).normalized() * sqrt(1.0 - min_y * min_y)
			a = Vector3(flat.x, min_y, flat.y)
		# 손이 벽을 뚫으면 벽 앞에서 멈추게 아래·옆으로 돌린다
		var min_z := clampf((wall_at(sh.y) + 0.03 - sh.z) / (L.ua + L.fa + L.hand), -1.0, 1.0)
		if a.z < min_z:
			var side := Vector2(a.x, a.y).normalized() * sqrt(1.0 - min_z * min_z)
			a = Vector3(side.x, side.y, min_z)
		p["shoulder_" + s] = sh
		p["elbow_" + s] = sh + a * L.ua
		p["wrist_" + s] = sh + a * (L.ua + L.fa)
		p["hand_" + s] = sh + a * (L.ua + L.fa + L.hand)
		var hip := pel + Vector3(x * L.hipw, 0, 0)
		var ankle := Vector3(base.x + x * maxf(L.hipw, 0.1) * 1.3, base.y + ANKLE_H + float(c.fy), base.z + float(c.fz))
		var knee := _knee(hip, ankle, L.thigh, L.shin)
		ankle = knee + (ankle - knee).normalized() * L.shin
		p["hip_" + s] = hip
		p["knee_" + s] = knee
		p["ankle_" + s] = ankle
		p["toe_" + s] = ankle + Vector3(0, -0.02, -1).normalized() * L.foot
	return p


## 두 마디 다리: 무릎은 앞(벽 쪽)·위로 굽는다.
static func _knee(hip: Vector3, ankle: Vector3, a: float, b: float) -> Vector3:
	var d := ankle - hip
	var dist := clampf(d.length(), absf(a - b) + 1e-3, a + b - 1e-4)
	var n := d.normalized() if d.length() > 1e-6 else Vector3.DOWN
	# 다리 축에 수직이면서 옆(x)과도 수직인 방향: 서 있으면 앞(−z), 다리가 앞으로 뻗으면 위
	var perp := Vector3.RIGHT.cross(n)
	perp = perp.normalized() if perp.length() > 1e-4 else Vector3(0, 0, -1)
	var along := (a * a - b * b + dist * dist) / (2.0 * dist)
	return hip + n * along + perp * sqrt(maxf(a * a - along * along, 0.0))


func points() -> Dictionary:
	return _pos


func done() -> bool:
	return _done


## 끝 자세로 바로 간다(화면을 눌러 건너뛰기).
func skip() -> void:
	var guard := 0
	while not _done and guard < 60 * 10:
		step(1.0 / 60.0)
		guard += 1
	_done = true
