extends SceneTree
## 해부학 점검 스윕(AnatomySweep)을 모든 루트에 돌려 위반 종류별 횟수·예시와 비틀림 분포를 출력한다.
## 실행: godot --headless --script res://tools/anatomy_sweep.gd -- [루트당 틱=3000] [시드=1]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 3000
	var seed := int(args[1]) if args.size() > 1 else 1
	var idx := ContentIndex.load_all()
	var counts := {}
	var forced := {}
	var examples := {}
	var tw := {&"arm": [], &"leg": []}
	var poses := 0
	var flips := {}
	var flip_ex := {}
	var us_total := 0
	var us_max := 0
	for r in idx.all_routes():
		var sw := AnatomySweep.run(r, n, seed)
		poses += sw.poses
		us_total += sw.compute_us_total
		us_max = maxi(us_max, sw.compute_us_max)
		var line := "%-16s 자세 %5d 위반 %5d" % [r.route_id, sw.poses, sw.total()]
		print(line)
		for k in sw.counts:
			counts[k] = counts.get(k, 0) + sw.counts[k]
			forced[k] = forced.get(k, 0) + sw.forced.get(k, 0)
			if not examples.has(k):
				examples[k] = [r.route_id, sw.examples[k]]
		for g in tw:
			tw[g].append_array(sw.twists[g])
		for l in sw.flips:
			flips[l] = flips.get(l, 0) + sw.flips[l]
			if not flip_ex.has(l):
				flip_ex[l] = [r.route_id, sw.flip_examples[l]]
	print("== 합계: 자세 %d, 자세 계산 평균 %.0fµs 최대 %dµs" % [poses, float(us_total) / maxf(poses, 1), us_max])
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		print("  %-20s %6d (%.2f%%) 강제 %d  예: %s" % [k, counts[k], 100.0 * counts[k] / maxf(poses, 1), forced[k], examples[k]])
	for g in tw:
		var a: Array = tw[g]
		a.sort()
		if a.is_empty():
			continue
		var pct := func(p: float) -> float: return a[clampi(int(p * (a.size() - 1)), 0, a.size() - 1)]
		print("  비틀림 %s: 최소 %.0f, 1%% %.0f, 50%% %.0f, 99%% %.0f, 최대 %.0f (n=%d)" % [g, a[0], pct.call(0.01), pct.call(0.5), pct.call(0.99), a[-1], a.size()])
	print("== 관절 뒤집힘(한 틱 %.0f° 넘는 굽힘 방향 변화): %s" % [AnatomySweep.FLIP_DEG, flips])
	for l in flip_ex:
		print("  %s 예: %s" % [l, flip_ex[l]])
	quit()
