class_name ClimbSnapshot
extends RefCounted
## 기술 판단기(docs/27 §7.1)의 입력: 확정된 틱의 등반 상태 복사본. 세션을 바꾸지 않는다.

var route: RouteDef
var body: BodyState          # 복사본(pos, vel, angle, ang_vel, yaw, yaw_vel)
var attached := {}           # limb → 접점 위치(Attached/Armed)
var contact_meta := {}       # limb → ContactInfo 복사본
var keys := {}               # limb → 슬롯 키(마지막으로 붙었던 슬롯)
var states := {}             # limb → "Attached"/"Armed"/"Dragging"/"Free"/"Flag"
var endpoints := {}          # limb → 실제 말단 위치(네 팔다리 모두)
var occupied := {}           # 슬롯 키 → [{limb, interval}]
var platform := false        # 플랫폼 지지 성립(두 발이 플랫폼 발판)
var phase := ClimbRules.Phase.STABLE
var last := {}               # 마지막 확정 힘 계산 결과
var loaded_feet: Array[StringName] = []
var feet_eligible: Array[StringName] = []
var stamina := {}
var imbalance_cause: StringName = &""
var profile := {}            # 지금의 목표 탐색 선호 거리(무브 프로필 + override)
var executing := false       # 기술 실행 중
var dragging := false        # 패드로 끄는 손발이 있음
var falling := false
var deadpoint_active := false  # 패드·기술 데드포인트 비행 중(손이 날아가는 동안)
var deadpoint_window := false  # 데드포인트 창이 열려 있는가(상승 중이거나 상승 종료 후 0.25초 이내)


static func from_session(s: ClimbSession) -> ClimbSnapshot:
	var snap := ClimbSnapshot.new()
	snap.route = s.route
	var b := BodyState.new(s.body.pos, s.body.angle)
	b.vel = s.body.vel
	b.ang_vel = s.body.ang_vel
	b.yaw = s.body.yaw
	b.yaw_vel = s.body.yaw_vel
	snap.body = b
	snap.attached = s.attached()
	for limb in s.limbs:
		var l: Dictionary = s.limbs[limb]
		snap.keys[limb] = l.key
		snap.states[limb] = l.state
		snap.endpoints[limb] = l.pos
		if snap.attached.has(limb) and l.get("contact") != null:
			snap.contact_meta[limb] = copy_contact(l.contact)
	snap.occupied = s.occupied()
	snap.platform = s.on_platform(snap.attached)
	snap.phase = s.rules.phase
	snap.last = s.rules.last.duplicate(true)
	snap.loaded_feet = s.rules.loaded_feet.duplicate()
	snap.feet_eligible = s.rules.feet_eligible.duplicate()
	snap.stamina = s.rules.stamina.duplicate()
	snap.imbalance_cause = s.rules.imbalance_cause
	snap.profile = s.rules.effective_profile()
	snap.executing = not s.runner.active.is_empty()
	snap.dragging = s.is_dragging()
	snap.falling = s.falling
	snap.deadpoint_active = not s.deadpoint.is_empty()
	snap.deadpoint_window = s.deadpoint_window()
	return snap


static func copy_contact(c: ContactInfo) -> ContactInfo:
	var n := ContactInfo.make(c.key, c.point, c.quality, c.mode, c.edge)
	n.axis = c.axis
	n.half_angle = c.half_angle
	return n


## 이 attached 구성·골반에서 플랫폼 지지가 성립하는가(ClimbSession.on_platform과 같은 규칙).
## feet: 지지 발 자격, key_over: 가정한 접점의 슬롯 키(limb → key).
func platform_for(att: Dictionary, feet: Array, pelvis: Vector2, key_over: Dictionary = {}) -> bool:
	if not (att.has(&"LF") and att.has(&"RF")) or feet.size() < 2:
		return false
	var lk: String = key_over.get(&"LF", keys[&"LF"])
	var rk: String = key_over.get(&"RF", keys[&"RF"])
	for p in route.platforms:
		if p.foot_slot_keys.has(lk) and p.foot_slot_keys.has(rk):
			var a: Vector2 = att[&"LF"]
			var c: Vector2 = att[&"RF"]
			return pelvis.x >= minf(a.x, c.x) - 0.10 and pelvis.x <= maxf(a.x, c.x) + 0.10
	return false
