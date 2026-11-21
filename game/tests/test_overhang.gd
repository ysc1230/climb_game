extends RefCounted
## 벽 기울기 실험(experiment/overhang, docs/48 R2): 문제마다 벽 각도. 판정은 벽면 그대로, 힘만 기운다.

var runner


func _route(deg: float) -> RouteDef:
	var r := ContentIndex.load_all().route("G_V0_02")
	r.wall_deg = deg
	return r


func _hands(s: ClimbSession) -> float:
	var loads: Dictionary = s.rules.last.get("loads", {})
	return float(loads.get(&"LH", 0.0)) + float(loads.get(&"RH", 0.0))


func test_route_reads_wall_angle() -> void:
	var d := {"route_id": "X", "wall_angle_deg": 30}
	runner.check(is_equal_approx(RouteDef.from_dict(d).wall_deg, 30.0), "wall_angle_deg를 읽음")
	runner.check(RouteDef.from_dict({"route_id": "Y"}).wall_deg == 0.0, "없으면 수직")


## 같은 시작 자세에서 45° 벽은 손이 더 무겁다(시작은 바닥에 서 있어 쉬는 자세라 버틴다).
func test_tilt_loads_hands() -> void:
	var v := ClimbSession.new(_route(0.0))
	var o := ClimbSession.new(_route(45.0))
	for i in 120:
		v.step()
		o.step()
	runner.check(_hands(o) > _hands(v) + 0.15, "45°에서 손 하중 증가(%.2f → %.2f)" % [_hands(v), _hands(o)])
	runner.check(not o.falling, "바닥에 선 시작 자세로는 버팀")


## 봇이 같은 정답 순서로 오르면 기운 벽에서 손 힘이 더 많이 준다(발이 받는 몫 × cosθ, 손 사용률 증가).
func test_tilt_tires_hands_on_route() -> void:
	var v := RouteBot.run(_route(0.0))
	var o := RouteBot.run(_route(25.0))
	runner.check(v.ok(), "수직 완등")
	runner.check(o.min_stamina < v.min_stamina - 5.0 or not o.ok(), "25°에서 최저 손 힘이 더 낮음(%.0f vs %.0f, %s)" % [o.min_stamina, v.min_stamina, o.failure])
	runner.check(o.max_hand_u > v.max_hand_u, "25°에서 최대 손 사용률이 큼(%.2f vs %.2f)" % [o.max_hand_u, v.max_hand_u])


## 설정 "벽 기울기": 0·15·25·35·45° 중 하나(기본 25°, 실험 앱은 처음부터 기운 벽). 일반 문제에만 적용.
func test_wall_angle_setting() -> void:
	var p := Progress.new()
	runner.check(int(p.control_get("wall_deg")) == 25, "기본 25°")
	p.set_control("wall_deg", 35)
	runner.check(int(p.control_get("wall_deg")) == 35, "35°로 바꿈")
	p.set_control("wall_deg", 20)
	runner.check(int(p.control_get("wall_deg")) == 35, "목록에 없는 각은 무시")
	var r := ContentIndex.load_all().route("G_V0_02")
	Progress.apply_wall_angle(r, p)
	runner.check(is_equal_approx(r.wall_deg, 35.0), "일반 문제에 적용")
	r.wall_deg = 0.0
