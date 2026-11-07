extends SceneTree
## 손 뻗기 시나리오 점검(AnatomySweep.run_reach): 루트 × 양손 × 어깨 기준 목표 × 속도. 떨림·뒤집힘·위반을 센다.
## 실행: godot --headless --script res://tools/anatomy_reach.gd -- [루트 수 상한=99]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lim := int(args[0]) if args.size() > 0 else 99
	var poses := 0
	var flips := 0
	var counts := {}
	var forced := {}
	var jit := {}
	var jit_sim := {}
	var jit_big := {}
	var worst := []
	var targets := [[0.0, 0.7], [0.35, 0.6], [-0.3, 0.6], [0.6, 0.2], [0.5, -0.3], [-0.2, 0.2], [0.2, -0.5], [-0.35, 0.35]]
	var n := 0
	for r in ContentIndex.load_all().all_routes():
		n += 1
		if n > lim:
			break
		for hand in [&"LH", &"RH"]:
			for tg in targets:
				for sp in [0.8, 2.0]:
					var sw := AnatomySweep.run_reach(r, hand, tg[0], tg[1], sp)
					poses += sw.poses
					for l in sw.flips:
						flips += sw.flips[l]
					for k in sw.counts:
						counts[k] = counts.get(k, 0) + sw.counts[k]
						forced[k] = forced.get(k, 0) + sw.forced.get(k, 0)
					for k in sw.jitter:
						jit[k] = jit.get(k, 0) + sw.jitter[k]
					for k in sw.jitter_big:
						jit_big[k] = jit_big.get(k, 0) + sw.jitter_big[k]
					for k in sw.jitter_sim:
						jit_sim[k] = jit_sim.get(k, 0) + sw.jitter_sim[k]
					var big := 0
					for k in sw.jitter_big:
						big += sw.jitter_big[k]
					if big > 0:
						worst.append([big, r.route_id, hand, tg, sp, sw.jitter_big])
	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("== 손 뻗기: 자세 %d, 관절 뒤집힘 %d" % [poses, flips])
	print("  떨림(표현): %s" % [jit])
	print("  큰 떨림(1cm/틱 넘음): %s" % [jit_big])
	print("  떨림(판정): %s" % [jit_sim])
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		print("  %-16s %5d (%.2f%%) 강제 %d" % [k, counts[k], 100.0 * counts[k] / maxf(poses, 1), forced[k]])
	for w in worst.slice(0, 6):
		print("  떨림 많은 경우: ", w)
	quit()
