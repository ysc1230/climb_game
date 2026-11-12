# Tripo 남성 클라이머 v2

기존 남성 참고 그림(`../tripo/references`)은 청바지 엉덩이·허벅지·무릎 뒤에 진한 주름·그림자가 그려져 있어, Tripo가 그것을 텍스처에 그대로 옮겼다(엉덩이 얼룩). `clean_refs.py`로 바지는 단색 + 외곽선·솔기만, 셔츠는 흰색 단색으로 정리한 `references/*.png`로 다시 생성했다(2026-11-12, Tripo v3.1, 30크레딧, `task.json`).

- 원본: `climber_male_v2_base.glb`
- 게임용: `blender -b --python art_source/character/tripo/build_tripo_rig.py` → `game/art/characters/climber_tripo.glb`(2026-11-13부터 이 모델)
- 맞춤(docs/37 §7): ×1.9877(키 1.99m), 손끝 ×0.981, 화면 다리 관절은 판정 고관절 위 0.10m, 가랑이 0.07m 올림.

이전 남성(v1) 원본은 `../tripo/climber_tripo_base.glb`.
