extends SceneTree
## 다리 올리기 시나리오 점검(AnatomySweep.run_lift): 모든 루트 × 양발 × 가로 위치 × 높이 × 속도.
## 실행: godot --headless --script res://tools/anatomy_lift.gd


func _initialize() -> void:
	var poses := 0
	var flips := 0
	var counts := {}
	var forced := {}
	var flip_cases := []
	for r in ContentIndex.load_all().all_routes():
		for foot in [&"LF", &"RF"]:
			for ox in [-0.35, -0.15, 0.0, 0.15, 0.35]:
				for rise in [-0.25, 0.0]:
					for sp in [1.0]:
						var sw := AnatomySweep.run_lift(r, foot, ox, rise, sp)
						poses += sw.poses
						var f := 0
						for l in sw.flips:
							f += sw.flips[l]
						flips += f
						if f > 0 and flip_cases.size() < 8:
							flip_cases.append([r.route_id, foot, ox, rise, sp, sw.flips, sw.flip_examples])
						for k in sw.counts:
							counts[k] = counts.get(k, 0) + sw.counts[k]
							forced[k] = forced.get(k, 0) + sw.forced.get(k, 0)
	print("== 다리 올리기: 자세 %d, 관절 뒤집힘 %d" % [poses, flips])
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		print("  %-16s %5d (%.2f%%) 강제 %d" % [k, counts[k], 100.0 * counts[k] / maxf(poses, 1), forced[k]])
	for c in flip_cases:
		print("  뒤집힘 사례: ", str(c).substr(0, 300))
	quit()
