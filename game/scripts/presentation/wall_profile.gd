class_name WallProfile
extends RefCounted
## 꺾이는 벽의 모양(docs/57 §5, 표현 전용). 판정은 벽면을 펼친 좌표(x, s = 벽면을 따라 잰 높이, z = 벽에서 나온 깊이)이고,
## 화면은 높이마다 그 각도(RouteDef.angle_at)로 벽면을 접는다: 벽면 선 O(s) = ∫ (0, cos a, sin a) ds,
## 점 (x, s, z) → O(s) + x·X + z·N(s), N = (0, −sin a, cos a). 구간이 하나면 예전 벽 묶음 회전(X축 θ)과 같다.
## 아래 끝 s0 아래·위 끝 s1 위는 끝 각도로 곧게 잇는다.

const STEP := 0.01

var s0 := -1.0
var s1 := 4.0
var _ang: PackedFloat32Array = []   # 표 i: s = s0 + i·STEP의 각도(라디안)
var _oy: PackedFloat32Array = []    # 벽면 선 O(s)의 y
var _oz: PackedFloat32Array = []    # 벽면 선 O(s)의 z


func _init(route: RouteDef, p_s0 := -1.0, p_s1 := 4.0) -> void:
	s0 = p_s0
	s1 = maxf(p_s1, p_s0 + STEP * 2.0)
	var n := int(ceil((s1 - s0) / STEP)) + 1
	_ang.resize(n)
	_oy.resize(n)
	_oz.resize(n)
	# 각도: 구간 경계 ±WALL_BLEND(섞는 곳)만 angle_at으로, 나머지는 그 구간 각도 그대로(1만 칸을 다 부르면 100m 벽에서 13ms, 2026-11-26 최적화)
	var secs: Array = route.wall_sections
	var cur := deg_to_rad(route.angle_at(s0) if secs.is_empty() else float(secs[0].deg))
	var j := 1
	for i in n:
		var s := s0 + i * STEP
		while j < secs.size() and float(secs[j].from_y) + RouteDef.WALL_BLEND <= s:
			cur = deg_to_rad(float(secs[j].deg))
			j += 1
		_ang[i] = deg_to_rad(route.angle_at(s)) if j < secs.size() and s > float(secs[j].from_y) - RouteDef.WALL_BLEND else cur
	# 0에서 0으로 맞추고(벽 아래 가장자리 y = 0, z = 0이 예전 회전 축) 사다리꼴로 적분
	var i0 := clampi(int(round(-s0 / STEP)), 0, n - 1)
	_oy[i0] = (s0 + i0 * STEP) * cos(_ang[i0])
	_oz[i0] = (s0 + i0 * STEP) * sin(_ang[i0])
	# 곧은 구간은 각도가 같아 cos·sin을 다시 쓴다(100m 벽이면 표가 1만 칸, 2026-11-26 최적화)
	var la := INF
	var dy := 0.0
	var dz := 0.0
	for i in range(i0 + 1, n):
		var a := (_ang[i - 1] + _ang[i]) * 0.5
		if a != la:
			la = a
			dy = STEP * cos(a)
			dz = STEP * sin(a)
		_oy[i] = _oy[i - 1] + dy
		_oz[i] = _oz[i - 1] + dz
	la = INF
	for i in range(i0 - 1, -1, -1):
		var a := (_ang[i + 1] + _ang[i]) * 0.5
		if a != la:
			la = a
			dy = STEP * cos(a)
			dz = STEP * sin(a)
		_oy[i] = _oy[i + 1] - dy
		_oz[i] = _oz[i + 1] - dz


## 벽면 높이 s의 각도(라디안).
func angle_rad(s: float) -> float:
	var f := clampf((s - s0) / STEP, 0.0, _ang.size() - 1.0)
	var i := mini(int(f), _ang.size() - 2)
	return lerpf(_ang[i], _ang[i + 1], f - i)


## 벽면 선 위의 점(x = 0, z = 0).
func origin(s: float) -> Vector3:
	var n := _ang.size()
	if s <= s0:
		return Vector3(0, _oy[0], _oz[0]) + Vector3(0, cos(_ang[0]), sin(_ang[0])) * (s - s0)
	if s >= s0 + (n - 1) * STEP:
		return Vector3(0, _oy[n - 1], _oz[n - 1]) + Vector3(0, cos(_ang[n - 1]), sin(_ang[n - 1])) * (s - (s0 + (n - 1) * STEP))
	var f := (s - s0) / STEP
	var i := mini(int(f), n - 2)
	var t := f - i
	return Vector3(0, lerpf(_oy[i], _oy[i + 1], t), lerpf(_oz[i], _oz[i + 1], t))


## 벽면 높이 s의 벽 틀: X 오른쪽, Y 벽면을 따라 위, Z 벽에서 나오는 쪽.
func basis_at(s: float) -> Basis:
	return Basis(Vector3.RIGHT, angle_rad(s))


## 벽면 높이 s의 틀(원점 = 벽면 선 위 점). frame(s) * (x, 0, z) = point((x, s, z)).
func frame(s: float) -> Transform3D:
	return Transform3D(basis_at(s), origin(s))


## 펼친 벽 좌표 → 월드(접은 벽).
func point(p: Vector3) -> Vector3:
	return origin(p.y) + basis_at(p.y) * Vector3(p.x, 0.0, p.z)


## 월드 높이 → 벽면 높이 s(벽면 선 위, 각도 < 90°라 오름차순). 카메라·추락 장면용.
func s_at_world_y(wy: float) -> float:
	var n := _ang.size()
	if wy <= _oy[0]:
		return s0 + (wy - _oy[0]) / maxf(cos(_ang[0]), 0.05)
	if wy >= _oy[n - 1]:
		return s0 + (n - 1) * STEP + (wy - _oy[n - 1]) / maxf(cos(_ang[n - 1]), 0.05)
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _oy[mid] <= wy:
			lo = mid
		else:
			hi = mid
	return s0 + (lo + (wy - _oy[lo]) / maxf(_oy[hi] - _oy[lo], 1e-6)) * STEP


## 깊이 z 면의 월드 단면 [(y, z)] (y 오름차순, 10cm마다). 추락 장면이 벽에 부딪히는 면.
func world_profile(z: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var s := s0
	while s <= s1 + 1e-6:
		var q := point(Vector3(0, s, z))
		out.append(Vector2(q.y, q.z))
		s += 0.1
	return out


## 월드 점 p에서 (y, z) 단면으로 가장 가까운 벽면 선의 높이 s. 벽이 아래로 꺾이면(270°보다 더) 높이로는 자리가 여럿이라
## s_at_world_y(이분 탐색)가 엉뚱한 벽면을 잡는다(2026-11-27 벽 모양 점검). 10cm마다 훑고 그 둘레를 1cm마다.
func nearest_s(p: Vector3) -> float:
	var n := _ang.size()
	var best := 0
	var bd := INF
	for i in range(0, n, 10):
		var d := Vector2(_oy[i] - p.y, _oz[i] - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	for i in range(maxi(0, best - 10), mini(n, best + 11)):
		var d := Vector2(_oy[i] - p.y, _oz[i] - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return s0 + best * STEP


## 월드 점 p가 가장 가까운 벽면에서 gap보다 가깝거나 벽 뒤면 벽면 법선 쪽으로 gap까지 민다(시점 카메라가 벽을 뚫지 않게).
## 밀면 자리가 바뀌므로 두 번 맞춘다. 벽 판 폭 밖도 같은 면으로 본다(옆으로 돌아도 벽 뒤로 못 감).
func push_in_front(p: Vector3, gap: float) -> Vector3:
	for i in 2:
		var f := frame(nearest_s(p))
		var lz := (f.affine_inverse() * p).z
		if lz >= gap:
			break
		p += f.basis.z * (gap - lz)
	return p

