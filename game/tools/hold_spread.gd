extends SceneTree
## 홀드 간격 맞추기(docs/44): 간격 규칙을 어긴 홀드 쌍을 서로 밀어 낸다(정상 슬롯은 고정, 시작 홀드도 민다). 결과를 JSON에 쓴다.
## 사용: godot --headless --path game --script res://tools/hold_spread.gd -- G_V3_02 (파일을 고쳐 쓴다. 이후 route_check로 재생 확인)
func _init():
	for id in OS.get_cmdline_user_args():
		var path := ContentIndex.route_path(id)
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for it in 200:
			var route := _load(data)
			var moved := false
			var keys: Array = route.slots.keys()
			for i in keys.size():
				for j in range(i + 1, keys.size()):
					var a: String = keys[i]
					var b: String = keys[j]
					var ha := a.get_slice("/", 1)
					var hb := b.get_slice("/", 1)
					if ha == hb:
						continue
					var pa: Vector2 = route.slot_pos(a)
					var pb: Vector2 = route.slot_pos(b)
					var u := (pb - pa).normalized()
					var ra := HoldSpacing.radius(HoldSpacing.ellipse(route, a), u)
					var rb := HoldSpacing.radius(HoldSpacing.ellipse(route, b), u)
					var deficit := 2.0 * maxf(ra, rb) - (pa.distance_to(pb) - ra - rb) + 0.005
					if deficit <= 0.0:
						continue
					moved = true
					var wa := 0.0 if ha == "G01" else 1.0
					var wb := 0.0 if hb == "G01" else 1.0
					if wa + wb == 0.0:
						continue
					_shift(data, ha, -u * deficit * wa / (wa + wb))
					_shift(data, hb, u * deficit * wb / (wa + wb))
			if not moved:
				print(id, " 정리됨, 반복 ", it)
				break
		FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(data, " "))
	quit()


func _shift(data: Dictionary, hold_id: String, d: Vector2) -> void:
	for h in data.holds:
		if h.hold_id == hold_id:
			for s in h.slots:
				s.pos = [snappedf(float(s.pos[0]) + d.x, 0.005), snappedf(float(s.pos[1]) + d.y, 0.005)]


func _load(data: Dictionary) -> RouteDef:
	var tmp := "user://_spread_tmp.json"
	FileAccess.open(tmp, FileAccess.WRITE).store_string(JSON.stringify(data))
	return RouteDef.load_json(tmp)
