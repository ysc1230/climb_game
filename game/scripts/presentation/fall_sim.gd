class_name FallSim
extends RefCounted
## 표현 전용 낙하 인형(docs/superpowers/specs/2026-11-19-1-feel-design.md §1.2, 2026-11-19 사용자: "캐릭터의 현재 무게중심과
## 자세에 따라 물리법칙에 의거해서 떨어진 뒤 조언"). 판정의 낙하(ClimbSession._fall_tick)와 별개다.
## 그림 목표 점(ClimberPose.compute의 t와 같은 이름)을 막대로 이은 베를레 인형. 붙어 있던 손 점은 놓는 시각까지 고정.
## 벽(z ≥ wall_z)과 바닥 매트(y ≥ mat_top_y)에 부딪히고, 매트에서 작게 튕긴 뒤 마찰로 멈춘다.

const RELEASE_DELAY := 0.12  # 아직 붙은 손을 놓기까지(초)
const MAX_TIME := 1.6
const REST_SPEED := 0.05     # m/s, 모든 점이 이보다 느리면 멈춤
const BOUNCE := 0.2
const FRICTION := 0.5        # 바닥·벽에 닿은 점의 미끄러짐 남김 비율
const GRAVITY := Vector3(0, -9.8, 0)
const ITERATIONS := 14
## 막대(뼈대 + 몸통이 접히지 않게 하는 버팀대).
const EDGES := [
	["pelvis", "spine"], ["spine", "chest"], ["chest", "neck"], ["neck", "head"], ["head", "head_top"],
	["chest", "shoulder_L"], ["chest", "shoulder_R"], ["neck", "shoulder_L"], ["neck", "shoulder_R"],
	["shoulder_L", "shoulder_R"], ["shoulder_L", "elbow_L"], ["elbow_L", "wrist_L"], ["wrist_L", "hand_L"],
	["shoulder_R", "elbow_R"], ["elbow_R", "wrist_R"], ["wrist_R", "hand_R"],
	["pelvis", "hip_L"], ["pelvis", "hip_R"], ["hip_L", "hip_R"],
	["hip_L", "knee_L"], ["knee_L", "ankle_L"], ["ankle_L", "toe_L"],
	["hip_R", "knee_R"], ["knee_R", "ankle_R"], ["ankle_R", "toe_R"],
	["shoulder_L", "hip_L"], ["shoulder_R", "hip_R"], ["shoulder_L", "hip_R"], ["shoulder_R", "hip_L"],
	["spine", "hip_L"], ["spine", "hip_R"], ["head", "shoulder_L"], ["head", "shoulder_R"],
]

var _pos := {}
var _prev := {}
var _pins := {}      # 점 이름 → 놓는 시각(초)
var _len := []       # EDGES마다 시작 길이
var _mat := 0.0
var _wall := 0.0
var elapsed := 0.0
var _done := false
var _last_dt := 1.0 / 60.0


## points: 이름 → Vector3(EDGES의 모든 이름). vel: 시작 몸 속도. pins: 고정 점 → 놓는 시각.
func start(points: Dictionary, vel: Vector3, pins: Dictionary, mat_top_y: float, wall_z: float) -> void:
	_mat = mat_top_y
	_wall = wall_z
	_pins = pins.duplicate()
	_pos = {}
	_prev = {}
	var names := {}
	for e in EDGES:
		names[e[0]] = true
		names[e[1]] = true
	for k in points:
		if points[k] is Vector3 and names.has(k):  # "up" 같은 방향 값은 점이 아니다
			var p: Vector3 = points[k]
			p.y = maxf(p.y, _mat)
			p.z = maxf(p.z, _wall)
			_pos[k] = p
			_prev[k] = p - vel * _last_dt
	_len = []
	for e in EDGES:
		_len.append((_pos[e[0]] as Vector3).distance_to(_pos[e[1]]))
	elapsed = 0.0
	_done = false


func _pinned(k: String) -> bool:
	return _pins.has(k) and elapsed < float(_pins[k])


func step(dt: float) -> void:
	if _done or dt <= 0.0:
		return
	_last_dt = dt
	elapsed += dt
	for k in _pos:
		if _pinned(k):
			_prev[k] = _pos[k]
			continue
		var p: Vector3 = _pos[k]
		var v: Vector3 = (p - (_prev[k] as Vector3)) * 0.995
		_prev[k] = p
		_pos[k] = p + v + GRAVITY * dt * dt
	for it in ITERATIONS:
		for i in EDGES.size():
			var a: String = EDGES[i][0]
			var b: String = EDGES[i][1]
			var pa: Vector3 = _pos[a]
			var pb: Vector3 = _pos[b]
			var d := pb - pa
			var l := d.length()
			if l < 1e-6:
				continue
			var wa := 0.0 if _pinned(a) else 1.0
			var wb := 0.0 if _pinned(b) else 1.0
			if wa + wb == 0.0:
				continue
			var corr := d * ((l - float(_len[i])) / l / (wa + wb))
			_pos[a] = pa + corr * wa
			_pos[b] = pb - corr * wb
		_collide()
	var fastest := 0.0
	for k in _pos:
		fastest = maxf(fastest, ((_pos[k] as Vector3) - (_prev[k] as Vector3)).length() / dt)
	if elapsed >= MAX_TIME or (elapsed > 0.3 and fastest < REST_SPEED):
		_done = true


func _collide() -> void:
	for k in _pos:
		var p: Vector3 = _pos[k]
		var q: Vector3 = _prev[k]
		if p.y < _mat:
			var vy := p.y - q.y
			p.y = _mat
			q.y = p.y + vy * BOUNCE
			q.x = p.x - (p.x - q.x) * FRICTION
			q.z = p.z - (p.z - q.z) * FRICTION
		if p.z < _wall:
			var vz := p.z - q.z
			p.z = _wall
			q.z = p.z + vz * BOUNCE
		_pos[k] = p
		_prev[k] = q


func points() -> Dictionary:
	return _pos


func done() -> bool:
	return _done


## 끝 자세로 바로 간다(화면을 눌러 건너뛰기).
func skip() -> void:
	var guard := 0
	while not _done and guard < 400:
		step(1.0 / 60.0)
		guard += 1
	_done = true
