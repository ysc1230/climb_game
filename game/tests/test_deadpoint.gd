extends RefCounted
## 데드포인트(docs/04 §10.5, docs/27 §8.4·§13 TA04): 패드 빠른 놓기, 창, 받기 판정, 놓치면 추락. 버튼은 없다(docs/28 §4.2).
## 대부분의 시험은 상승 중을 골반 속도 직접 주입으로 만든다. 실제 하이스텝(최대 0.244m/s)으로 창이 열리는지는 별도 시험이 본다.

var runner

const FAR := Vector2(3.0, 3.8)  # 시험에서 쓰지 않는 홀드를 치워 둘 곳
const LH_KEY := "TX_TECH/H01/hand_1"
const HOLD := "TX_TECH/N02/hand_1"  # 반폭 0.18 큰 홀드(dir = +X). 어깨 바로 위에 두면 영역이 접선 방향이라 투영이 도달 거리를 거의 바꾸지 않는다. 매 시험에서 옮긴다


func _tx() -> RouteDef:
	return RouteDef.load_json("res://data/routes/TX_TECH.json")


func _session(r: RouteDef) -> ClimbSession:
	var s := ClimbSession.new(r)
	for i in 30:
		s.step()
	return s


## LH를 떼어 위쪽으로 끌어 몸이 자리 잡게 한 뒤(체중 이동이 끝난 자세), 그 어깨에서 dir 방향으로
## (정적 한계 + extra) 떨어진 곳에 HOLD를 두고 손의 요청 목표를 거기로 옮긴다. 나머지 홀드는 치운다.
## offset_t: 영역 안 잡는 위치(끝 = 1). 반환: 잡는 점.
func _setup(r: RouteDef, s: ClimbSession, extra: float, offset_t: float = 0.0, drag: bool = true) -> Vector2:
	for k in r.slots:
		if k != HOLD and not k.contains("/H0") and not k.contains("/F0"):
			r.slots[k].pos = FAR
	r.slots[HOLD].pos = FAR
	var dir := Vector2(0.0, 1.0)
	var sh := PoseSolver.joint_position(s.body.pos, s.body.angle, &"LH", s.body.yaw)
	if drag:
		s.apply_input([{"type": "detach", "limb": &"LH"}])
		for i in 40:
			var req: Vector2 = s.limbs[&"LH"].req
			s.apply_input([{"type": "move", "limb": &"LH", "delta": (sh + dir * 1.2 - req).limit_length(2.5 * Tuning.DT)}])
			s.step()
		for i in 30:
			s.step()
	sh = PoseSolver.joint_position(s.body.pos, s.body.angle, &"LH", s.body.yaw)
	var far := TechniqueJudge.deadpoint_far(&"LH", s.body.yaw)
	var hw: float = r.slots[HOLD].hand_area.half_width
	var aim := sh + dir * (far + extra)
	r.slots[HOLD].pos = aim - Vector2(1, 0) * hw * offset_t
	if drag:
		var req2: Vector2 = s.limbs[&"LH"].req
		s.apply_input([{"type": "move", "limb": &"LH", "delta": aim - req2}])
	return aim


func _release(s: ClimbSession, speed: float) -> void:
	s.apply_input([{"type": "release", "limb": &"LH", "speed": speed}])


func _run(s: ClimbSession, n: int = 30) -> String:
	for i in n:
		var r := s.step()
		if r != "":
			return r
	return ""


func test_deadpoint_catches_while_rising() -> void:
	var r := _tx()
	var s := _session(r)
	var aim := _setup(r, s, 0.10)
	runner.check(s.limbs[&"LH"].state == "Dragging" and s.limbs[&"LH"].cand.is_empty(), "전제: 드래그 중, 정적 후보 없음 (%s)" % s.limbs[&"LH"].cand)
	s.body.vel.y = 0.40  # 일어서는 중
	runner.check(s.deadpoint_window(), "창 열림")
	_release(s, 2.0)
	runner.check(s.limbs[&"LH"].state == "Deadpoint" and s.deadpoint.limb == &"LH", "데드포인트 시작 (%s)" % s.limbs[&"LH"].state)
	var res := ""
	var drop := 0.0
	for i in 12:
		var before: float = s.rules.stamina[&"RH"]
		res = s.step()
		if res != "" or s.limbs[&"LH"].state == "Attached":
			drop = before - float(s.rules.stamina[&"RH"])
			break
	runner.check(res == "", "추락 없음 (%s)" % res)
	runner.check(s.limbs[&"LH"].state == "Attached" and s.limbs[&"LH"].key == HOLD, "LH가 홀드에 붙음: %s %s" % [s.limbs[&"LH"].state, s.limbs[&"LH"].key])
	runner.check(s.deadpoint.is_empty() and s.falls == 0, "데드포인트 종료, 추락 0")
	runner.check(absf(drop - 10.0) < 0.5, "붙는 틱에 버틴 손(RH) 피로 −10 (%.2f)" % drop)
	runner.check(s.limbs[&"LH"].contact != null and s.limbs[&"LH"].contact.quality >= 0.5, "접점 품질 ≥ 0.5")


## 정적 후보가 있으면 창이 열려 있어도 일반 잡기다(데드포인트·피로 −10 없음).
func test_static_candidate_wins_over_deadpoint() -> void:
	var r := _tx()
	var s := _session(r)
	_setup(r, s, -0.20)
	for i in 30:  # 손이 홀드 위로 내려오게 한다
		s.step()
	runner.check(not s.limbs[&"LH"].cand.is_empty(), "전제: 정적 후보 있음")
	var rh0: float = s.rules.stamina[&"RH"]
	s.body.vel.y = 0.40
	_release(s, 2.0)
	runner.check(s.limbs[&"LH"].state == "Attached" and s.limbs[&"LH"].key == HOLD and s.deadpoint.is_empty(), "일반 잡기 (%s)" % s.limbs[&"LH"].state)
	runner.check(is_equal_approx(rh0, s.rules.stamina[&"RH"]), "피로 −10 없음")


## Review Focus 4 / TA04: 정지 상태에서 같은 빠른 놓기는 데드포인트가 아니다. 손은 Free, 추락 없음.
func test_fast_drag_while_static_is_not_deadpoint() -> void:
	var r := _tx()
	var s := _session(r)
	var aim := _setup(r, s, 0.10)
	runner.check(not s.deadpoint_window(), "전제: 창 닫힘 (v_up %.3f)" % s.body.vel.y)
	_release(s, 2.0)
	runner.check(s.limbs[&"LH"].state == "Free", "손은 Free (%s)" % s.limbs[&"LH"].state)
	runner.check(s.deadpoint.is_empty(), "데드포인트 없음")
	var res := _run(s, 20)
	runner.check(res == "" and s.falls == 0, "추락 없음 (%s, falls %d)" % [res, s.falls])


func test_deadpoint_miss_falls() -> void:
	var r := _tx()
	var s := _session(r)
	var aim := _setup(r, s, 0.20)  # 보너스 0.15 + 0.05 밖
	s.body.vel.y = 0.40
	_release(s, 2.0)
	runner.check(s.limbs[&"LH"].state == "Deadpoint", "던짐 (%s)" % s.limbs[&"LH"].state)
	var res := _run(s, 12)
	runner.check(res == "fall:DEADPOINT_MISS", "DEADPOINT_MISS 추락: %s" % res)
	runner.check(s.falls == 1 and s.falling, "추락 수 1")
	# 같은 틱 이후 다시 세지 않는다
	_run(s, 5)
	runner.check(s.falls == 1, "추락 수 한 번만 증가")


func test_deadpoint_needs_quality() -> void:
	var r := _tx()
	var s := _session(r)
	var aim := _setup(r, s, 0.05, 0.9)  # 영역 끝(t = 0.9, q = 0.19)
	s.body.vel.y = 0.40
	_release(s, 2.0)
	runner.check(s.limbs[&"LH"].state == "Deadpoint", "던짐 (%s)" % s.limbs[&"LH"].state)
	var res := _run(s, 12)
	runner.check(res == "fall:DEADPOINT_MISS" and s.falls == 1, "품질 부족이면 추락: %s" % res)


## 상승이 끝난 뒤 0.25초(15틱)까지 열려 있고 그 뒤 닫힌다.
func test_window_grace() -> void:
	var s := _session(_tx())
	runner.check(not s.deadpoint_window(), "정지: 닫힘")
	s.body.vel.y = 0.40
	s.step()
	s.body.vel.y = 0.0
	var open_ticks := 0
	for i in 40:
		if s.deadpoint_window():
			open_ticks += 1
		s.body.vel.y = 0.0
		s.step()
	runner.check(open_ticks >= 14 and open_ticks <= 16, "상승 종료 후 약 15틱 열림 (%d)" % open_ticks)
	runner.check(not s.deadpoint_window(), "그 뒤 닫힘")


func test_bonus_formula() -> void:
	var s := _session(_tx())
	s.body.vel.y = 0.0
	runner.check(is_equal_approx(s.deadpoint_bonus(0.0), 0.0), "정지·무속도: 0")
	runner.check(is_equal_approx(s.deadpoint_bonus(1.0), 0.05), "속도 1: 0.05")
	s.body.vel.y = 0.2
	runner.check(is_equal_approx(s.deadpoint_bonus(1.0), 0.10), "0.25·0.2 + 0.05 = 0.10")
	s.body.vel.y = 1.0
	runner.check(is_equal_approx(s.deadpoint_bonus(5.0), 0.15), "상한 0.15")


## 입력 라우터: release 명령의 speed = 마지막 0.1초 동안의 이동 경로 길이 / 0.1.
func test_router_release_speed() -> void:
	var rt := InputRouter.new()
	rt.set_pad(&"LH", Vector2(100, 200), 160)
	rt.deadzone_px = 10
	rt.touch_down(1, Vector2(100, 200), false)  # 이미 떨어진 손: 바로 Dragging
	var x := 100.0
	for i in 6:  # 60Hz로 6프레임(0.1초): 프레임당 16px = 패드 지름의 0.1 = 0.1m
		x += 16.0
		rt.touch_drag(1, Vector2(x, 200), 1.0 + i / 60.0)
	var cmds := rt.touch_up(1, 1.0 + 5.0 / 60.0)
	runner.check(cmds.size() == 1 and cmds[0].type == "release", "release 명령")
	runner.check(absf(cmds[0].speed - 6.0) < 0.01, "speed ≈ 6 (0.6m / 0.1s): %.3f" % cmds[0].speed)
	# 멈췄다가 놓으면 0
	rt.touch_down(2, Vector2(100, 200), false)
	rt.touch_drag(2, Vector2(160, 200), 2.0)
	var still := rt.touch_up(2, 2.5)
	runner.check(is_zero_approx(still[0].speed), "멈췄다 놓으면 speed 0: %.3f" % still[0].speed)


## Ruling 12: 느린 놓기(< 1.0 m/s)는 창이 열려 있어도 일반 잡기 규칙: 후보 없으면 Free, 추락 없음.
func test_slow_release_is_not_deadpoint() -> void:
	var r := _tx()
	var s := _session(r)
	_setup(r, s, 0.10)
	s.body.vel.y = 0.40
	_release(s, 0.5)
	runner.check(s.limbs[&"LH"].state == "Free" and s.deadpoint.is_empty(), "느린 놓기: Free (%s)" % s.limbs[&"LH"].state)
	var res := _run(s, 20)
	runner.check(res == "" and s.falls == 0, "추락 없음 (%s)" % res)


## Ruling 12: 빠르게 놓아도 노린 홀드가 방향 영역 밖이면 던지지 않고 일반 Free.
func test_fast_release_toward_wrong_direction_is_free() -> void:
	var r := _tx()
	var s := _session(r)
	for k in r.slots:
		if k != HOLD and not k.contains("/H0") and not k.contains("/F0"):
			r.slots[k].pos = FAR
	var sh := PoseSolver.joint_position(s.body.pos, s.body.angle, &"LH", s.body.yaw)
	var bad := sh + Vector2(0.94, -0.342) * 0.4  # 안쪽 아래(-110°): 방향 영역(-100°) 경계 바로 밖
	r.slots[HOLD].pos = bad
	s.apply_input([{"type": "detach", "limb": &"LH"}])
	for i in 30:
		var req: Vector2 = s.limbs[&"LH"].req
		s.apply_input([{"type": "move", "limb": &"LH", "delta": (bad - req).limit_length(2.5 * Tuning.DT)}])
		s.step()
	runner.check(s.limbs[&"LH"].req.distance_to(bad) < 0.2, "전제: 요청 목표가 홀드 근처 (%s)" % s.limbs[&"LH"].req)
	s.body.vel.y = 0.40
	_release(s, 3.0)
	runner.check(s.limbs[&"LH"].state == "Free" and s.deadpoint.is_empty(), "방향 밖: Free (%s)" % s.limbs[&"LH"].state)
	var res := _run(s, 20)
	runner.check(res == "" and s.falls == 0, "추락 없음 (%s)" % res)


## 부정 게이트(패드): 반대 손이 붙어 있지 않으면, 하중 받는 발이 없으면 던지지 않는다.
func test_pad_gates_opposite_hand_and_feet() -> void:
	for gate in ["no_other_hand", "no_loaded_foot"]:
		var r := _tx()
		var s := _session(r)
		_setup(r, s, 0.10)
		s.body.vel.y = 0.40
		if gate == "no_other_hand":
			s.limbs[&"RH"].state = "Free"
		else:
			s.rules.loaded_feet.clear()
		_release(s, 2.0)
		runner.check(s.limbs[&"LH"].state == "Free" and s.deadpoint.is_empty(), "%s: Free, 데드포인트 없음 (%s)" % [gate, s.limbs[&"LH"].state])
		runner.check(s.falls == 0 and not s.falling, "%s: 추락 없음" % gate)


## 드래그 속도 항이 도달을 넓힌다: 정적 한계 + 0.13 홀드는 속도 1(보너스 0.10)로는 놓치고 속도 4(0.15)로는 잡는다.
func test_drag_speed_term_widens_reach() -> void:
	var outcomes := {}
	for speed in [1.0, 4.0]:
		var r := _tx()
		var s := _session(r)
		_setup(r, s, 0.13)
		s.body.vel.y = 0.20
		_release(s, speed)
		runner.check(s.limbs[&"LH"].state == "Deadpoint", "속도 %.0f: 던짐 (%s)" % [speed, s.limbs[&"LH"].state])
		outcomes[speed] = _run(s, 12)
	runner.check(outcomes[1.0] == "fall:DEADPOINT_MISS", "속도 1: 보너스 0.10으로는 놓침 (%s)" % outcomes[1.0])
	runner.check(outcomes[4.0] == "", "속도 4: 보너스 0.15로 잡음 (%s)" % outcomes[4.0])


## 패드로 limb을 key까지 끌어 놓는다. 붙으면 true.
func _pad_place(s: ClimbSession, limb: StringName, key: String, budget: int = 300) -> bool:
	var target := s.route.slot_pos(key)
	s.apply_input([{"type": "detach", "limb": limb}])
	for i in budget:
		var req: Vector2 = s.limbs[limb].req
		s.apply_input([{"type": "move", "limb": limb, "delta": (target - req).limit_length(2.5 * Tuning.DT)}])
		if s.step().begins_with("fall"):
			return false
		if s.limbs[limb].cand.get("key", "") == key:
			s.apply_input([{"type": "release", "limb": limb}])
			return s.limbs[limb].state == "Attached" and s.limbs[limb].key == key
	return false


## 자연 플레이: 실제 하이스텝 일어서기에서 속도 주입 없이 창이 열리고, 정적 한계 바로 밖 홀드를 데드포인트로 잡는다.
func test_natural_high_step_opens_window_and_catches() -> void:
	var r := _tx()
	var s := _session(r)
	var key := "TX_TECH/F03/foot_1"
	runner.check(_pad_place(s, &"LF", key), "패드 하이스텝: LF를 높은 발판에")
	var opened := false
	for i in 120:
		s.step()
		if s.deadpoint_window() and s.body.vel.y >= TechniqueJudge.DEADPOINT_RISE_SPEED:
			opened = true
			break
	runner.check(opened, "일어서는 중 창이 열림 (v_up %.3f)" % s.body.vel.y)
	if not opened:
		return
	for k in r.slots:
		if k != HOLD and not k.contains("/H0") and not k.contains("/F0"):
			r.slots[k].pos = FAR
	var sh := PoseSolver.joint_position(s.body.pos, s.body.angle, &"LH", s.body.yaw)
	var aim := sh + Vector2(0.0, 1.0) * (TechniqueJudge.deadpoint_far(&"LH", s.body.yaw) + 0.03)
	r.slots[HOLD].pos = aim
	s.apply_input([{"type": "detach", "limb": &"LH"}])
	for i in 20:  # 손이 옛 홀드에서 떨어져 올라가는 동안 창(상승 + 0.25초)이 계속 열려 있다
		var req: Vector2 = s.limbs[&"LH"].req
		s.apply_input([{"type": "move", "limb": &"LH", "delta": (aim - req).limit_length(2.5 * Tuning.DT)}])
		s.step()
		if (s.limbs[&"LH"].pos as Vector2).distance_to(s.limbs[&"LH"].req) < 0.02 and i > 8:
			break
	runner.check(s.deadpoint_window(), "전제: 창 아직 열려 있음 (v_up %.3f)" % s.body.vel.y)
	runner.check(s.limbs[&"LH"].cand.is_empty(), "전제: 정적 후보 없음")
	_release(s, 2.0)
	runner.check(s.limbs[&"LH"].state == "Deadpoint", "던짐 (%s)" % s.limbs[&"LH"].state)
	var res := _run(s, 12)
	runner.check(res == "" and s.limbs[&"LH"].state == "Attached" and s.limbs[&"LH"].key == HOLD, "자연 상승 중 받음: %s %s %s" % [res, s.limbs[&"LH"].state, s.limbs[&"LH"].key])


## 다시 잡기 버그: 끌고 있지 않은 손발(붙음·무장·날아가는 중)의 release는 아무것도 바꾸지 않는다.
func test_release_on_non_dragging_limb_is_ignored() -> void:
	var r := _tx()
	var s := _session(r)
	var rh: Dictionary = s.limbs[&"RH"]
	var contact = rh.contact
	s.apply_input([{"type": "release", "limb": &"RH", "speed": 0.0}])
	runner.check(rh.state == "Attached" and rh.contact == contact and rh.key == "TX_TECH/H02/hand_1", "Attached: release 무시")
	rh.state = "Armed"
	s.apply_input([{"type": "release", "limb": &"RH", "speed": 0.0}])
	runner.check(rh.state == "Armed", "Armed: release 무시 (%s)" % rh.state)
	rh.state = "Attached"
	# 날아가는 중
	_setup(r, s, 0.10)
	s.body.vel.y = 0.40
	_release(s, 2.0)
	runner.check(s.limbs[&"LH"].state == "Deadpoint", "전제: 날아가는 중")
	var dp := s.deadpoint.duplicate()
	_release(s, 0.0)
	runner.check(s.limbs[&"LH"].state == "Deadpoint" and s.deadpoint == dp, "Deadpoint: release 무시")
	# _try_grab 직접 호출도 같은 보호
	s._try_grab(&"LH", 0.0)
	runner.check(s.limbs[&"LH"].state == "Deadpoint", "Deadpoint: _try_grab 무시")


## 보조 모드(fatigue_disabled)에서는 버틴 손의 즉시 피로 -10도 없다(Fatigue.apply 의미).
func test_deadpoint_holder_cost_respects_fatigue_disabled() -> void:
	var results := {}
	for disabled in [false, true]:
		var r := _tx()
		var s := _session(r)
		s.rules.fatigue_disabled = disabled
		_setup(r, s, 0.10)
		s.body.vel.y = 0.40
		var before: float = s.rules.stamina[&"RH"]
		_release(s, 2.0)
		runner.check(s.limbs[&"LH"].state == "Deadpoint", "던짐 (%s)" % disabled)
		for i in 20:
			s.body.vel.y = maxf(s.body.vel.y, 0.0)
			s.step()
			if s.deadpoint.is_empty():
				break
		runner.check(s.limbs[&"LH"].key == HOLD, "붙음 (%s)" % disabled)
		results[disabled] = before - float(s.rules.stamina[&"RH"])
	runner.check(results[false] >= ClimbSession.DEADPOINT_STAMINA_COST - 1.0, "기본: -10 적용 (%.2f)" % results[false])
	runner.check(results[true] <= 0.0, "보조 모드: 감소 없음 (%.2f)" % results[true])
