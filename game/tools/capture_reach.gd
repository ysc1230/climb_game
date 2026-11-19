extends SceneTree
## 임시 확인 도구(작업 1 Task 5): 오른손을 홀드 쪽으로 끌어 놓은 장면을 찍고, 판정 점(빨강)을 겹쳐 그린다.
## 실행(창 필요): godot --path game --script res://tools/capture_reach.gd -- <out_prefix>

var play: Node
var frame := 0
var shots := [[-0.13, "above"], [0.13, "below"], [0.0, "on"]]
var idx := 0
var target := Vector2.ZERO
var prefix := "user://reach"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		prefix = args[0]


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		var g = root.get_node_or_null("Game")
		if g != null:
			g.current_route_id = "G_V3_03"
		play = load("res://scenes/play_3d.tscn").instantiate()
		root.add_child(play)
		return false
	var logic = play.get_node("UI/PlayTest")
	var s: ClimbSession = logic.session
	if frame == 60:
		# 오른손보다 위에 있는 가장 가까운 손 슬롯
		var rh: Vector2 = s.limbs[&"LH"].pos
		var best := INF
		for key in s.route.slots:
			var sl: Dictionary = s.route.slots[key]
			if sl.allowed.has(&"LH") and sl.has("hand_area") and sl.pos.y > rh.y + 0.05 and sl.pos.distance_to(rh) < minf(best, 0.55) and not s.occupied().has(key):
				best = sl.pos.distance_to(rh)
				target = sl.pos
		s.apply_input([{"type": "detach", "limb": &"LH"}])
	if frame >= 61 and idx < shots.size():
		var want: Vector2 = target + Vector2(0.0, -float(shots[idx][0]))
		var l: Dictionary = s.limbs[&"LH"]
		s.apply_input([{"type": "move", "limb": &"LH", "delta": (want - l.req)}])
		if frame % 90 == 0:
			var img := root.get_texture().get_image()
			var p: Vector2 = logic.w2s(l.pos)
			for dx in range(-5, 6):
				for dy in range(-5, 6):
					var q := Vector2i(int(p.x) + dx, int(p.y) + dy)
					if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
						img.set_pixelv(q, Color.RED)
			var c := Vector2i(clampi(int(p.x) - 200, 0, img.get_width() - 400), clampi(int(p.y) - 200, 0, img.get_height() - 400))
			img = img.get_region(Rect2i(c, Vector2i(400, 400)))
			img.resize(800, 800, Image.INTERPOLATE_NEAREST)
			img.save_png("%s_%s.png" % [prefix, shots[idx][1]])
			print("saved %s_%s.png pos=%s target=%s cand=%s" % [prefix, shots[idx][1], l.pos, target, not l.cand.is_empty()])
			idx += 1
	return idx >= shots.size()
