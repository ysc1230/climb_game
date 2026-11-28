extends SceneTree
## R7 관문 검사(작업 5 §5.1, docs/48 §4 R7). 문제마다 ① 관문 격자 검사(기술 없이 성립하는 자세 수, 0이어야 진짜 관문)
## ② 탐색기 기술 금지(관문 기술을 모두 금지하고 길을 찾음, "길 없음"이어야 함)를 출력한다.
## 사용: godot --headless --path game --script res://tools/gate_check.gd [-- route_id ...] [--no-explore]
## 인자가 없으면 관문이 있는 일반 문제 + 기술 수업 6개(LESSON_GATES).

## 기술 수업은 score_gates가 없어 여기서 관문을 적는다(docs/47의 "기술로 하기" 단계).
const LESSON_GATES := {
	"C_HIGH_T": [{"slot": "C_HIGH_T/F05/foot_1", "technique": "T_HIGH_STEP"}],
	"C_MATCH_T": [{"slot": "C_MATCH_T/M01/hand_1", "technique": "T_MATCH"}],
	"C_FSWAP_T": [{"slot": "C_FSWAP_T/F04/foot_1", "technique": "T_FOOT_SWAP"}],
	"C_FMATCH_T": [{"slot": "C_FMATCH_T/B01/hand_1", "technique": "T_FOOT_MATCH"}],
	"C_CROSS_T": [{"slot": "C_CROSS_T/H03/hand_1", "technique": "T_CROSS"}],
	"C_DYNO_T": [{"slot": "C_DYNO_T/G01/hand_1", "technique": "T_DYNO"}],
}


func _init() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var explore := not args.has("--no-explore")
	args.erase("--no-explore")
	var routes: Array = []
	for r in ContentIndex.load_all().all_routes():
		if (args.is_empty() and (not r.score_gates.is_empty() or LESSON_GATES.has(r.route_id))) or args.has(r.route_id):
			if LESSON_GATES.has(r.route_id) and r.score_gates.is_empty():
				r.score_gates = LESSON_GATES[r.route_id]
				if r.route_id == "C_MATCH_T":
					r.crux_steps = {&"T_MATCH": 1}  # 오른손이 M01을 먼저 잡고 왼손이 모으는 단계
			routes.append(r)
	for r in routes:
		_report(r, explore)
	quit(0)


func _report(r: RouteDef, explore: bool) -> void:
	print("== %s %s %s" % [r.route_id, r.grade, r.name_ko])
	var forbid := {}
	var pull := false
	for g in GateCheck.check(r):
		if g.error != "":
			print("  관문 %s #%d: 앞까지 재생 실패 %s" % [g.technique, g.index, g.error])
			continue
		var verdict := "검사 불가(이 자리는 정적 자세로 못 봄: 기술로도 성립 자세 0)" if g.free == 0 else ("진짜 관문" if g.feasible == 0 else ("뚫림(재생 확인: %s)" % g.breach_log if g.breach else "정적으로는 뚫림, 재생으로는 막힘(%s)" % g.breach_log))
		print("  관문 %s #%d %s → %s: 기술 없이 성립 %d / 닿는 자세 %d (금지 없이 %d) → %s" % [g.technique, g.index, g.limb, g.key, g.feasible, g.tried, g.free, verdict])
		var t: StringName = g.technique
		if GateCheck.DIRECTION.has(t):
			pull = true
		elif GateCheck.FORBID.has(t):
			forbid[GateCheck.FORBID[t]] = true
	if not explore:
		return
	if forbid.is_empty() and not pull:
		print("  탐색기: 금지할 패드 기술 없음(버튼 기술·다이노)")
		return
	var t0 := Time.get_ticks_msec()
	var base := PathExplorer.explore(r)
	if not base.ok:
		print("  탐색기: 금지 없이도 길을 못 찾음(%d ms) → 금지 결과로 관문을 말할 수 없음(하이스텝처럼 몸이 올라가는 동작은 탐색기가 못 봄)" % (Time.get_ticks_msec() - t0))
		return
	t0 = Time.get_ticks_msec()
	var res := PathExplorer.explore(r, forbid, pull)
	print("  탐색기 금지 %s%s: %s (%d ms, 펼친 상태 %d)" % [forbid.keys(), " +당기기만" if pull else "", "길 있음 → 관문 뚫림 %s" % [res.steps] if res.ok else "길 없음(통과)", Time.get_ticks_msec() - t0, res.expanded])
