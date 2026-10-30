class_name BodyState
extends RefCounted
## docs/09 BodyState. 골반 위치·벽면 회전·속도.

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var angle := 0.0
var ang_vel := 0.0


func _init(p_pos: Vector2 = Vector2.ZERO, p_angle: float = 0.0) -> void:
	pos = p_pos
	angle = p_angle
