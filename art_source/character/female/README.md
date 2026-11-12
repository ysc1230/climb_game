# Tripo 여성 클라이머

사용자가 그린 T자 그림 4장(`references/front·left·back·right.png`)으로 Tripo v3.1 멀티뷰 생성(2026-11-12, 30크레딧, `task.json`).

- 원본: `climber_female_base.glb`(키 1.0, 올림머리 포함, 앞 +X)
- 게임용: `TRIPO_CHAR=female blender -b --python art_source/character/build_tripo_rig.py` → `game/art/characters/climber_tripo_female.glb`
- 맞춤(docs/37 §7): 어깨~발목을 판정 몸(1.455m)에 맞춰 ×2.0845(키 약 2.08m). 팔은 손끝이 0.80m에 오게 길이 방향으로 ×0.866. 화면 다리 관절은 판정 고관절 위 0.11m, 무릎·발목은 모델 실측.
- 초크백은 왼쪽 허리(그림대로).

미리보기: `preview.png`(Tripo). 게임 화면은 docs/37 §7.
