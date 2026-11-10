"""캐릭터 치수 기준 그림(docs/images/character_size_sheet.svg). 게임 뼈대 규격(docs/34 §3.1)에서 그린다.
python3 art_source/character/size_sheet.py
"""
import math, os
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "images", "character_size_sheet.svg")
S = 300  # px / m
FLOOR = -1.05
def J():
    j = {"pelvis": (0, 0), "spine": (0, 0.22), "chest": (0, 0.44), "neck": (0, 0.63), "head": (0, 0.80), "head_top": (0, 0.94)}
    a = math.radians(25)
    for s, sx in (("L", -1), ("R", 1)):
        sh = (sx * 0.20, 0.55); el = (sh[0] + sx * math.cos(a) * 0.40, sh[1] - math.sin(a) * 0.40)
        wr = (el[0] + sx * math.cos(a) * 0.38, el[1] - math.sin(a) * 0.38)
        ha = (wr[0] + sx * math.cos(a) * 0.09, wr[1] - math.sin(a) * 0.09)
        l = math.radians(4); hip = (sx * 0.14, 0); kn = (hip[0] + sx * math.sin(l) * 0.52, -math.cos(l) * 0.52)
        an = (kn[0] + sx * math.sin(l) * 0.48, kn[1] - math.cos(l) * 0.48)
        j.update({"shoulder_" + s: sh, "elbow_" + s: el, "wrist_" + s: wr, "hand_" + s: ha, "hip_" + s: hip, "knee_" + s: kn, "ankle_" + s: an})
    return j
j = J()
W, H = 1500, 760
ox, oy = 360, 60 + 0.94 * S + 20
def P(p, x0=ox): return (x0 + p[0] * S, oy - p[1] * S)
out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="Apple SD Gothic Neo, Noto Sans KR, sans-serif">',
       '<rect width="100%" height="100%" fill="#faf6ee"/>',
       '<text x="20" y="34" font-size="24" fill="#302820">캐릭터 치수 기준(게임 뼈대 규격 · 단위 m · 골반 관절 = 원점)</text>']
def line(a, b, c="#302820", w=3, dash=""): out.append(f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" stroke="{c}" stroke-width="{w}" {dash}/>')
def text(p, t, size=15, c="#302820", anchor="start"): out.append(f'<text x="{p[0]:.1f}" y="{p[1]:.1f}" font-size="{size}" fill="{c}" text-anchor="{anchor}">{t}</text>')
def circle(p, r, fill="#302820", stroke="none", w=0, op=1): out.append(f'<circle cx="{p[0]:.1f}" cy="{p[1]:.1f}" r="{r:.1f}" fill="{fill}" stroke="{stroke}" stroke-width="{w}" opacity="{op}"/>')
# 앞모습: 높이 눈금
for z in [0.94, 0.80, 0.63, 0.55, 0.44, 0.22, 0.0, -0.52, -1.0, FLOOR]:
    y = oy - z * S
    line((ox - 330, y), (ox + 330, y), "#d8cdb8", 1, 'stroke-dasharray="4 4"')
    text((ox - 335, y + 5), f"{z:+.2f}", 13, "#8a7a60", "end")
text((ox, 60), "앞모습(벽에서 본 반대편 = 카메라 쪽 등과 같은 실루엣)", 16, "#302820", "middle")
# 살 범위(최대 두께 한계)
circle(P((0, 0.84)), 0.19 * S, "#c9b8e8", op=0.35)  # 머리카락 한계
circle(P((0, 0.84)), 0.12 * S, "#e8b48e", op=0.9)
out.append(f'<rect x="{P((-0.24,0.60))[0]:.1f}" y="{P((-0.24,0.60))[1]:.1f}" width="{0.48*S:.1f}" height="{0.62*S:.1f}" rx="30" fill="#f1ebe0" stroke="#bbb" opacity="0.9"/>')
EDGES = [("pelvis", "spine"), ("spine", "chest"), ("chest", "neck"), ("neck", "head"), ("head", "head_top")]
for s in "LR":
    EDGES += [("chest", "shoulder_" + s), ("shoulder_" + s, "elbow_" + s), ("elbow_" + s, "wrist_" + s), ("wrist_" + s, "hand_" + s),
              ("pelvis", "hip_" + s), ("hip_" + s, "knee_" + s), ("knee_" + s, "ankle_" + s)]
for a, b in EDGES:
    line(P(j[a]), P(j[b]), "#2b7a6f", 5)
for k, p in j.items():
    circle(P(p), 6, "#985448")
for s, sx in (("L", -1), ("R", 1)):
    an = j["ankle_" + s]
    out.append(f'<rect x="{P((an[0]-0.05, an[1]+0.02))[0]:.1f}" y="{P((0, an[1]+0.02))[1]:.1f}" width="{0.10*S:.1f}" height="{0.07*S:.1f}" rx="6" fill="#a39c94"/>')
# 치수 글
text(P((0.0, 0.97)), "머리 끝 +0.94", 14, anchor="middle")
text(P((0.23, 0.86)), "머리 반지름 ≤ 0.12 · 머리카락 ≤ 0.19", 13, "#5e4c70")
text(P((0.22, 0.58)), "어깨 관절 X ±0.20, 높이 +0.55", 13)
text(P((0.62, 0.42)), "위팔 0.40", 13); text(P((0.95, 0.27)), "아래팔 0.38", 13); text(P((1.0, 0.13)), "손 0.09(주먹)", 13)
text(P((-1.12, 0.47)), "팔 기준 자세: 25° 아래 A자", 13)
text(P((0.20, -0.25)), "허벅지 0.52", 13); text(P((0.24, -0.75)), "정강이 0.48", 13)
text(P((0.17, 0.03)), "고관절 X ±0.14", 13)
text(P((0.28, -1.00)), "발목 −1.00 (발 접점)", 13); text(P((0.28, FLOOR + 0.0)), "밑창 ≈ −1.05", 13)
text(P((-0.27, 0.15)), "몸통 반폭 ≤ 0.24", 13, "#555", "end")
# 옆모습
sx0 = 1120
text((sx0, 60), "옆모습(왼쪽 = 벽 쪽 −Z · 앞)", 16, "#302820", "middle")
def Q(z, y): return (sx0 - z * S, oy - y * S)   # z: 앞(벽) 양수로 왼쪽
for a, b in [((0, 0), (0, 0.94))]:
    line(Q(*a), Q(*b), "#2b7a6f", 5)
out.append(f'<rect x="{Q(0.13,0.6)[0]:.1f}" y="{Q(0,0.6)[1]:.1f}" width="{0.28*S:.1f}" height="{0.62*S:.1f}" rx="25" fill="#f1ebe0" stroke="#bbb" opacity="0.9"/>')
circle(Q(0, 0.84), 0.12 * S, "#e8b48e")
line(Q(0, -0.0), Q(0, -1.0), "#2b7a6f", 5)
line(Q(0, -1.0), Q(0.15, -1.05), "#2b7a6f", 5)
out.append(f'<rect x="{Q(0.20,-0.98)[0]:.1f}" y="{Q(0,-0.98)[1]:.1f}" width="{0.27*S:.1f}" height="{0.08*S:.1f}" rx="8" fill="#a39c94"/>')
out.append(f'<rect x="{Q(-0.15,0.06)[0]:.1f}" y="{Q(0,0.06)[1]:.1f}" width="{0.06*S:.1f}" height="{0.13*S:.1f}" rx="6" fill="#7a7472"/>')
line(Q(0.35, 1.1), Q(0.35, -1.1), "#985448", 2, 'stroke-dasharray="6 4"')
text(Q(0.36, 1.0), "벽", 14, "#985448", "end")
text(Q(-0.02, 0.33), "몸통 앞 두께 ≤ 0.13(벽 쪽)", 13, "#302820", "start")
text(Q(-0.17, 0.0), "초크백: 등 쪽 허리, 지름 ≤ 0.14·높이 ≤ 0.13", 13, "#302820", "start")
text(Q(0.20, -1.13), "신발: 발목→발끝 앞 0.15, 너비 ≤ 0.10", 13, "#302820", "start")
# 바닥 기준 키
text((20, H - 50), "바닥 기준 키 ≈ 1.99 m (밑창 −1.05 ~ 머리 끝 +0.94). 남성·여성 모두 같은 관절 위치·뼈 길이, 차이는 살(실루엣)로만.", 16)
text((20, H - 24), "Blender: Z 위 · +Y 앞(벽 쪽) · 단위 m · 스케일 1 · 변환 적용 후 glTF(+Y up) 내보내기", 15, "#5e4c70")
out.append("</svg>")
open(OUT, "w").write("\n".join(out))
print(OUT)
