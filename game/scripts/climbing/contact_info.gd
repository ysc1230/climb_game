class_name ContactInfo
extends RefCounted
## 잡은(딛은) 접점의 정보 (docs/27 §8). 순수 데이터.

var key: String = ""
var point: Vector2 = Vector2.ZERO
var quality: float = 1.0
var mode: StringName = &"pull"   # 손: pull/sidepull/gaston/undercling, 발: foot
var edge: StringName = &""       # 발: inside/outside/toe/drop_knee, 손: 빈 값
var axis: Vector2 = Vector2(0, 1)  # 손: 그립 방식의 힘 축(grip_modes)
var half_angle: float = 0.0        # 손: 방식의 반각, 0이면 기본(SupportSolver)
var half_width: float = 0.0        # 손: 잡은 홀드의 hand_area.half_width(피로 크기 배율, docs/41 §7). 0이면 배율 없음
## 홀드 종류 효과(작업 4 §4.1). 옛 형식 슬롯은 기본값(효과 없음).
var hold_type: StringName = &""
var fatigue_mult: float = 1.0      # 손: 종류 피로 배율(저그 0.7, 크림프 1.3 …)
var foot_share: float = 1.0        # 발: 발 몫 배율(작은 발판 0.85)
var window: Array = []             # 손: 슬로퍼 몸 창 [안 m, 밖 m, 밖 품질 배율]. 비면 없음
var hold_x: float = 0.0            # 몸 창 기준(홀드 중심 x)


static func make(p_key: String, p_point: Vector2, p_quality: float, p_mode: StringName, p_edge: StringName) -> ContactInfo:
	var c := ContactInfo.new()
	c.key = p_key
	c.point = p_point
	c.quality = p_quality
	c.mode = p_mode
	c.edge = p_edge
	return c


## 슬롯의 종류 효과를 옮겨 적는다(RouteDef 슬롯 사전).
func apply_slot(slot: Dictionary) -> ContactInfo:
	hold_type = slot.get("hold_type", &"")
	fatigue_mult = float(slot.get("fatigue_mult", 1.0))
	foot_share = float(slot.get("foot_share", 1.0))
	window = slot.get("window", [])
	hold_x = (slot.pos as Vector2).x
	return self


func copy_hold_from(c: ContactInfo) -> void:
	hold_type = c.hold_type
	fatigue_mult = c.fatigue_mult
	foot_share = c.foot_share
	window = c.window
	hold_x = c.hold_x
