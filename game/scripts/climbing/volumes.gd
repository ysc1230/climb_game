class_name Volumes
extends RefCounted
## 벽에 붙이는 볼륨(2026-11-28 사용자 "세로로도 구분하여 특정 영역의 벽의 각도를 조정해서 튀어나온 볼륨처럼", "어 둘다야":
## 면에 홀드를 달고, 볼륨 자체를 잡고 딛는다). 벽(높이마다 각도 하나인 띠)은 그대로 두고 그 위에 붙는 물체다.
## 볼륨 {id, shape: "box" | "wedge", x, y(가운데, 판정 벽 좌표), size: S/M/L, rot: 0/90/180/270(삼각의 두꺼운 쪽: 위·오른쪽·아래·왼쪽)}.
## 바닥(벽에 붙는 면)은 한 변 side의 정사각형. 상자는 앞면이 벽에서 depth만큼 나와 벽과 나란하고, 삼각은 얇은 쪽 0에서 두꺼운 쪽 depth까지 기운다.
## 모서리는 "볼륨 모서리"(hold_types volume) 칸이다: 판정은 보통 홀드와 같다(방향 = 볼륨 바깥, 반폭 = 변 절반, 합손·발 딛기).

const SHAPES := ["box", "wedge"]
const SIDE := {"S": 0.3, "M": 0.5, "L": 0.8}
const DEPTH := {"S": 0.18, "M": 0.3, "L": 0.4}
const MAX := 20


static func make(id: String, shape: String, x: float, y: float, size := "M", rot := 0) -> Dictionary:
	return {"id": id, "shape": shape if SHAPES.has(shape) else "box", "x": x, "y": y, "size": size if SIDE.has(size) else "M", "rot": posmod(int(round(rot / 90.0)) * 90, 360)}


static func side(v: Dictionary) -> float:
	return float(SIDE[v.size])


static func depth(v: Dictionary) -> float:
	return float(DEPTH[v.size])


static func center(v: Dictionary) -> Vector2:
	return Vector2(float(v.x), float(v.y))


## 삼각의 두꺼운 쪽(벽 평면 방향). 상자도 rot대로 돌려 두지만 쓰지 않는다.
static func dir(v: Dictionary) -> Vector2:
	return HoldTypes.rotate(Vector2(0, 1), float(v.rot)).round()


## 벽 평면의 점 p가 볼륨 바닥(정사각형, margin만큼 넓혀) 안인가.
static func contains(v: Dictionary, p: Vector2, margin := 0.0) -> bool:
	var h := side(v) * 0.5 + margin + 1e-5  # 모서리 위(꼭짓점)는 안: 부동소수 오차로 꼭짓점 깊이가 0이 돼 상자가 납작했다
	var d := p - center(v)
	return absf(d.x) <= h and absf(d.y) <= h


## p에서 볼륨 겉면이 벽에서 나온 깊이(바닥 밖은 0).
static func depth_at(v: Dictionary, p: Vector2) -> float:
	if not contains(v, p):
		return 0.0
	if v.shape == "box":
		return depth(v)
	var t := clampf((p - center(v)).dot(dir(v)) / side(v) + 0.5, 0.0, 1.0)
	return depth(v) * t


## p의 볼륨 겉면 법선(벽 틀: x 오른쪽, y 벽면 위, z 벽에서 나옴).
static func normal_at(v: Dictionary, _p: Vector2) -> Vector3:
	if v.shape == "box":
		return Vector3(0, 0, 1)
	var g := dir(v) * (depth(v) / side(v))  # 깊이 기울기
	return Vector3(-g.x, -g.y, 1.0).normalized()


## 모서리 칸 [{slot_id, pos, rot, depth}]. 상자: 위(t)·오른쪽(r)·아래(b)·왼쪽(l). 삼각: 두꺼운 모서리와 양옆(옆은 가운데 깊이).
static func edges(v: Dictionary) -> Array:
	var c := center(v)
	var h := side(v) * 0.5
	var all := [["edge_t", Vector2(0, 1), 0], ["edge_r", Vector2(1, 0), 90], ["edge_b", Vector2(0, -1), 180], ["edge_l", Vector2(-1, 0), 270]]
	var out: Array = []
	for e in all:
		var n: Vector2 = e[1]
		var dd := depth(v)
		if v.shape == "wedge":
			var k := n.dot(dir(v))
			if k < -0.5:
				continue  # 얇은 쪽은 벽과 맞닿아 잡을 데가 없다
			if absf(k) < 0.5:
				dd *= 0.5
		out.append({"slot_id": e[0], "pos": c + n * h, "rot": e[2], "depth": dd})
	return out


## 발 비비기 면(볼륨 면 칸) {slot_id, pos, depth}: 위를 보는 면만(아래가 두꺼운 삼각). 아래를 보거나 벽과 나란한 면에는 발을 비빌 수 없다.
static func face(v: Dictionary) -> Dictionary:
	if v.shape != "wedge" or dir(v).y > -0.5:
		return {}
	return {"slot_id": "face", "pos": center(v), "depth": depth_at(v, center(v))}


## 점 p가 놓인 볼륨(가장 앞으로 나온 것), 없으면 {}.
static func at(vols: Array, p: Vector2) -> Dictionary:
	var best := {}
	var bd := -1.0
	for v in vols:
		if contains(v, p) and depth_at(v, p) > bd:
			bd = depth_at(v, p)
			best = v
	return best


## 점 p 둘레(바닥 옆으로 margin까지)의 가장 앞으로 나온 볼륨 겉면 깊이: 바닥 안으로 끌어 잰다(관절 두께만큼 옆도 볼륨으로).
static func depth_near(vols: Array, p: Vector2, margin: float) -> float:
	var best := 0.0
	for v in vols:
		if contains(v, p, margin):
			var h := side(v) * 0.5
			var c := center(v)
			best = maxf(best, depth_at(v, Vector2(clampf(p.x, c.x - h, c.x + h), clampf(p.y, c.y - h, c.y + h))))
	return best


## 점 p의 볼륨 겉면 깊이(볼륨 밖 0).
static func mount_depth(vols: Array, p: Vector2) -> float:
	var v := at(vols, p)
	return 0.0 if v.is_empty() else depth_at(v, p)
