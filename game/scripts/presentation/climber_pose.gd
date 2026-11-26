class_name ClimberPose
extends RefCounted
## 판정 상태 → 표현용 3D 관절 위치(docs/04 §8). play_3d와 해부학 점검(Anatomy, AnatomySweep)이 같이 쓴다.
## 판정은 2D(벽 평면)라서 골반 깊이(Z)와 떠 있는 손발의 깊이는 표현이 정한다.
## - 골반 깊이: 붙은 접점이 허용하는 구간(PoseSolver.body_depth_range) 안에서, 선호 깊이에 가까우면서
##   네 팔다리 모두 해부학적으로 가능한 굽힘이 있는 깊이를 고른다(발을 엉덩이 높이로 들면 엉덩이를 벽에서 뗀다).
## - 끌거나 떠 있는 손발 끝: 기본 깊이(접촉면 + 띄움)에서 안 되면 벽에서 더 떨어진 깊이를 쓴다.
## - 팔다리 굽힘은 LimbIK.solve_limb가 해부학 범위 안에서 고른다. 깊이는 DEPTH_SPEED로 부드럽게 따라간다.

## 몸통·머리 관절 높이(골반 기준, 위 방향). 2026-11-11 B안(docs/35 §6): 몸통이 길고 머리 1.4배. 이전 0.22/0.44/0.63/0.80/0.94.
const SPINE_UP := 0.16   # 더미 몸(docs/39). B안 0.27/0.54/0.76/0.84/1.16
const CHEST_UP := 0.37
const NECK_UP := 0.49
const HEAD_UP := 0.56
const HEAD_TOP_UP := 0.81
const DEPTH_STEP := 0.03       # 골반 깊이 후보 간격
const DEPTH_SPEED := 1.0       # m/s, 표현 골반 깊이가 목표로 따라가는 빠르기
const LIFT_SPEED := 2.5        # m/s, 떠 있는 손발 끝 깊이가 목표로 따라가는 빠르기
const FREE_END_DEPTHS := [0.0, 0.06, 0.12]  # 떠 있는 발 끝의 추가 깊이 후보(기본 띄움에 더함). 벽 평면 위치는 판정 그대로
const FREE_FOOT_FRONT := 0.05  # 떠 있는 발 끝은 골반보다 이만큼 이상 벽 쪽(발이 몸 뒤로 나오는 "뒤차기" 방지, docs/37)
const FREE_HAND_DEPTHS := [0.0, -0.06, -0.12]  # 떠 있는 손 끝: 벽 쪽으로 붙이기(−0.12면 접촉면 깊이)
const LIFT_HOLD_TICKS := 20   # 떠 있는 발의 추가 깊이를 한 번 바꾸면 이만큼은 유지(오락가락 방지)
const HYSTERESIS := 0.02       # 새 깊이 후보는 지금 목표보다 점수가 이만큼 이상 나을 때만 바꾼다
const SEARCH_BUDGET := 32      # 프레임당 굽힘 원 계산 상한(불가능한 자세에서 탐색이 길어지지 않게)
## 몸통 비틀기(표현만, 판정 yaw에 더함). 어느 깊이에서도 팔다리가 불가능하면 몸을 옆으로 틀어 본다(2026-11-21 사용자:
## V3-4에서 왼팔이 펴져 골반이 벽에 붙자 많이 굽은 오른팔 팔꿈치가 벽을 뚫고 가슴 앞으로 접혔다. 오른 어깨를 벽에서 빼면 자리가 생긴다).
const TWIST_STEP := 10.0       # 도, 비틀기 후보 간격
const TWIST_MAX := 30.0        # 도, 판정 yaw에서 더 트는 최대 각
const TWIST_SPEED := 60.0      # 도/초, 표현 비틀기가 목표로 따라가는 빠르기
const TWIST_COST := 0.002      # 도당 비용(위반이 같으면 덜 트는 쪽)
const TWIST_BUDGET := 24       # 비틀기 후보를 볼 때만 더 쓰는 굽힘 원 계산 수
const TWIST_HOLD_TICKS := 30   # 비틀기를 바꾸면 이만큼은 유지하고, 그 뒤 덜 틀어도 되면 한 단계씩 푼다

var bends := {}        # limb -> 직전 굽힘 축(연속성)
var depth := NAN       # 표현 골반 깊이(부드럽게 따라감)
var free_lift := {}    # limb -> 떠 있는 말단의 추가 깊이(부드럽게 따라감)
var _cache := {}       # 이번 프레임에 구한 굽힘 원(limb·관절·끝 → circle)
var _target := {}      # 목표 {depth, lift: limb → 추가 깊이, twist: 판정 yaw에 더할 각}. 가능하면 유지한다
var _lift_hold := {}   # limb → 떠 있는 발 추가 깊이를 바꾼 뒤 남은 유지 틱
var twist := 0.0       # 표현 몸통 비틀기(도, 판정 yaw에 더함. 부드럽게 따라감)
var _twist_hold := 0
var _budget := 0


## session: ClimbSession(또는 같은 필드를 가진 것). delta: 프레임 시간.
## 떠 있는 손발의 그림 위치(ReachMarker.display_point, 표현만). 붙은 손발은 판정 점 그대로.
var _disp := {}


func _update_display(session, delta: float) -> void:
	var flying: bool = session.has_method("dyno_flying") and session.dyno_flying()
	for limb in session.limbs:
		var l: Dictionary = session.limbs[limb]
		var hanging: bool = l.state == "Free" and not flying and PoseSolver.is_hand(limb)
		_hang[limb] = move_toward(float(_hang.get(limb, 1.0 if hanging else 0.0)), 1.0 if hanging else 0.0, HANG_RATE * delta)
		if l.state in ["Attached", "Armed"] or not _disp.has(limb):
			_disp[limb] = l.pos
		elif l.state == "Free" and not flying:
			var b = session.body
			var root := PoseSolver.joint_position(b.pos, b.angle, limb, b.yaw)
			var full := (Tuning.ARM_UPPER + Tuning.ARM_LOWER) if PoseSolver.is_hand(limb) else (LimbIK.leg_upper_shown + LimbIK.leg_lower_shown)
			var rest: Vector2 = b.pos + ClimbSession._rest_offset(limb)
			if PoseSolver.is_hand(limb):
				rest = root + Vector2(sin(deg_to_rad(HANG_OUT_DEG)) * PoseSolver.side_sign(limb), -cos(deg_to_rad(HANG_OUT_DEG))) * HANG_REACH * full
			_disp[limb] = free_display(_disp[limb], rest, root, PoseSolver.side_sign(limb), full, delta)
		else:
			_disp[limb] = ReachMarker.display_point(_disp[limb], l, delta)


## 놓친·쉬는(Free) 손발의 그림 위치(docs/59 §5 2단계, 2026-11-25 사용자: "머리 위 홀드를 못 잡고 팔이 떨어질 때 이상한 각도로
## 돌아간다"). 판정 점은 쉬는 자리로 곧게 가서 어깨·고관절 바로 옆을 지난다. 그대로 그리면 팔꿈치가 155° 넘게 접혀 솟고 아래팔이
## 몸통을 뚫는다. 그림은 어깨·고관절(root)을 중심으로 쉬는 자리(rest, 판정 Free의 목표)까지 바깥쪽 호를 그리며 내려온다:
## 각은 바깥(옆)을 거쳐 돌고(안쪽 수평에서만 끊김), 남은 각이 크면 팔다리 길이의 FREE_DROP_RADIUS 밑으로 오므리지 않는다.
## 호를 따라 FREE_DROP_SPEED로 움직인다. 판정 점(session)은 바꾸지 않는다.
const FREE_DROP_SPEED := 2.5     # m/s(판정 Free 빠르기와 같음)
const FREE_DROP_RADIUS := 0.8    # 팔다리 길이 비율
const FREE_DROP_MIN_ARM := 0.4   # m, 각속도 = 빠르기 / max(반지름, 이 값). 접힌 다리가 엉덩이 옆에서 휙 돌지 않게(한 프레임 6° 남짓)
## 놓친 손은 판정 쉬는 자리(골반 옆 위, 벽 가까이)가 아니라 몸 옆에 거의 편 채 늘어뜨린다: 어깨에서 아래로, 바깥으로 HANG_OUT_DEG,
## 깊이는 골반 깊이에서 HANG_FRONT만큼 벽 쪽. 판정 쉬는 자리로 그리면 손이 어깨 앞 가까이 와서 팔꿈치가 90° 넘게 접히고
## 굽는 방향이 반 바퀴 넘어가며 어깨 비틀림이 170°가 됐다(docs/59). 끌기 시작하면 HANG_RATE로 다시 벽 쪽으로 간다.
const HANG_OUT_DEG := 15.0
const HANG_REACH := 0.95         # 어깨→손목 거리 = 팔 길이 × 이 값(팔꿈치를 살짝 굽힘)
const HANG_FRONT := 0.05
const HANG_RATE := 4.0           # 1/s
var _hang := {}                  # limb → 늘어뜨린 정도 0~1


static func free_display(prev: Vector2, rest: Vector2, root: Vector2, side: float, limb_len: float, dt: float) -> Vector2:
	var p := prev - root
	var q := rest - root
	var ap := atan2(p.y, p.x * side)  # 바깥 0, 위 +90°, 아래 −90°
	var aq := atan2(q.y, q.x * side)
	var rp := p.length()
	var a := move_toward(ap, aq, FREE_DROP_SPEED * dt / maxf(rp, FREE_DROP_MIN_ARM))
	var r := move_toward(rp, maxf(q.length(), FREE_DROP_RADIUS * limb_len), FREE_DROP_SPEED * dt)
	var floor_r := lerpf(q.length(), FREE_DROP_RADIUS * limb_len, smoothstep(deg_to_rad(10.0), deg_to_rad(45.0), absf(aq - a)))
	r = maxf(r, minf(rp, floor_r))
	return root + Vector2(cos(a) * side, sin(a)) * r


func compute(session, delta: float) -> Dictionary:
	_update_display(session, delta)
	var body = session.body
	var attached: Dictionary = session.attached()
	var ang := deg_to_rad(body.angle)
	var up := Vector3(-sin(ang), cos(ang), 0)
	_cache.clear()
	_budget = SEARCH_BUDGET
	for limb in _lift_hold.keys():
		_lift_hold[limb] = maxi(0, int(_lift_hold[limb]) - 1)
	_twist_hold = maxi(0, _twist_hold - 1)
	var want := _choose(session, body, attached, up)
	var target_depth: float = want.depth
	if is_nan(depth):
		depth = target_depth
		twist = float(want.twist)
	else:
		depth = move_toward(depth, target_depth, DEPTH_SPEED * delta)
		twist = move_toward(twist, float(want.twist), TWIST_SPEED * delta)
	var yaw := _yaw(body, twist)
	var frame := Anatomy.body_basis(body.angle, yaw)
	var pelvis := Vector3(body.pos.x, body.pos.y, depth)
	var t := {"pelvis": pelvis, "spine": pelvis + up * SPINE_UP, "chest": pelvis + up * CHEST_UP,
		"neck": pelvis + up * NECK_UP, "head": pelvis + up * HEAD_UP, "head_top": pelvis + up * HEAD_TOP_UP, "up": up, "yaw": yaw}
	var max_step := LimbIK.PRESENTATION_JOINT_SPEED_DEG * delta
	for limb in PoseSolver.LIMBS:
		var hand := PoseSolver.is_hand(limb)
		var lift_now: float = free_lift.get(limb, 0.0)
		free_lift[limb] = move_toward(lift_now, float(want.lift[limb]), LIFT_SPEED * delta)
		var root := _root(body, limb, depth, yaw)
		var end := _end(session, limb, float(free_lift[limb]), depth)
		var stood := not hand and _stood(session, limb)
		if stood:
			end = _pivot_foot(limb, root, end, frame, pelvis, up)
		var ik := LimbIK.solve_circle(_circle(limb, root, end, frame, pelvis, up, true, _ik_free(session, limb)), bends.get(limb, Vector3.ZERO), max_step)
		bends[limb] = ik.bend
		var mid: Vector3 = ik.mid
		var s := "L" if PoseSolver.side_sign(limb) < 0 else "R"
		if hand:
			t["shoulder_" + s] = root
			t["elbow_" + s] = mid
			t["wrist_" + s] = end
			t["hand_" + s] = end + _hand_dir(session, limb, (end - mid).normalized()) * Anatomy.HAND_LENGTH
		else:
			t["hip_" + s] = root
			t["knee_" + s] = mid
			t["ankle_" + s] = end
			var fd := Anatomy.foot_direction(mid, end, frame, root)
			var key = session.limbs[limb].key
			if session.limbs[limb].state in ["Attached", "Armed"] and surface_top.has(key):
				# 딛은 발: 이번 발목은 직전 방향으로 놓았으니 발끝도 그 방향(홀드 윗면 그대로), 다음 프레임 방향은 무릎 쪽으로 돈다
				var prev: Vector3 = _foot_dir.get(limb, Anatomy.FOOT_WANT.normalized())
				t["toe_" + s] = end + prev * Anatomy.FOOT_LENGTH
				var next := prev.slerp(fd, minf(1.0, FOOT_TURN_SPEED * delta)).normalized()
				# 무릎 쪽으로 돌다가 발목이 무릎 자리가 없는 곳으로 가면 돌지 않는다(_pivot_foot와 오락가락하지 않게)
				if not stood or _leg_viol(limb, root, end + (prev - next) * Anatomy.FOOT_LENGTH, frame, pelvis, up) <= PIVOT_OK:
					_foot_dir[limb] = next
			else:
				t["toe_" + s] = end + fd * Anatomy.FOOT_LENGTH
				_foot_dir[limb] = fd
	return t


const WRIST_BEND_MAX := deg_to_rad(95.0)  # 옆·아래를 보는 면을 잡을 때 손목을 꺾는 최대 각
const WRIST_BEHIND := 0.05                # 그때 손목을 잡는 면 반대쪽으로 옮기는 거리(m)


## 손(손목 → 손가락) 방향: 옆·아래를 보는 면을 잡은 손은 손가락이 잡는 면 쪽(힘 축)을 향하게 손목을 꺾는다(WRIST_BEND_MAX까지).
## 사이드풀이면 손가락이 옆 날을, 언더면 아래 날을 감싼다(2026-11-27 사용자 "저 홀드는 옆으로밖에 잡을 수 없는데 그렇게 잡은것처럼 보이지않아").
static func _hand_dir(session, limb: StringName, forearm: Vector3) -> Vector3:
	var c = session.rules.contact_meta.get(limb)
	if c == null or not (session.limbs[limb].state in ["Attached", "Armed"]) or not (c.grip_kind in [&"sidepull", &"gaston", &"undercling"]):
		return forearm
	var want := Vector3(c.axis.x, c.axis.y, 0.0).normalized()
	var ang := forearm.angle_to(want)
	return want if ang <= WRIST_BEND_MAX else forearm.slerp(want, WRIST_BEND_MAX / ang).normalized()


## 끌거나 떠 있는 손발인가(붙음·준비가 아님).
static func _free(session, limb: StringName) -> bool:
	return not (session.limbs[limb].state in ["Attached", "Armed"])


## IK에 넘기는 free: 발은 _free(들어 옮기는 다리 규칙), 손은 늘어뜨린 손(Free, 다이노 비행 아님: 팔꿈치가 뒤로 갈 수 있음, docs/59).
static func _ik_free(session, limb: StringName) -> bool:
	if not PoseSolver.is_hand(limb):
		return _free(session, limb)
	return session.limbs[limb].state == "Free" and not (session.has_method("dyno_flying") and session.dyno_flying())


## 다리는 판정 고관절에서 몸 위쪽으로 LimbIK.hip_raise 올린 화면 회전 중심에서 시작한다.
## yaw: 표현 yaw(NAN이면 판정 yaw).
static func _root(body, limb: StringName, pelvis_depth: float, yaw := NAN) -> Vector3:
	if is_nan(yaw):
		yaw = body.yaw
	var j2 := PoseSolver.joint_position(body.pos, body.angle, limb, yaw)
	if not PoseSolver.is_hand(limb):
		var ang := deg_to_rad(body.angle)
		j2 += Vector2(-sin(ang), cos(ang)) * LimbIK.hip_raise
	return Vector3(j2.x, j2.y, pelvis_depth + PoseSolver.joint_depth_offset(limb, yaw))


## 판정 yaw + 표현 비틀기(골반 yaw 한계 안).
static func _yaw(body, tw: float) -> float:
	return clampf(body.yaw + tw, -Tuning.PELVIS_YAW_LIMIT_DEG, Tuning.PELVIS_YAW_LIMIT_DEG)


## 붙은 손발은 홀드 겉면(surface_depth[슬롯 키], 화면이 홀드 메시에서 채움)에 둔다(2026-11-13 사용자: "손이 홀드 안으로
## 묻힌다. 등 뒤에서 보니 홀드 겉을 잡아도 된다"). 없으면 판정 접촉 깊이. 판정은 그대로(표현만).
var surface_depth := {}
## 붙은 발은 발끝(앞꿈치)이 홀드 윗면(surface_top[슬롯 키], 홀드 중심에서 위로)에 얹히게 발목을 둔다(2026-11-15 사용자:
## "위쪽 홀드에 발을 딛으면 허공에 딛은 것처럼 보인다" — 발목을 홀드 중심에 두니 발끝이 홀드 아래 벽 속으로 들어갔다).
var surface_top := {}
const STRETCH_WEIGHT := 30.0  # 깊이 고르기: 닿지 않는 1m당 벌점(1cm = 0.3). 돌림 한계 벌점이 세진 뒤(2026-11-25) 머리 위로 끈 손이 1.1cm 늘어났다
const TOE_IN_HOLD := 0.5   # 발끝 깊이 = 홀드 겉면 깊이 × 이 비율(윗면 가운데쯤)
## 딛은 발의 발끝 방향(직전 프레임, 발목 자리를 정함). 무릎을 따라 FOOT_TURN_SPEED로 돈다: 발끝은 홀드 위 그대로, 뒤꿈치가 돈다
## (2026-11-25 사용자 "어딜 밟아도 … 위에서 밟는 것처럼").
var _foot_dir := {}
const FOOT_TURN_SPEED := 6.0  # 1/s
const HAND_ON_SURFACE := 0.065   # 손 접점(손가락 뿌리)을 홀드 겉면에서 띄우는 거리(말아 쥔 손가락 길이만큼, 손가락 끝이 겉면에 닿음)
const FOOT_ON_SURFACE := 0.03


## 딛은 발 뒤꿈치 돌리기(2026-11-26 사용자 V0-2 화면 "무릎이 불가능한 각도야. 그리고 발도 문제가 있어"): 판정 다리 길이는 엉덩이→홀드
## 접점이라(최소 0.24m) 발끝 기준으로 놓은 발목(발 길이만큼 벽 밖·위)이 엉덩이에 너무 가까워질 수 있다. 그러면 무릎 자리가 하나도 없어
## 돌림 한계를 넘어 접혔다. 발목에서 무릎 자리가 없으면 발끝은 홀드에 둔 채 발 방향을 돌려 무릎 자리를 낸다(주로 뒤꿈치 내리기).
## 후보: FOOT_WANT를 좌우 PIVOT_YAWS·위로 PIVOT_PITCHES만큼 돈 방향 중 가장 나은 것. 지금 방향에서 그쪽으로 무릎 자리가 생기는 만큼만 돈다.
const PIVOT_OK := 0.05     # 가장 나은 굽힘의 위반이 이 아래면 무릎 자리가 있다
const PIVOT_YAWS := [0.0, 45.0, -45.0, 90.0, -90.0]
const PIVOT_PITCHES := [0.0, 30.0, 60.0]


## 홀드 윗면에 발끝을 얹은 발(_end가 발끝 기준으로 발목을 놓는다).
func _stood(session, limb: StringName) -> bool:
	var key = session.limbs[limb].key
	return session.limbs[limb].state in ["Attached", "Armed"] and surface_depth.has(key) and surface_top.has(key)


func _leg_viol(limb: StringName, root: Vector3, ankle: Vector3, frame: Basis, pelvis: Vector3, up: Vector3) -> float:
	return LimbIK.circle_min(LimbIK.circle(limb, root, ankle, frame, pelvis, up, LimbIK.SEARCH_SAMPLES, false))


## 반환: 발목. 발 방향(_foot_dir)을 바꿨으면 그 방향의 발목.
func _pivot_foot(limb: StringName, root: Vector3, end: Vector3, frame: Basis, pelvis: Vector3, up: Vector3) -> Vector3:
	if _leg_viol(limb, root, end, frame, pelvis, up) <= PIVOT_OK:
		return end
	var fd: Vector3 = _foot_dir.get(limb, Anatomy.FOOT_WANT.normalized())
	var toe := end + fd * Anatomy.FOOT_LENGTH
	var best := fd
	var best_v := INF
	for yaw in PIVOT_YAWS:
		for pitch in PIVOT_PITCHES:
			var d: Vector3 = (Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch))) * Anatomy.FOOT_WANT.normalized()
			var v := _leg_viol(limb, root, toe - d * Anatomy.FOOT_LENGTH, frame, pelvis, up)
			if v < best_v - 0.01 or (absf(v - best_v) <= 0.01 and d.angle_to(fd) < best.angle_to(fd)):
				best = d
				best_v = v
	if best_v <= PIVOT_OK:
		# 지금 방향에서 best 쪽으로 무릎 자리가 생기는 가장 작은 만큼(이분법)
		var lo := 0.0
		var hi := 1.0
		for i in 5:
			var m := (lo + hi) * 0.5
			if _leg_viol(limb, root, toe - fd.slerp(best, m).normalized() * Anatomy.FOOT_LENGTH, frame, pelvis, up) <= PIVOT_OK:
				hi = m
			else:
				lo = m
		best = fd.slerp(best, hi).normalized()
	_foot_dir[limb] = best
	return toe - best * Anatomy.FOOT_LENGTH


func _end(session, limb: StringName, lift: float, pelvis_depth: float) -> Vector3:
	var stuck: bool = session.limbs[limb].state in ["Attached", "Armed"]
	var e2: Vector2 = session.limbs[limb].pos if stuck else _disp.get(limb, session.limbs[limb].pos)
	# 떠 있는 손발: 잡을 수 있는 홀드에 가까울수록 벽 쪽으로 붙인다(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.5)
	var near := 1.0 if stuck else ReachMarker.lift_scale(ReachMarker.nearest_slot_dist(session.route, limb, e2, session.occupied()))
	var z := Tuning.CONTACT_DEPTH if stuck else Tuning.CONTACT_DEPTH + (Tuning.FREE_ENDPOINT_LIFT + lift) * near
	var key = session.limbs[limb].key
	if stuck and not PoseSolver.is_hand(limb) and surface_depth.has(key) and surface_top.has(key):
		var toe := Vector3(e2.x, e2.y + float(surface_top[key]), float(surface_depth[key]) * TOE_IN_HOLD)
		return toe - _foot_dir.get(limb, Anatomy.FOOT_WANT.normalized()) * Anatomy.FOOT_LENGTH
	if stuck and surface_depth.has(key):
		z = maxf(z, float(surface_depth[session.limbs[limb].key]) + (HAND_ON_SURFACE if PoseSolver.is_hand(limb) else FOOT_ON_SURFACE))
	if stuck and PoseSolver.is_hand(limb):
		# 옆·아래를 보는 면: 손목을 홀드의 몸 쪽(잡는 면의 반대편)에 두고 손이 홀드를 가로질러 날을 감싼다(저그의 손목이 홀드 아래에 오듯)
		var c = session.rules.contact_meta.get(limb)
		if c != null and c.grip_kind in [&"sidepull", &"gaston", &"undercling"]:
			e2 -= (c.axis as Vector2).normalized() * WRIST_BEHIND
	if not stuck and not PoseSolver.is_hand(limb):
		z = maxf(Tuning.CONTACT_DEPTH, minf(z, pelvis_depth - FREE_FOOT_FRONT))
	if not stuck and PoseSolver.is_hand(limb):
		z = lerpf(z, pelvis_depth - HANG_FRONT, float(_hang.get(limb, 0.0)))
	return Vector3(e2.x, e2.y, z)


## 목표 골반 깊이와 떠 있는 말단의 추가 깊이. 지금 목표가 그대로 가능하면 유지한다(떨림 방지, 2026-11-08 사용자 보고:
## "움직일 때 팔이 심각하게 떨린다" — 손을 띄우고 비키는 선택이 매 틱 켜졌다 꺼졌다 했다).
## 지금 목표가 불가능할 때만 다시 찾는다: 1단계 골반 깊이 후보 모두(떠 있는 말단은 지금 깊이 그대로),
## 2단계 떠 있는 말단의 추가 깊이 후보. 새 후보는 지금보다 확실히 나을 때만(HYSTERESIS) 바꾼다.
## 점수는 팔다리마다 LimbIK.local_violation(지금 굽힘 쪽에서 가능한 자세가 있는가)의 합.
func _choose(session, body, attached: Dictionary, up: Vector3) -> Dictionary:
	if _target.is_empty():
		_target = {"depth": Tuning.PELVIS_DEPTH_PREFERRED, "lift": {}, "twist": 0.0}
	var tw: float = _target.twist
	var r := _depth_range(body, attached, tw)
	if not r.is_finite() and tw != 0.0:
		tw = 0.0  # 판정이 바뀌어 지금 비틀기로는 닿지 않음: 풀고 다시
		_target.twist = 0.0
		r = _depth_range(body, attached, tw)
	if not r.is_finite():
		r = Vector2(Tuning.PELVIS_DEPTH_PREFERRED, Tuning.PELVIS_DEPTH_PREFERRED)
	var start := clampf(Tuning.PELVIS_DEPTH_PREFERRED, r.x, r.y)
	_target.depth = clampf(float(_target.depth), r.x, r.y)
	for limb in PoseSolver.LIMBS:
		if not _free(session, limb) or not _target.lift.has(limb):
			_target.lift[limb] = 0.0  # 붙은 손발은 띄우지 않는다. 다시 떼면 0부터
	var cur := _score_depth(session, body, up, _target.depth, _target.lift, true, tw)
	if cur.total <= 0.0:
		_relax_twist(session, body, attached, up)
		return _target
	var cands: Array[float] = [float(_target.depth)]
	if absf(start - float(_target.depth)) > 0.001:
		cands.append(start)
	var k := 1
	while start + k * DEPTH_STEP <= r.y + 0.0001 or start - k * DEPTH_STEP >= r.x - 0.0001:
		if start + k * DEPTH_STEP <= r.y + 0.0001:
			cands.append(start + k * DEPTH_STEP)
		if start - k * DEPTH_STEP >= r.x - 0.0001:
			cands.append(start - k * DEPTH_STEP)
		k += 1
	var best := {}
	var best_v := INF
	for dpt in cands:
		var res := _score_depth(session, body, up, dpt, _target.lift, false, tw)
		if res.total < best_v:
			best_v = res.total
			best = res
		if best_v <= 0.0 or _budget <= 0:
			break
	if best_v > 0.0 and _budget > 0:
		for dpt in [float(best.get("depth", _target.depth)), float(_target.depth)]:
			var res := _score_depth(session, body, up, dpt, {}, false, tw)
			if res.total < best_v:
				best_v = res.total
				best = res
			if best_v <= 0.0 or _budget <= 0:
				break
	var best_cost := best_v + TWIST_COST * absf(tw)
	if best_v > 0.0:
		# 어느 깊이도 안 되면 몸통을 틀어 본다(덜 트는 쪽부터, 같은 크기는 양쪽 다 보고 더 나은 쪽)
		_budget += TWIST_BUDGET
		var mag := TWIST_STEP
		while mag <= TWIST_MAX + 0.001 and best_v > 0.0 and _budget > 0:
			for cand in [mag, -mag]:
				if is_equal_approx(cand, tw) or absf(body.yaw + cand) > Tuning.PELVIS_YAW_LIMIT_DEG:
					continue
				var rc := _depth_range(body, attached, cand)
				if not rc.is_finite():
					continue
				for dpt in [rc.y, clampf(Tuning.PELVIS_DEPTH_PREFERRED, rc.x, rc.y), (rc.x + rc.y) * 0.5]:
					var res := _score_depth(session, body, up, dpt, _target.lift, false, cand)
					if res.total + TWIST_COST * absf(cand) < best_cost:
						best_cost = res.total + TWIST_COST * absf(cand)
						best_v = res.total
						best = res
					if res.total <= 0.0 or _budget <= 0:
						break
			mag += TWIST_STEP
	if not best.is_empty() and best_v < float(cur.total) - HYSTERESIS:
		for limb in PoseSolver.LIMBS:
			if float(best.lift.get(limb, 0.0)) != float(_target.lift.get(limb, 0.0)):
				_lift_hold[limb] = LIFT_HOLD_TICKS
		if float(best.twist) != tw:
			_twist_hold = TWIST_HOLD_TICKS
		_target = {"depth": best.depth, "lift": best.lift, "twist": best.twist}
	return _target


## 비틀기 tw에서 붙은 접점이 모두 닿는 골반 깊이 구간(판정 PoseSolver.body_depth_range, yaw만 표현 값).
static func _depth_range(body, attached: Dictionary, tw: float) -> Vector2:
	return PoseSolver.body_depth_range(body.pos, body.angle, attached, _yaw(body, tw))


## 지금 목표가 가능하고 비틀었으면, 유지 틱이 지난 뒤 한 단계 덜 튼 자세가 가능할 때 그쪽으로(몸이 계속 틀어져 있지 않게).
func _relax_twist(session, body, attached: Dictionary, up: Vector3) -> void:
	var tw: float = _target.twist
	if tw == 0.0 or _twist_hold > 0:
		return
	var cand := move_toward(tw, 0.0, TWIST_STEP)
	var rc := _depth_range(body, attached, cand)
	if not rc.is_finite():
		return
	for dpt in [clampf(float(_target.depth), rc.x, rc.y), clampf(Tuning.PELVIS_DEPTH_PREFERRED, rc.x, rc.y)]:
		var res := _score_depth(session, body, up, dpt, _target.lift, true, cand)
		if res.total <= 0.0:
			_target = {"depth": dpt, "lift": res.lift, "twist": cand}
			_twist_hold = TWIST_HOLD_TICKS
			return


## 골반 깊이 하나의 점수. lifts: limb → 떠 있는 말단 추가 깊이(이것만 씀). 비면 FREE_END_DEPTHS를 모두 본다.
## fine이면 정밀 후보(표시와 같은 원)로, 아니면 거친 후보로 예산 안에서 본다.
## tw: 표현 몸통 비틀기(도).
func _score_depth(session, body, up: Vector3, dpt: float, lifts: Dictionary, fine: bool, tw: float) -> Dictionary:
	var pelvis := Vector3(body.pos.x, body.pos.y, dpt)
	var yaw := _yaw(body, tw)
	var frame := Anatomy.body_basis(body.angle, yaw)
	var total := 0.0
	var lift := {}
	for limb in PoseSolver.LIMBS:
		var root := _root(body, limb, dpt, yaw)
		var free := _free(session, limb)
		# 떠 있는 손발 끝의 깊이 후보: 발은 벽에서 더 띄우기(무릎 공간), 손은 벽 쪽으로 붙이기(얼굴 앞을 지날 때 머리 공간).
		# 벽 평면 위치는 판정 그대로. 한 번 바꾸면 LIFT_HOLD_TICKS 동안 유지(손을 띄우고 비키는 선택이 매 틱 바뀌어 떨렸다, 2026-11-08).
		var options: Array = [0.0]
		if free:
			if lifts.has(limb):
				options = [lifts[limb]]
			elif int(_lift_hold.get(limb, 0)) > 0:
				options = [_target.lift.get(limb, 0.0)]
			else:
				options = FREE_HAND_DEPTHS if PoseSolver.is_hand(limb) else FREE_END_DEPTHS
		var lv := INF
		var full := (Tuning.ARM_UPPER + Tuning.ARM_LOWER) if PoseSolver.is_hand(limb) else (LimbIK.leg_upper_shown + LimbIK.leg_lower_shown)
		for extra in options:
			var end := _end(session, limb, extra, dpt)
			var c := _circle(limb, root, end, frame, pelvis, up, fine, _ik_free(session, limb))
			if c.is_empty():
				break
			# 손발 끝이 뼈 길이보다 멀면(그 깊이에서 닿지 않음) 팔다리가 늘어나 보인다: 닿는 깊이를 고르게 벌점(STRETCH_WEIGHT/m)
			var v := LimbIK.local_violation(c, bends.get(limb, Vector3.ZERO)) + maxf(0.0, root.distance_to(end) - full) * STRETCH_WEIGHT
			if v < lv:
				lv = v
				lift[limb] = extra
			if v <= 0.0:
				break
		if lv == INF:
			return {"total": INF}
		total += lv
	return {"total": total, "depth": dpt, "lift": lift, "twist": tw}


## 같은 프레임 안 굽힘 원 캐시. 고르기용은 거친 후보(SEARCH_SAMPLES)·예산 안, force(실제 표시용)는 정밀 후보·예산 무관. 예산이 다 되면 {}.
func _circle(limb: StringName, root: Vector3, end: Vector3, frame: Basis, pelvis: Vector3, up: Vector3, force := false, free := false) -> Dictionary:
	var key := [limb, root, end, pelvis, force, free, frame]
	if _cache.has(key):
		return _cache[key]
	if not force:
		if _budget <= 0:
			return {}
		_budget -= 1
	var c := LimbIK.circle(limb, root, end, frame, pelvis, up, LimbIK.BEND_SAMPLES if force else LimbIK.SEARCH_SAMPLES, free)
	_cache[key] = c
	return c
