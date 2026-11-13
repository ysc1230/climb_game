# 매끈한 남성 (게임 기본 캐릭터, 2026-11-13)

- 원본: `climber_smooth_base.glb` = main 15f44d9의 `game/art/characters/climber_smooth_base.glb`(Tripo P1, task 1f0174d2, 사용자 제작). 제작 기록은 main의 `art_source/character/rebuild/approved_small_head/README.md`.
- 게임용: `TRIPO_CHAR=smooth blender -b --python art_source/character/build_tripo_rig.py` → `game/art/characters/climber_smooth.glb`
- 맞춤(더미 몸, docs/39): ×1.831(키 1.83m, 머리카락 포함). 무릎 −0.339 → −0.41. 팔은 손목까지만 늘리고(원본 팔이 짧다) 손바닥은 원래 크기, 손가락은 늘린 길이의 절반(0.058, 사용자 요청). 초크백은 앞뒤 두 겹으로 생성돼 뒤쪽 하나만 남겼다.
- Tripo 자동 리깅본(`climber_smooth_rig_wip.glb`, Mixamo 65뼈)은 게임 뼈대 규격이 아니라 쓰지 않는다.
- 남은 것: 하이스텝·옆 뻗기에서 엉덩이~허벅지 연결부(허리띠 아래 끌림), 얼굴·파츠.
