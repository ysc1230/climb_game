extends RefCounted
## 데드포인트(docs/04 §10.5, docs/27 §8.4·§13 TA04): 패드 빠른 놓기·기술 버튼, 창, 받기 판정, 놓치면 추락.
## 실제 하이스텝의 최대 상승 속도는 0.244m/s(< 0.25)라 창이 열리지 않으므로, 상승 중은 골반 속도를 직접 넣어 만든다.

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
	runner.check(is_equal_approx(s.deadpoint_bonus(1.0), 0.05), "속도 1: 0.05 (버튼 흐름)")
	s.body.vel.y = 0.2
	runner.check(is_equal_approx(s.deadpoint_bonus(1.0), 0.10), "0.25·0.2 + 0.05 = 0.10")
	s.body.vel.y = 1.0
	runner.check(is_equal_approx(s.deadpoint_bonus(5.0), 0.15), "상한 0.15")


## 버튼: 정지 상태에서는 양쪽 불가(창 닫힘 문구).
func test_deadpoint_button_side_disabled_when_static() -> void:
	var s := _session(_tx())
	var j := TechniqueJudge.judge(ClimbSnapshot.from_session(s), TechniqueJudge.T_DEADPOINT)
	for side in [&"left", &"right"]:
		runner.check(not j[side].available and j[side].reason == TechniqueJudge.LIMB_STATE, "%s 불가·LIMB_STATE: %s" % [side, j[side]])
		runner.check(j[side].text == TechniqueJudge.DEADPOINT_TEXT_CLOSED, "문구: %s" % j[side].text)


## 버튼: 창이 열려 있으면 보너스(0.25·v_up + 0.05) 범위 홀드가 후보가 되고 실행기가 같은 받기 로직으로 붙인다.
func test_deadpoint_button_catches() -> void:
	var r := _tx()
	var s := _session(r)
	var aim := _setup(r, s, 0.10, 0.0, false)
	s.body.vel.y = 0.40
	var snap := ClimbSnapshot.from_session(s)
	var j := TechniqueJudge.judge(snap, TechniqueJudge.T_DEADPOINT)
	runner.check(j.left.available, "왼쪽 가능: %s" % [j.left])
	var targets := TechniqueJudge.hold_targets(snap, TechniqueJudge.T_DEADPOINT, &"left")
	runner.check(targets.any(func(t): return t.key == HOLD), "후보에 홀드 포함: %s" % [targets.map(func(t): return t.key)])
	runner.check(s.runner.start(s, TechniqueJudge.T_DEADPOINT, &"left", HOLD, aim) == &"", "시작")
	var res := ""
	for i in 20:
		s.body.vel.y = maxf(s.body.vel.y, 0.0)
		res = s.step()
		if res != "" or s.runner.active.is_empty():
			break
	runner.check(res == "", "추락 없음 (%s)" % res)
	runner.check(s.limbs[&"LH"].state == "Attached" and s.limbs[&"LH"].key == HOLD, "LH가 홀드에 붙음: %s %s" % [s.limbs[&"LH"].state, s.limbs[&"LH"].key])
	var types: Array = s.technique_log.map(func(e): return e.type)
	runner.check(types == [TechniqueRunner.STARTED, TechniqueRunner.SUCCEEDED], "started→succeeded: %s" % [types])


## 버튼: 보너스 밖 홀드는 후보가 아니고 시작도 거절된다. 방향 영역은 보너스로 완화되지 않는다.
func test_deadpoint_button_rejects_out_of_bonus() -> void:
	var r := _tx()
	var s := _session(r)
	var aim := _setup(r, s, 0.20, 0.0, false)
	s.body.vel.y = 0.40
	var snap := ClimbSnapshot.from_session(s)
	runner.check(not TechniqueJudge.hold_targets(snap, TechniqueJudge.T_DEADPOINT, &"left").any(func(t): return t.key == HOLD), "보너스 밖: 후보 아님")
	runner.check(s.runner.start(s, TechniqueJudge.T_DEADPOINT, &"left", HOLD, aim) != &"", "시작 거절")
	# 방향 영역 밖 홀드: 거리는 가까워도 거절
	var sh := PoseSolver.joint_position(s.body.pos, s.body.angle, &"LH", s.body.yaw)
	r.slots[HOLD].pos = sh + Vector2(0.3, -0.3)  # 안쪽 아래(-135°): 손 방향 영역 밖
	snap = ClimbSnapshot.from_session(s)
	var c := TechniqueJudge.check_hold(snap, TechniqueJudge.T_DEADPOINT, &"left", HOLD, r.slots[HOLD].pos)
	runner.check(not c.ok, "방향 밖 홀드 거절: %s" % [c])


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
