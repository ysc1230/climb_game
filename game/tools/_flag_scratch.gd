extends SceneTree
## 임시 실험 도구(삭제 예정). 인자: <route json 경로> <steps JSON> [forbid,콤마] [drop]
## drop: flag 단계에서 균형 발이 안 되어도(Free) 계속 진행.

class Bot extends SessionBot:
	var allow_drop := false
	var verbose := false
	var max_gain := -INF
	var max_imb := 0
	var last_gain := 0.0
	var gain_at := Vector2.ZERO
	func _tick() -> String:
		var e := super._tick()
		max_imb = maxi(max_imb, session.rules.imbalance_ticks)
		if true:
			var b := session.body
			var r: Dictionary = session.rules.last
			var st := []
			for l in session.limbs:
				st.append("%s:%s(%.2f,%.2f)" % [l, session.limbs[l].state.left(3), session.limbs[l].pos.x, session.limbs[l].pos.y])
			var fc := ""
			var ru := session.rules
			if session.limbs[&"RF"].state == "Dragging":
				var eps := {}
				for l in session.limbs:
					if not session.attached().has(l):
						eps[l] = session.limbs[l].pos
				var here := ru.evaluate(b.pos, b.angle, session.attached(), eps, false, ru.feet_eligible, b.yaw)
				var re := eps.duplicate()
				re[&"RF"] = PoseSolver.clamp_endpoint(b.pos, b.angle, &"RF", eps[&"RF"], b.pos + Vector2(0.25, -0.70), b.yaw)
				var rest := ru.evaluate(b.pos, b.angle, session.attached(), re, false, ru.feet_eligible, b.yaw)
				var g := ClimbRules.flag_cost(rest) - ClimbRules.flag_cost(here)
				last_gain = g
				if g > max_gain:
					max_gain = g
					gain_at = eps[&"RF"]
				fc = "cost here %.3f rest %.3f u=%s" % [ClimbRules.flag_cost(here), ClimbRules.flag_cost(rest), here.get("u", {})]
			if verbose: log.append(fc + "  t%d p=(%.3f,%.3f) %s barn=%s fr=%s %s %s" % [_ticks, b.pos.x, b.pos.y, session.rules.phase_name(), [snapped(r.get("barn",{}).get("tau",0.0),0.001), snapped(r.get("barn",{}).get("capacity",0.0),0.001), r.get("barn",{}).get("applies",false)], session.rules.flag_ready, " ".join(st), e])
		return e
	func _flag(foot: StringName, point: Vector2) -> String:
		var e := super._flag(foot, point)
		if allow_drop and session.limbs[foot].state == "Free":
			log.append("(발 떨굼) flag_ready=%s" % [session.rules.flag_ready])
			return ""
		return e


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var route := RouteDef.load_json(a[0])
	if not route.errors.is_empty():
		print("ERR ", route.errors)
		quit(1)
		return
	var steps = route.intended_moves if a[1] == "-" else JSON.parse_string(a[1])
	var forbid := {}
	if a.size() > 2 and a[2] != "-":
		for f in a[2].split(","):
			forbid[StringName(f)] = true
	var bot := Bot.new()
	bot.allow_drop = a.size() > 3 and a[3].contains("drop")
	bot.verbose = a.size() > 3 and a[3].contains("v")
	bot.route = route
	bot.session = ClimbSession.new(route)
	bot.session.forbid = forbid
	bot._play(steps)
	for l in bot.log:
		print("  ", l)
	print("max_gain=%.4f at %s release_gain=%.4f max_imb=%d" % [bot.max_gain, bot.gain_at, bot.last_gain, bot.max_imb])
	print("failed_step=%d ok=%s metrics=%s" % [bot.failed_step, bot.ok(), bot.metrics])
	quit(0)
