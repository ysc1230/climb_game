class_name GhostTrack
extends RefCounted
## 자세 기록(docs/superpowers/specs/2026-11-19-3-score-design.md §3.5): 내 최고 기록 고스트·시범 보기가 같이 쓴다. 노드 없음.
## 초당 10번 [시간, 골반 x·y, 몸 기울기, 돌림, LH·RH·LF·RF 끝 x·y, 붙음 비트]. 저장은 소수 셋째 자리.

const HZ := 10.0
const LIMBS := [&"LH", &"RH", &"LF", &"RF"]

var frames: Array = []
var _time := 0.0


func record(s: ClimbSession, dt: float) -> void:
	_time += dt
	if not frames.is_empty() and _time - float(frames.back()[0]) < 1.0 / HZ - 1e-6:
		return
	var f := [_time, s.body.pos.x, s.body.pos.y, s.body.angle, s.body.yaw]
	var bits := 0
	for i in LIMBS.size():
		var l: Dictionary = s.limbs[LIMBS[i]]
		var p: Vector2 = l.pos
		f.append(p.x)
		f.append(p.y)
		if l.state in ["Attached", "Armed"]:
			bits |= 1 << i
	f.append(bits)
	frames.append(f)


func duration() -> float:
	return float(frames.back()[0]) if not frames.is_empty() else 0.0


## t초의 자세 {pelvis, angle, yaw, limbs{limb: Vector2}, attached{limb: bool}}(사이는 직선 보간, 붙음은 앞 기록).
func sample(t: float) -> Dictionary:
	if frames.is_empty():
		return {}
	var i := 0
	while i + 1 < frames.size() and float(frames[i + 1][0]) <= t:
		i += 1
	var a: Array = frames[i]
	var b: Array = frames[mini(i + 1, frames.size() - 1)]
	var span := float(b[0]) - float(a[0])
	var w := clampf((t - float(a[0])) / span, 0.0, 1.0) if span > 1e-6 else 0.0
	var v := func(k: int) -> float: return lerpf(float(a[k]), float(b[k]), w)
	var out := {"pelvis": Vector2(v.call(1), v.call(2)), "angle": v.call(3), "yaw": v.call(4), "limbs": {}, "attached": {}}
	for j in LIMBS.size():
		out.limbs[LIMBS[j]] = Vector2(v.call(5 + 2 * j), v.call(6 + 2 * j))
		out.attached[LIMBS[j]] = (int(a[13]) >> j) & 1 == 1
	return out


## 골반이 그 높이에 처음 닿는 시각(시범 보기 "떨어진 곳부터"). 처음부터 넘었거나 못 닿으면 0.
func time_at_height(y: float) -> float:
	for f in frames:
		if float(f[2]) >= y:
			return float(f[0]) if f != frames[0] else 0.0
	return 0.0


func to_dict() -> Dictionary:
	var out := []
	for f in frames:
		out.append(f.map(func(x): return snappedf(float(x), 0.001)))
	return {"hz": HZ, "f": out}


static func from_dict(d) -> GhostTrack:
	var g := GhostTrack.new()
	if not d is Dictionary or not d.get("f") is Array:
		return g
	for f in d.f:
		if f is Array and f.size() == 14:
			g.frames.append(f.duplicate())
	if not g.frames.is_empty():
		g._time = g.duration()
	return g
