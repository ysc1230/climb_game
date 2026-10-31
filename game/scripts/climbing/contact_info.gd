class_name ContactInfo
extends RefCounted
## 잡은(딛은) 접점의 정보 (docs/27 §8). 순수 데이터.

var key: String = ""
var point: Vector2 = Vector2.ZERO
var quality: float = 1.0
var mode: StringName = &"pull"   # 손: pull/sidepull/gaston/undercling, 발: foot
var edge: StringName = &""       # 발: inside/outside/toe/drop_knee, 손: 빈 값


static func make(p_key: String, p_point: Vector2, p_quality: float, p_mode: StringName, p_edge: StringName) -> ContactInfo:
	var c := ContactInfo.new()
	c.key = p_key
	c.point = p_point
	c.quality = p_quality
	c.mode = p_mode
	c.edge = p_edge
	return c
