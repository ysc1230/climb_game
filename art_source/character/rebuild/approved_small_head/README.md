# 승인된 작은 머리 시안의 Tripo 제작 결과

2026-11-13. 사용자 승인 시안은 approved_concept.png. 이전의 5.5/6/7/8등신 수치보다 최종 작은 머리 시안의 시각적 비율을 우선한다. 정면·후면은 내장 image_gen으로 개별화했고 front.png / back.png를 실제 입력했다.

## 산출물

- game/art/characters/climber_smooth_base.glb: Tripo P1 기본 생성본.
- game/art/characters/climber_smooth_rig_wip.glb: Mixamo 규격 자동 리깅본. **WIP, 게임 최종 채택본 아님.**
- tripo-out/: 각 단계 원본 및 미리보기.
- review/inspection.json: Khronos GLB 형식 검사와 메시/리그 정보.
- review/review.png: 앞·뒤·측면, 높은 다리/옆 벌림의 단순 회전 점검. 실제 게임 IK 또는 기존 참고와 일치된 포즈 검수는 아님.

## 실행 및 비용

1. multiview_to_model — P1-20260311, face_limit=20000, texture=true, pbr=false. 작업 1f0174d2-45be-44d3-8d1c-94f080fc5cf5: 50크레딧.
2. animate_prerigcheck — 작업 d6c71084-4cd6-4953-a25f-91a26cfdef44: 0크레딧, biped 권장.
3. animate_rig — v2.5-20260210, spec=mixamo, out_format=glb. 작업 87a328a7-c074-4a99-ae6a-f2ec85e16ad4: 25크레딧.

총 75크레딧. 시작 잔액 820, 완료 후 745. 명령의 쉼표 인자 오류는 dry-run 단계에서 발생했고 따옴표로 수정했다. 유료 생성 실패나 중복 제출이 아니다.

## 검수 결과

- 리깅본 2,347,724 bytes, 18,545 삼각형, 재질 1개, 스킨 1개, 스킨 조인트 65개, 애니메이션 클립 0개.
- GLB validator 오류 0, 경고 1: NODE_SKINNED_MESH_NON_ROOT. 엔진 임포트 및 부모 변환 동작은 별도 확인 대상.
- 앞뒤 외형과 무주름 바지 인상 확인. 측면에서 초크백이 두 겹으로 생성된 형상이 보이므로 1개로 정리 필요.
- 단순 다리 회전에서 허리선/벨트가 다리에 끌리는 변형을 확인. 골반·벨트 가중치 정리와 필요 시 자세 보정이 남아 있음.
- 65개 스킨 조인트는 기존 40개 이하 예산보다 많다. 손가락·끝 조인트 필요 여부를 검토하고 실제 가중치와 런타임을 확인한 뒤 줄일 것.
- 사용자 참고의 높은 발 올리기와 옆 벌림에 대한 최종 시각 합격, Godot 연결, 실제 기기 성능은 미검증.

기존 game/art/characters/climber.glb를 교체하거나 실행 장면을 변경하지 않았다. 현재 파일은 기본 제작과 리깅이 성공한 검토용 결과다. 초크백 형상과 골반 웨이트 수정을 마치기 전 완성 게임 캐릭터로 보고하지 않는다.
