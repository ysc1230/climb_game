class_name HoldTips
extends RefCounted
## 처음 보는 홀드 종류 이름표(작업 4 §4.4): 루트 읽기 동안 종류마다 한 번, 그 종류의 가장 낮은 홀드 옆에 "슬로퍼" 같은 이름.
## 본 종류는 Progress.seen_tips에 "hold_<종류>"로 남는다. 탑과 옛 형식(종류 없음)은 띄우지 않는다. 노드 없음.

const SECONDS := 3.0  # 이름표가 떠 있는 시간


static func tip_id(type: String) -> String:
	return "hold_" + type


## [{type, key, text, tip}] — 낮은 홀드 순.
static func pick(route: RouteDef, seen: Array) -> Array:
	var best := {}
	for key in route.slots:
		var type := str(route.slots[key].get("hold_type", ""))
		if type == "" or type == "goal" or seen.has(tip_id(type)):
			continue
		if not best.has(type) or (route.slots[key].pos as Vector2).y < (route.slots[best[type]].pos as Vector2).y:
			best[type] = key
	var out := []
	for type in best:
		out.append({"type": type, "key": best[type], "text": HoldTypes.name_ko(type), "tip": tip_id(type)})
	out.sort_custom(func(a, b): return (route.slots[a.key].pos as Vector2).y < (route.slots[b.key].pos as Vector2).y)
	return out
