class_name GrabFeel
extends RefCounted
## 잡는 손맛(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.4). 세션 사건 하나 → {sound, vib_ms, vib_amp, puff}.
## 표현 전용. 손발 떼기는 소리 없음. 홀드 종류(작업 4)가 생기면 크기 대신 종류로 고른다.

const BIG_HW := 0.08
const SMALL_HW := 0.05
const WINDOW := 0.08  # 같은 소리·진동이 이 안에 또 오면 하나만(네 손발 동시 잡기)


static func pick(ev: Dictionary, slot: Dictionary) -> Dictionary:
	match str(ev.get("type", "")):
		"grab":
			if not PoseSolver.is_hand(StringName(ev.get("limb", &""))):
				return {"sound": &"step_foot", "vib_ms": 12, "vib_amp": 0.3, "puff": &"dust"}
			var ha: Dictionary = slot.get("hand_area", {})
			var hw := float(ha.get("half_width", 0.08))
			if hw >= BIG_HW or bool(ha.get("matchable", false)):
				return {"sound": &"grab_big", "vib_ms": 22, "vib_amp": 0.7, "puff": &"chalk"}
			if hw < SMALL_HW:
				return {"sound": &"grab_small", "vib_ms": 12, "vib_amp": 0.35, "puff": &"chalk_small"}
			return {"sound": &"grab_mid", "vib_ms": 18, "vib_amp": 0.5, "puff": &"chalk"}
		"miss":
			return {"sound": &"miss", "vib_ms": 0, "vib_amp": 0.0, "puff": &""}
	return {}


## 같은 소리·진동 겹침 막기.
class Gate:
	var _last := {}
	var _vibe := -INF

	func allow(sound: StringName, now_s: float) -> bool:
		if now_s - float(_last.get(sound, -INF)) < WINDOW:
			return false
		_last[sound] = now_s
		return true

	func allow_vibe(now_s: float) -> bool:
		if now_s - _vibe < WINDOW:
			return false
		_vibe = now_s
		return true
