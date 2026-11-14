# 여성 클라이머(단발)

출처: main `temp/characters/female_bob_v1/climber_female_base.glb`(Tripo 기본 생성본, 키 1.0, 앞 +X). 2026-11-15 이 폴더로 옮겨 게임에 넣음. 이전 여성(올림머리, 2026-11-12)은 게임에서 쓰지 않아 지움.

- 게임용: `TRIPO_CHAR=female blender -b --python art_source/character/build_tripo_rig.py` → `game/art/characters/climber_female.glb`(삼각형 12000, 뼈 21)
- 기준점(정규화 높이에서 잼): 어깨 0.776, 발목 0.06, 무릎 0.27, 손끝 0.398, 가랑이 0.47, 손목 0.29, 손가락 뿌리 0.35. 손가락 0.058(남성과 같음).
- 초크백: 오른쪽 허리 뒤(몸과 붙은 덩어리, `chalk` 판별식).
- Mixamo 리깅본·파츠 분리본(temp의 rig_wip·parts_wip)은 쓰지 않는다: 게임 뼈대(docs/39 더미 기준)로 다시 리깅한다.
- 참고 그림: `references/`, 파츠 검토 그림: `preview.png`.
- 고를 곳: `game/data/characters.json` 몸 목록(남성 → 여성 → 더미).
