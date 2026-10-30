class_name SupportSolver
extends RefCounted
## docs/04 §4 벽면 내 준정적 지지 계산. 체중 1BW, 벽면 XY.
## 각 접점의 힘 = 축·양쪽 경계(±반각) 세 단위 방향의 비음수 조합, 조합 계수 합 ≤ max_load.
## 조건: 힘 합 = 위쪽 1BW, 무게중심 대리점 c 주위 모멘트 합 = 0.
## 여러 해 중 Σ w·u² + 0.001·Σcoef² 최소(w: 손 2.0, 발 1.0).
## 풀이: 등식·용량을 큰 가중치의 벌점 행으로 둔 비음수 최소제곱(Lawson–Hanson NNLS, Gram 행렬).
## 결과의 잔차가 허용치(힘 0.02BW, 모멘트 0.02BW·m) 안이면 Feasible, 밖이면 Infeasible,
## 반복 상한 초과·수치 오류는 Unresolved(docs/04: 플레이어 불균형으로 단정하지 않음).
## 벽 밖 모멘트(barn door)·마찰은 계산하지 않는다.

enum Status { FEASIBLE, INFEASIBLE, UNRESOLVED }

const HAND_HALF_ANGLE := 65.0
const HAND_MAX_LOAD := 1.10
const FOOT_HALF_ANGLE := 60.0
const FOOT_MAX_LOAD := 1.30
const FORCE_TOLERANCE := 0.02
const MOMENT_TOLERANCE := 0.02
const LOAD_COST_HAND := 2.0
const LOAD_COST_FOOT := 1.0
const REGULARIZER := 0.001
const PENALTY := 1.0e5
const STABLE_LOAD_RATIO := 0.80
const RECOVER_HAND_LOAD_RATIO := 0.35

# 무게중심 대리점 가중치(docs/04 §4, 게임용)
const W_TORSO := 0.60
const W_ARM := 0.05
const W_LEG := 0.15


## 무게중심 대리점. endpoints: 네 팔다리 말단의 현재 위치(붙은 접점·자유 말단 모두).
## 팔다리 중심은 관절·중간·말단 평균인데, 중간 관절을 직선 중점으로 근사해 (관절+말단)/2를 쓴다.
static func com_proxy(pelvis: Vector2, angle_deg: float, endpoints: Dictionary) -> Vector2:
	var up := Vector2(0, 1).rotated(deg_to_rad(angle_deg))
	var c := (pelvis + (pelvis + up * 0.78)) * 0.5 * W_TORSO
	for limb in PoseSolver.LIMBS:
		var j := PoseSolver.joint_position(pelvis, angle_deg, limb)
		var e: Vector2 = endpoints.get(limb, j)
		c += (j + e) * 0.5 * (W_ARM if PoseSolver.is_hand(limb) else W_LEG)
	return c


static func contact(limb: StringName, pos: Vector2) -> Dictionary:
	var hand := PoseSolver.is_hand(limb)
	return {"limb": limb, "pos": pos, "axis": Vector2(0, 1),
		"half_angle": HAND_HALF_ANGLE if hand else FOOT_HALF_ANGLE,
		"max_load": HAND_MAX_LOAD if hand else FOOT_MAX_LOAD}


## contacts: contact() 배열. 반환:
## {status, loads: {limb: BW}, u: {limb: 사용률}, force_residual, moment_residual, residual}
static func solve(contacts: Array, com: Vector2) -> Dictionary:
	var result := {"status": Status.INFEASIBLE, "loads": {}, "u": {}, "force_residual": 1.0, "moment_residual": 0.0, "residual": 1.0}
	if contacts.is_empty():
		return result
	var k := contacts.size()
	var dirs := []  # 접점별 세 방향
	for ct in contacts:
		var a: float = deg_to_rad(ct.half_angle)
		var ax: Vector2 = ct.axis
		dirs.append([ax, ax.rotated(a), ax.rotated(-a)])
	var n := k * 3 + k  # 조합 계수 + 용량 여유 변수
	var rows := []
	var rhs := []
	var sp := sqrt(PENALTY)
	# 힘 X, 힘 Y, 모멘트
	var fx := _zeros(n)
	var fy := _zeros(n)
	var mz := _zeros(n)
	for i in k:
		var r: Vector2 = contacts[i].pos - com
		for j in 3:
			var d: Vector2 = dirs[i][j]
			fx[i * 3 + j] = d.x * sp
			fy[i * 3 + j] = d.y * sp
			mz[i * 3 + j] = (r.x * d.y - r.y * d.x) * sp
	rows.append_array([fx, fy, mz])
	rhs.append_array([0.0, sp, 0.0])
	# 용량: Σcoef + slack = max_load
	for i in k:
		var cap := _zeros(n)
		for j in 3:
			cap[i * 3 + j] = sp
		cap[k * 3 + i] = sp
		rows.append(cap)
		rhs.append(sp * float(contacts[i].max_load))
	# 하중 비용: sqrt(w)/max_load · Σcoef
	for i in k:
		var w := LOAD_COST_HAND if PoseSolver.is_hand(contacts[i].limb) else LOAD_COST_FOOT
		var lc := _zeros(n)
		for j in 3:
			lc[i * 3 + j] = sqrt(w) / float(contacts[i].max_load)
		rows.append(lc)
		rhs.append(0.0)
	# 정규항
	for v in k * 3:
		var reg := _zeros(n)
		reg[v] = sqrt(REGULARIZER)
		rows.append(reg)
		rhs.append(0.0)
	var sol := nnls(rows, rhs, n)
	if not sol.ok:
		result.status = Status.UNRESOLVED
		return result
	var x: PackedFloat64Array = sol.x
	var force := Vector2.ZERO
	var moment := 0.0
	for i in k:
		var load := 0.0
		var r: Vector2 = contacts[i].pos - com
		for j in 3:
			var c := x[i * 3 + j]
			var f: Vector2 = dirs[i][j] * c
			force += f
			moment += r.x * f.y - r.y * f.x
			load += c
		result.loads[contacts[i].limb] = load
		result.u[contacts[i].limb] = load / float(contacts[i].max_load)
		if not is_finite(load):
			result.status = Status.UNRESOLVED
			return result
	result.force_residual = (force - Vector2(0, 1)).length()
	result.moment_residual = absf(moment)
	result.residual = sqrt(pow(result.force_residual, 2) + pow(result.moment_residual, 2))
	var over := false
	for limb in result.u:
		if result.u[limb] > 1.0 + FORCE_TOLERANCE:
			over = true
	if result.force_residual <= FORCE_TOLERANCE and result.moment_residual <= MOMENT_TOLERANCE and not over:
		result.status = Status.FEASIBLE
	return result


static func max_u(result: Dictionary) -> float:
	var m := 0.0
	for limb in result.u:
		m = maxf(m, result.u[limb])
	return m


static func _zeros(n: int) -> PackedFloat64Array:
	var a := PackedFloat64Array()
	a.resize(n)
	a.fill(0.0)
	return a


## Lawson–Hanson NNLS: min ||A x − b||², x ≥ 0. Gram 행렬 G = AᵀA, h = Aᵀb로 푼다.
static func nnls(rows: Array, rhs: Array, n: int) -> Dictionary:
	var g := []
	for i in n:
		g.append(_zeros(n))
	var h := _zeros(n)
	for r in rows.size():
		var row: PackedFloat64Array = rows[r]
		var b: float = rhs[r]
		for i in n:
			var ai := row[i]
			if ai == 0.0:
				continue
			h[i] += ai * b
			var gi: PackedFloat64Array = g[i]
			for j in n:
				if row[j] != 0.0:
					gi[j] += ai * row[j]
			g[i] = gi
	var x := _zeros(n)
	var passive := []
	var tol := 1.0e-9
	var outer := 0
	while outer < 4 * n:
		outer += 1
		var w := _grad(g, h, x, n)
		var best := -1
		var best_w := tol
		for j in n:
			if not passive.has(j) and w[j] > best_w:
				best_w = w[j]
				best = j
		if best < 0:
			return {"x": x, "ok": true}
		passive.append(best)
		var inner := 0
		while true:
			inner += 1
			if inner > 4 * n:
				return {"x": x, "ok": false}
			var z := _solve_passive(g, h, passive, n)
			if z.is_empty():
				return {"x": x, "ok": false}
			var all_pos := true
			for j in passive:
				if z[j] <= tol:
					all_pos = false
			if all_pos:
				x = z
				break
			var alpha := 1.0
			for j in passive:
				if z[j] <= tol:
					var denom := x[j] - z[j]
					if denom > 0.0:
						alpha = minf(alpha, x[j] / denom)
			for j in n:
				x[j] = x[j] + alpha * (z[j] - x[j])
			var keep := []
			for j in passive:
				if x[j] > tol:
					keep.append(j)
				else:
					x[j] = 0.0
			passive = keep
	return {"x": x, "ok": false}


static func _grad(g: Array, h: PackedFloat64Array, x: PackedFloat64Array, n: int) -> PackedFloat64Array:
	var w := _zeros(n)
	for i in n:
		var s := h[i]
		var gi: PackedFloat64Array = g[i]
		for j in n:
			s -= gi[j] * x[j]
		w[i] = s
	return w


## 활성 집합에 대해 G_PP z_P = h_P (부분 피벗 가우스 소거). 실패 시 빈 배열.
static func _solve_passive(g: Array, h: PackedFloat64Array, passive: Array, n: int) -> PackedFloat64Array:
	var m := passive.size()
	var a := []
	for r in m:
		var row := _zeros(m + 1)
		var gr: PackedFloat64Array = g[passive[r]]
		for c in m:
			row[c] = gr[passive[c]]
		row[m] = h[passive[r]]
		a.append(row)
	for col in m:
		var piv := col
		for r in range(col + 1, m):
			if absf(a[r][col]) > absf(a[piv][col]):
				piv = r
		if absf(a[piv][col]) < 1.0e-14:
			return PackedFloat64Array()
		if piv != col:
			var tmp = a[col]
			a[col] = a[piv]
			a[piv] = tmp
		var pr: PackedFloat64Array = a[col]
		for r in range(col + 1, m):
			var rr: PackedFloat64Array = a[r]
			var f := rr[col] / pr[col]
			if f == 0.0:
				continue
			for c in range(col, m + 1):
				rr[c] -= f * pr[c]
			a[r] = rr
	var sol := _zeros(m)
	for r in range(m - 1, -1, -1):
		var row: PackedFloat64Array = a[r]
		var s := row[m]
		for c in range(r + 1, m):
			s -= row[c] * sol[c]
		sol[r] = s / row[r]
	var z := _zeros(n)
	for r in m:
		if not is_finite(sol[r]):
			return PackedFloat64Array()
		z[passive[r]] = sol[r]
	return z
