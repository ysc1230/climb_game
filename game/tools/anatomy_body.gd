extends SceneTree
## 몸 밀기 시나리오 점검(AnatomySweep.run_body_shift): 모든 루트 × 8방향. 손발을 붙인 채 몸을 밀 때의 무릎·팔꿈치.
func _initialize() -> void:
	var poses := 0
	var flips := 0
	var counts := {}
	var forced := {}
	var big := {}
	for r in ContentIndex.load_all().all_routes():
		for d in [[0.4, 0.0], [-0.4, 0.0], [0.0, 0.4], [0.0, -0.4], [0.3, 0.3], [-0.3, 0.3], [0.3, -0.3], [-0.3, -0.3]]:
			var sw := AnatomySweep.run_body_shift(r, d[0], d[1])
			poses += sw.poses
			for l in sw.flips:
				flips += sw.flips[l]
			for k in sw.counts:
				counts[k] = counts.get(k, 0) + sw.counts[k]
				forced[k] = forced.get(k, 0) + sw.forced.get(k, 0)
			for k in sw.jitter_big:
				big[k] = big.get(k, 0) + sw.jitter_big[k]
	print("== 몸 밀기: 자세 %d, 관절 뒤집힘 %d, 큰 떨림 %s" % [poses, flips, big])
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		print("  %-16s %5d (%.2f%%) 강제 %d" % [k, counts[k], 100.0 * counts[k] / maxf(poses, 1), forced[k]])
	quit()
