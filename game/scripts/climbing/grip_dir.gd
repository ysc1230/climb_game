class_name GripDir
extends RefCounted
## 홀드 면 방향에 따른 손 잡기(2026-11-26 사용자 "홀드 방향에 따라 손이 잡는 방향도 같이 바뀌어야해. 그에따라 몸에 받는 힘이 달라져야하고
## 특정 방향에서 손으로 잡기 불가능한 홀드가 있을거야. 불편한 홀드도 있을거야 … 힘이 빠지는 속도가 달라져야해", "실제 사람이 어떻게 동작하는지 판단해서").
## axis = 그립 방식의 힘 축(몸이 받는 힘, 잡는 면이 향한 쪽. 위 = 위를 보는 면). 실제 사람처럼:
## - 위를 보는 면(60° 안): 어느 손이든 당긴다(pull).
## - 아래를 보는 면: 손바닥을 위로 들어 올린다(undercling). 홀드가 그 손 어깨보다 낮을 때만(머리 위 언더는 못 씀).
## - 옆을 보는 면은 홀드가 그 손 쪽(몸 가운데에서 그 손 방향)에 있을 때만 잡는다. 몸을 가로질러 반대편 손으로는 못 잡는다
##   (사용자 예시 1 "오른쪽 면이 몸 오른쪽에 있으면 오른손만").
##   · 면이 그 손 바깥쪽(오른쪽 면 = 오른손): 몸 쪽으로 당긴다(sidepull, 팔이 당겨짐).
##   · 면이 그 손 안쪽(오른쪽 면 = 왼손, 홀드는 몸 왼쪽): 엄지를 아래로 뒤집어 바깥으로 민다(gaston, 팔이 밀림). 어깨 높이일 때만.
## 잡은 뒤 몸이 옮겨 그 손으로 못 잡는 자세가 되면 품질이 떨어지고 손 힘이 빨리 빠져 미끄러진다.

const UP := 0.5                  # cos 60°: 이보다 위를 보면 당기기, −이보다 아래를 보면 언더
const SIDE_X := 0.1              # 옆을 보는 면: 홀드가 몸 가운데(골반)에서 반대편으로 이만큼까지는 그 손 쪽으로 본다
const GASTON_BAND := 0.36        # 개스턴: 홀드가 어깨 높이 ± 이 안
const UNDER_ABOVE := 0.05        # 언더: 어깨보다 이만큼 위까지
## 방식별 손 힘 빠지는 배율(편한 당기기 1).
const FATIGUE := {&"pull": 1.0, &"sidepull": 1.2, &"undercling": 1.25, &"gaston": 1.6}
const SLIP_QUALITY := 0.3        # 잡은 뒤 못 잡는 자세: 품질 배율
const SLIP_DRAIN := 6.0          # 잡은 뒤 못 잡는 자세: 손 힘 빠지는 배율(1~2초면 미끄러짐)


## 손 limb이 힘 축 axis인 면을 hold에서 잡는 방식. 못 잡으면 &"".
## margin(m): 경계 안쪽으로 이만큼 여유(봇 계획용: 몸이 조금 움직여도 계속 잡히는 것만, 2026-11-28).
static func kind(limb: StringName, axis: Vector2, hold: Vector2, pelvis: Vector2, angle: float, yaw: float, margin := 0.0) -> StringName:
	if axis.y >= UP:
		return &"pull"
	var sh := PoseSolver.joint_position(pelvis, angle, limb, yaw)
	if axis.y <= -UP:
		return &"undercling" if hold.y <= sh.y + UNDER_ABOVE - margin else &""
	var s := PoseSolver.side_sign(limb)
	if (hold.x - pelvis.x) * s < -SIDE_X + margin:
		return &""  # 몸을 가로질러 반대편: 못 잡는다
	if axis.x * s > 0.0:
		return &"sidepull"
	return &"gaston" if absf(hold.y - sh.y) <= GASTON_BAND - margin else &""


## 그 손으로 잡을 수 있는 그립 방식이 하나라도 있는가(손 칸, grip_modes마다).
static func any_ok(slot: Dictionary, limb: StringName, pelvis: Vector2, angle: float, yaw: float, margin := 0.0) -> bool:
	for gm in slot.get("grip_modes", []):
		if kind(limb, gm.axis, slot.pos, pelvis, angle, yaw, margin) != &"":
			return true
	return false


## ContactInfo의 방식 이름.
static func mode_name(k: StringName) -> StringName:
	return k
