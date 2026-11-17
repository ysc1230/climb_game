extends RefCounted
## 벽 장식은 홀드와 겹치지 않고, 벽 판은 모든 홀드를 덮는다(2026-11-18 사용자: "오른쪽에 발판이 안 보여. 홀드가 아닌 것은
## 벽 밖에 두거나 홀드와 절대 겹치지 않게").

var runner

const P3 := preload("res://scenes/play_3d.gd")


func test_decor_never_overlaps_holds() -> void:
	var idx := ContentIndex.load_all()
	for r in idx.all_routes():
		var half_w := P3.wall_half_width(r.slots)
		var top: float = r.slots.values().reduce(func(a, s): return maxf(a, s.pos.y), 0.0) + 2.5
		var bad := 0
		for seed in 30:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed
			for d in P3.deco_spots(r.slots, half_w, top, rng):
				for key in r.slots:
					if Vector2(d[0], d[1]).distance_to(r.slots[key].pos) < d[2] * 0.8 + 0.35 - 0.0001:
						bad += 1
		runner.check(bad == 0, "%s 장식이 홀드와 겹침 %d" % [r.route_id, bad])
		for key in r.slots:
			runner.check(absf((r.slots[key].pos as Vector2).x) <= half_w - 0.45 + 0.0001, "%s 홀드 %s가 벽 판 안" % [r.route_id, key])
