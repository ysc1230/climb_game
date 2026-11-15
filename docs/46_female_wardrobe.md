# 46. 여성 캐릭터 옷 갈아입기

v0.1 (2026-11-16) 사용자: "github의 temp 폴더에 내가 만든 상의, 하의, 암벽화가 있어. 교체 가능하도록 설정해 줘."

## 자료

main `temp/characters/wardrobe_v1`(Tripo 생성 6종 + 여성 몸에 맞춘 착용 검토본 `fitted_wip/`). 착용 검토본을 썼다(원본과 같은 정규화 좌표, 발바닥 z 0). `art_source/character/female/wardrobe/`로 옮겼다(미리보기 그림 포함).

| ID | 이름(게임) | 슬롯 |
|---|---|---|
| top_mint_tee | 민트 반팔 | 상의 |
| top_coral_long | 코랄 긴팔 | 상의 |
| pants_charcoal | 차콜 긴바지 | 하의 |
| pants_olive_crop | 올리브 7부 | 하의 |
| shoes_gray_pair | 회색 암벽화 | 암벽화 |
| shoes_teal_pair | 청록 암벽화 | 암벽화 |

## 만드는 법(`TRIPO_CHAR=female blender -b --python art_source/character/build_tripo_rig.py`)

1. 옷마다 원본 몸과 **같은 변환**(원본 z 최솟값 기준 놓기, Z +90°, ×1.8156)과 같은 다리·팔 맞추기를 한다. 3500 삼각형으로 줄이고, 법선 방향으로 1.2cm(암벽화 1.0cm) 띄운다.
2. 가중치는 원본 몸과 같은 위치 규칙(`weights_for`)이라 같은 뼈대(ClimberCommonRig)로 함께 움직인다.
3. 암벽화는 한 켤레가 한 메시라 두 발 사이를 잇는 면(가운데 |x| < 0.035)을 지운다(회색 암벽화에 막대가 생겼음).
4. **몸에 붙은 옷 나누기**: 같은 원본의 파츠 분리본(`climber_female_parts.glb`, main temp female_bob_v1의 parts_wip)을 같은 변환으로 놓고, 몸의 면마다 가장 가까운 파츠로 부위를 정해 떼어 낸다 → `P_female_top`, `P_female_pants_up`, `P_female_pants_low`(올리브 7부 밑단 + 3cm 아래), `P_female_shoes`. 나머지(피부·머리·벨트·초크백)는 `P_body_female`.
5. 한 glb(`game/art/characters/climber_female.glb`)에 몸·기본 옷 네 조각·새 옷 여섯 벌이 모두 들어 있고, 고른 것만 보인다.

## 고르기(`data/characters.json`, `CharacterAssembler`)

- 슬롯: 상의·하의·암벽화. 파츠는 `meshes`(보일 메시 목록)와 `bodies`(그 몸에서만).
- 여성: 각 슬롯 기본 + 2종. 기본은 몸에서 떼어 낸 기본 옷 조각이라, 새 옷을 입으면 그 부위의 기본 옷은 숨는다(비침 방지).
- 올리브 7부는 기본 바지 아랫단(`P_female_pants_low`)을 같이 보여 7부 아래가 레깅스처럼 보인다(아래에 맨다리가 없기 때문).
- 남성·더미: 기본뿐(고를 것 없음). 다른 몸의 옷을 고른 값은 기본으로 바뀐다.
- 홈 → 캐릭터에서 ◀ ▶로 고르고 저장.

## 확인

- 맥 렌더(G_V0_02, 오르는 자세): 코랄 긴팔 + 차콜 긴바지 + 청록 암벽화 / 민트 반팔 + 올리브 7부 + 회색 암벽화 / 기본. 기본 옷 비침 없음, 나눈 경계에 틈 없음.
- 테스트: 슬롯·몸별 파츠, 차례 바꾸기, 다른 몸의 옷은 기본으로, 고른 메시만 보이고 덮인 기본 옷은 숨음.

## 남은 것(검토본 품질)

- 올리브 7부는 갈색에 가깝고 천 무늬가 지저분해 보인다. 코랄 긴팔 등판에 밝은 얼룩이 있다(검토본 텍스처).
- 큰 자세에서 허리·무릎 변형, 암벽화 발목 구멍 모양은 README의 수정 대상 그대로다.
- 옷 크기는 1차 근사(비균일 배율)라 체형에 맞춘 재단·관통 검사는 아니다. 기기에서 확인 필요.
