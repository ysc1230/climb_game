extends RefCounted
## R7 관문 검사 도구(작업 5 §5.1, docs/48 §4 R7): 관문 자리에서 그 기술 없이 골반을 격자로 옮겨 가며 힘 해가 있는지 센다.

var runner


func _route() -> RouteDef:
	return RouteDef.load_json("res://data/routes/general/G_V3_04.json")


func test_gate_steps_from_score_gates() -> void:
	var g := GateCheck.gate_steps(_route())
	runner.check(g.size() == 1 and g[0].index == 3 and g[0].limb == &"LF" and g[0].technique == &"T_HIGH_STEP", "관문 = score_gates 슬롯으로 가는 단계 %s" % [g])


func test_forbidden_rules() -> void:
	var r := _route()
	var pel := Vector2(0.0, 0.9)
	var hip := PoseSolver.joint_position(pel, 0.0, &"LF", 0.0)
	runner.check(GateCheck.forbidden({&"high_step": true}, &"LF", "x/F/f", Vector2(hip.x, hip.y), pel, 0.0, {}), "하이스텝 금지: 고관절 근처 발은 금지")
	runner.check(not GateCheck.forbidden({&"high_step": true}, &"LF", "x/F/f", Vector2(hip.x, hip.y - 0.4), pel, 0.0, {}), "낮은 발은 됨")
	runner.check(not GateCheck.forbidden({}, &"LF", "x/F/f", Vector2(hip.x, hip.y), pel, 0.0, {}), "금지가 없으면 됨")
	var keys := {&"RH": "R/H01/hand_1"}
	var att := {&"RH": Vector2(0.2, 1.5)}
	runner.check(GateCheck.forbidden({&"cross": true}, &"LH", "R/H02/hand_1", Vector2(0.4, 1.8), pel, 0.0, keys, att), "크로스 금지: 왼손이 오른손 너머")
	runner.check(GateCheck.forbidden({&"match": true}, &"LH", "R/H01/hand_1", Vector2(0.2, 1.5), pel, 0.0, keys, att), "매치 금지: 같은 홀드")
	runner.check(GateCheck.forbidden({&"foot_swap": true}, &"LF", "R/F01/foot_1", Vector2(0.0, 0.3), pel, 0.0, {&"RF": "R/F01/foot_1"}), "풋스왑 금지: 다른 발 자리")


## 하이스텝을 금지하면 성립하는 자세가 줄어든다(같은 격자).
func test_forbid_reduces_poses() -> void:
	var r := _route()
	var res := GateCheck.check(r)
	runner.check(res.size() == 1 and res[0].tried > 50, "격자를 돌림 %s" % [res])
	runner.check(res[0].free > res[0].feasible, "기술을 쓰면 되는 자세가 더 많음 free %d > 금지 %d" % [res[0].free, res[0].feasible])


## 방향 기술(사이드풀·언더클링·개스턴) 없이 = 그 홀드를 위로 당기기로만 잡기.
func test_direction_override() -> void:
	var ci := ContactInfo.make("k", Vector2.ZERO, 1.0, &"sidepull", &"")
	ci.axis = Vector2(1, 0)
	var o := GateCheck.as_pull(ci)
	runner.check(o.mode == &"pull" and o.axis.is_equal_approx(Vector2(0, 1)) and ci.axis.is_equal_approx(Vector2(1, 0)), "위로 당기기로 바꾼 복사본")


## 탐색기 기술 금지: 탐색 자체가 그 기술이 필요한 이동을 뺀다(크로스 수업은 크로스 없이 길 없음, 있으면 길 있음).
func test_explorer_forbid() -> void:
	var r := RouteDef.load_json(ContentIndex.route_path("C_CROSS_T"))
	runner.check(not PathExplorer.explore(r, {&"cross": true}).ok, "크로스 금지 → 길 없음")
	runner.check(PathExplorer.explore(r).ok, "금지 없으면 길 있음")
