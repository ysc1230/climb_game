class_name ContentCheck
extends RefCounted
## 문제 하나의 콘텐츠 검사(docs/28 §7.4). 순서:
## 1. 저작 오류 없음(RouteDef 로드 전 불변 조건) → 2. 의도 경로를 SessionBot으로 완등 →
## 3. check_swapped면 좌우 순서 교체 경로(RouteBot.swapped_pairs)도 완등 →
## 4. required_techniques마다 그 기술을 금지한 재생이 crux 인덱스 i에서 i 또는 i+1 단계에 실패(국소 검사) →
## 5. 등급 기준(GradeRules) 경고는 "경고:" 줄로 남기되 ok에 영향 없음.
## 튜토리얼(course_slot tutorial)은 의도 경로 검사만 한다.

## 패드 기술 → 세션 검증기 금지 플래그(ClimbSession.forbid, Task 3).
const PAD_FORBID := {
	&"T_HIGH_STEP": &"high_step",
	&"T_CROSS": &"cross",
	&"T_FLAG": &"flag",
	&"T_MATCH": &"match",
	&"T_FOOT_SWAP": &"foot_swap",
	&"T_LOCK_OFF": &"lock_off",
	&"T_SIDEPULL": &"grip_auto",
	&"T_GASTON": &"grip_auto",
	&"T_UNDERCLING": &"grip_auto",
	&"T_DEADPOINT": &"deadpoint",
}


## 반환 {ok: bool, lines: PackedStringArray, metrics: Dictionary(의도 경로 측정값, 재생하지 못했으면 빈 사전)}.
static func check(route: RouteDef) -> Dictionary:
	var lines: PackedStringArray = []
	var res := {"ok": false, "lines": lines, "metrics": {}}
	if not route.errors.is_empty():
		for e in route.errors:
			lines.append("[저작 오류] " + e)
		return res
	var bot := SessionBot.run(route, route.intended_moves)
	res.metrics = bot.metrics
	_add_run(lines, "의도 경로", bot)
	if not bot.ok():
		return res
	var ok := true
	if route.course_slot == "tutorial":
		res.ok = true
		return res
	if route.check_swapped:
		var sw := SessionBot.run(route, RouteBot.swapped_pairs(route.intended_moves))
		_add_run(lines, "좌우 순서 교체", sw)
		ok = ok and sw.ok()
	for tech in route.required_techniques:
		ok = _check_required(route, tech, lines) and ok
	lines.append("측정값: 도달 여유 최소 %.3fm, 손 반폭 최소 %.3fm, 최대 손 사용률 %.2f, 최저 손 피로 %.0f, 이동 %d, %.2f초" % [
		bot.metrics.min_reach_margin, bot.metrics.min_half_width, bot.metrics.max_hand_u, bot.metrics.min_stamina, bot.metrics.moves, bot.metrics.seconds])
	lines.append_array(GradeRules.warnings(route, bot.metrics))
	res.ok = ok
	return res


static func _add_run(lines: PackedStringArray, title: String, bot: SessionBot) -> void:
	lines.append("-- %s: %s" % [title, "통과" if bot.ok() else "실패"])
	for l in bot.log:
		lines.append("   " + l)


## 기술 없이 재생: 금지한 재생이 crux 단계 i 또는 i+1에서 실패해야 "필요"다.
static func _check_required(route: RouteDef, tech: StringName, lines: PackedStringArray) -> bool:
	if not route.crux_steps.has(tech):
		lines.append("필요 기술 %s: crux_steps에 인덱스 없음" % tech)
		return false
	var i: int = route.crux_steps[tech]
	var steps := route.intended_moves.duplicate()
	var forbid := {}
	if TechniqueDefs.button_ids().has(tech):
		var m: Array = steps[i]
		if m.size() < 2 or StringName(str(m[1])) != tech:
			lines.append("필요 기술 %s: crux 단계 #%d가 그 기술 단계가 아님 %s" % [tech, i, m])
			return false
		steps[i] = [m[0], m[2]] if m.size() == 3 else []  # 홀드로 옮기는 기술은 같은 홀드를 패드로, 제자리 기술은 건너뜀
	elif PAD_FORBID.has(tech):
		forbid[PAD_FORBID[tech]] = true
	else:
		lines.append("필요 기술 %s: 금지 방법이 없는 기술" % tech)
		return false
	var bot := SessionBot.run(route, steps, forbid)
	if bot.ok():
		lines.append("필요 기술 %s: 금지해도 완등함 → 필요 기술 아님(등급·태그를 고칠 것)" % tech)
		return false
	if bot.failed_step == i or bot.failed_step == i + 1:
		lines.append("필요 기술 %s: 금지하면 #%d에서 실패(통과) — %s" % [tech, bot.failed_step, bot.failure])
		return true
	lines.append("필요 기술 %s: 금지 재생이 crux #%d·#%d가 아닌 곳에서 실패 — %s" % [tech, i, i + 1, bot.failure])
	return false
