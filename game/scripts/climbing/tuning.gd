class_name Tuning
extends RefCounted
## docs/04 초기 조정표의 판정 수치. 04와 값이 달라지면 04를 같은 변경에서 고친다.
## 모든 값은 조정용 초깃값이며 검증된 값이 아니다.

const TICK_HZ := 60
const DT := 1.0 / TICK_HZ

# 체형 (좌표·크기 계약)
const ARM_UPPER := 0.40
const ARM_LOWER := 0.38
const LEG_UPPER := 0.52
const LEG_LOWER := 0.48
const SHOULDER_OFFSET := Vector2(0.20, 0.55) # X는 좌우 부호 적용
const HIP_OFFSET := Vector2(0.14, 0.0)
const ARM_REACH_NOMINAL := Vector2(0.20, 0.78)
const LEG_REACH_NOMINAL := Vector2(0.25, 1.00)
const ELBOW_BEND_DEG := Vector2(5.0, 155.0)
const KNEE_BEND_DEG := Vector2(5.0, 145.0)
const BODY_ANGLE_LIMIT_DEG := 25.0

# 목표 자세 비용
const PREF_ARM := 0.52
const PREF_LEG := 0.78
const W_HAND := 1.00
const W_FOOT := 1.25
const W_ANGLE := 0.20
const W_LATERAL := 0.10

# 목표 탐색
const SEARCH_POS_STEP := 0.04
const SEARCH_ANGLE_STEP := 4.0
const SEARCH_ROUNDS := 8
const SEARCH_POS_EXTENT := 0.30
const SEARCH_ANGLE_EXTENT := 15.0
const COST_EPSILON := 0.00001
const DISTANCE_EPSILON := 0.00001

# 골반 운동
const ROOT_POS_GAIN := 40.0
const ROOT_POS_DAMPING := 12.0
const ROOT_SPEED_LIMIT := 1.2
const ROOT_ACCEL_LIMIT := 12.0
const ROOT_ANGLE_GAIN := 30.0
const ROOT_ANGLE_DAMPING := 10.0
const ROOT_ANGULAR_SPEED := 90.0
const ROOT_ANGULAR_ACCEL := 360.0

# 발 지지
const FOOT_SUPPORT_DIR := Vector2(0.0, 1.0)
const FOOT_SUPPORT_HALF_ANGLE := 60.0
const FOOT_SUPPORT_MIN_HEIGHT := 0.05
const SUPPORT_EXIT_ANGLE := 5.0
const SUPPORT_EXIT_HEIGHT := 0.01

# 잡기
const HAND_CANDIDATE_RADIUS := 0.12
const FOOT_CANDIDATE_RADIUS := 0.10
const ATTACHED_POSITION_TOLERANCE := 0.02

# 규칙
const UNSUPPORTED_GRACE_TICKS := 9
const GOAL_DWELL_TICKS := 36


## 두 뼈 길이와 굽힘 제한(완전 펴짐=0°)에서 얻는 거리 범위와 명목 범위의 교집합.
static func reach_range(a: float, b: float, bend: Vector2, nominal: Vector2) -> Vector2:
	var far := sqrt(a * a + b * b + 2.0 * a * b * cos(deg_to_rad(bend.x)))
	var near := sqrt(a * a + b * b + 2.0 * a * b * cos(deg_to_rad(bend.y)))
	return Vector2(maxf(nominal.x, near), minf(nominal.y, far))


static func arm_range() -> Vector2:
	return reach_range(ARM_UPPER, ARM_LOWER, ELBOW_BEND_DEG, ARM_REACH_NOMINAL)


static func leg_range() -> Vector2:
	return reach_range(LEG_UPPER, LEG_LOWER, KNEE_BEND_DEG, LEG_REACH_NOMINAL)
