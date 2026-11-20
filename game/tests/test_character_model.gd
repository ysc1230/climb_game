extends RefCounted
## 표정 고르기 규칙(표정 메시 FX_face_*가 있는 모델에서 쓴다. 2026-11-13 CH02 모델은 지움, 지금 Tripo 모델은 표정 메시 없음).

var runner

const PLAY_3D := preload("res://scenes/play_3d.gd")


func test_expression_rules() -> void:
	runner.check(PLAY_3D.expression_for(false, false, 100.0, false) == "calm", "평소 평온")
	runner.check(PLAY_3D.expression_for(false, false, 40.0, false) == "effort", "팔 힘 45 아래 힘씀")
	runner.check(PLAY_3D.expression_for(false, false, 90.0, true) == "effort", "자세 무너짐 힘씀")
	runner.check(PLAY_3D.expression_for(false, true, 20.0, true) == "happy", "정상 잡으면 기쁨")
	runner.check(PLAY_3D.expression_for(true, true, 20.0, false) == "scared", "떨어지면 놀람")


## 2026-11-20 사용자: 떨어진 뒤 몸은 벽을 보는데 머리만 뒤로 돌아 무서움 → 떨어질 때·착지 장면에서는 고개를 돌려 돌아보지 않는다.
func test_no_look_back_when_falling() -> void:
	runner.check(not PLAY_3D.looks_back(false, true), "떨어질 때 돌아보지 않음")
	runner.check(not PLAY_3D.looks_back(true, true), "떨어지는 중이면 정상 표정이어도 돌아보지 않음")
	runner.check(PLAY_3D.looks_back(true, false), "정상 잡으면 돌아봄")
	runner.check(not PLAY_3D.looks_back(false, false), "평소엔 돌아보지 않음")
