"""작업 5 새 일반 문제 배치(gen_routes.py가 읽음). 좌표는 m(x 오른쪽, y 위). 시작 발판 F01·F02는 바닥 받침(y 0.1).
moves의 홀드 이름은 슬롯 키로 바뀐다(GL·GR = 정상 왼칸·오른칸). 문제마다 설계 메모는 note.
"""


def H(hid, t, size, x, y, rot=0, allowed=None, matchable=False):
    return {"hid": hid, "t": t, "size": size, "x": x, "y": y, "rot": rot, "allowed": allowed, "matchable": matchable}


ROUTES = [
    # ---------- V0 ----------
    {
        "id": "G_V0_03", "grade": "V0", "order": 2, "name": "넓은 계단",
        "note": "작업 5 V0: 손발 하나씩. 저그 L·큰 발판이 가깝게 계단처럼 이어진다. 쉬는 자리는 어디서나. 관문 없음.",
        "holds": [
            H("H01", "jug", "L", -0.36, 1.5), H("H02", "jug", "L", 0.36, 1.5),
            H("H03", "jug", "L", -0.4, 1.95), H("H04", "jug", "L", 0.3, 1.95),
            H("H05", "jug", "L", -0.38, 2.33), H("H06", "jug", "L", 0.45, 2.33),
            H("F01", "foot_chip", "M", -0.15, 0.1), H("F02", "foot_chip", "M", 0.18, 0.1),
            H("F03", "foot_big", "M", -0.25, 0.5), H("F04", "foot_big", "M", 0.3, 0.6),
            H("F05", "foot_big", "M", -0.17, 0.95), H("F06", "foot_big", "M", 0.22, 0.98),
        ],
        "goal": (0.05, 2.75),
        "start": {"LH": "H01", "RH": "H02", "LF": "F01", "RF": "F02"},
        "moves": [["LF", "F03"], ["RF", "F04"], ["LH", "H03"], ["RH", "H04"], ["LF", "F05"], ["RF", "F06"],
                  ["LH", "H05"], ["RH", "H06"], ["LH", "GL"], ["RH", "GR"]],
    },
    # ---------- V1 ----------
    {
        "id": "G_V1_02", "grade": "V1", "order": 2, "name": "발 먼저",
        "note": "작업 5 V1: 손홀드 사이가 멀어 발을 먼저 올려야 다음 손이 닿는다. 저그 M·작은 발판. 관문 없음.",
        "holds": [
            H("H01", "jug", "M", -0.3, 1.5), H("H02", "jug", "M", 0.28, 1.5),
            H("H03", "jug", "M", -0.25, 2.05), H("H04", "jug", "M", 0.35, 2.3),
            H("H05", "jug", "M", -0.3, 2.6),
            H("F01", "foot_chip", "M", -0.15, 0.1), H("F02", "foot_chip", "M", 0.18, 0.1),
            H("F03", "foot_chip", "M", -0.2, 0.5), H("F04", "foot_chip", "M", 0.25, 0.6),
            H("F05", "foot_chip", "M", -0.15, 1.0), H("F06", "foot_chip", "M", 0.3, 1.15),
            H("F07", "foot_chip", "M", 0.0, 1.25),
        ],
        "goal": (0.15, 3.0),
        "start": {"LH": "H01", "RH": "H02", "LF": "F01", "RF": "F02"},
        "moves": [["LF", "F03"], ["RF", "F04"], ["LH", "H03"], ["LF", "F05"], ["RH", "H04"], ["RF", "F06"],
                  ["LH", "H05"], ["LF", "F07"], ["RH", "GR"], ["LH", "GL"]],
    },
    # ---------- V2 ----------
    {
        "id": "G_V2_01", "grade": "V2", "order": 1, "name": "옆길",
        "note": "작업 5 V2: 오른쪽으로 비껴 오르는 길. 몸통을 옆으로 옮겨야 다음 손이 편하다. 가운데 큰 저그(H04)가 쉬는 자리. 관문 없음.",
        "holds": [
            H("H01", "jug", "M", -0.3, 1.5), H("H02", "jug", "M", 0.25, 1.5),
            H("H03", "jug", "S", 0.55, 1.95), H("H04", "jug", "L", 0.2, 2.25),
            H("H05", "jug", "S", 0.75, 2.45), H("H06", "jug", "M", 0.1, 2.65),
            H("F01", "foot_chip", "M", -0.15, 0.1), H("F02", "foot_chip", "M", 0.18, 0.1),
            H("F03", "foot_big", "M", 0.1, 0.55), H("F04", "foot_chip", "M", 0.6, 0.7),
            H("F05", "foot_big", "M", 0.25, 1.1), H("F06", "foot_chip", "M", 0.7, 1.3),
        ],
        "goal": (0.6, 3.0),
        "start": {"LH": "H01", "RH": "H02", "LF": "F01", "RF": "F02"},
        "moves": [["LF", "F03"], ["RF", "F04"], ["RH", "H03"], ["LH", "H04"], ["LF", "F05"], ["RF", "F06"],
                  ["RH", "H05"], ["LH", "H06"], ["LF", "H02"], ["RH", "GR"], ["LH", "GL"]],
    },
    {
        "id": "G_V2_02", "grade": "V2", "order": 2, "name": "쉼터",
        "note": "작업 5 V2: 작은 저그가 이어지다 가운데 큰 저그 둘(H04·H05)을 두 손으로 잡고 두 발을 디뎌 쉬어야 끝까지 간다. 관문 없음.",
        "holds": [
            H("H01", "jug", "S", -0.28, 1.5), H("H02", "jug", "S", 0.28, 1.5),
            H("H03", "jug", "S", -0.35, 1.95), H("H04", "jug", "L", 0.25, 2.15),
            H("H05", "jug", "L", -0.3, 2.45), H("H06", "jug", "S", 0.45, 2.6),
            H("F01", "foot_chip", "M", -0.15, 0.1), H("F02", "foot_chip", "M", 0.18, 0.1),
            H("F03", "foot_chip", "S", -0.25, 0.55), H("F04", "foot_chip", "S", 0.3, 0.6),
            H("F05", "foot_big", "M", -0.1, 1.0), H("F06", "foot_big", "M", 0.4, 1.05),
        ],
        "goal": (0.1, 2.95),
        "start": {"LH": "H01", "RH": "H02", "LF": "F01", "RF": "F02"},
        "moves": [["LF", "F03"], ["RF", "F04"], ["LH", "H03"], ["RH", "H04"], ["LF", "F05"], ["RF", "F06"], ["LH", "H05"],
                  ["REST", "rest", 2.0], ["RH", "H06"], ["LF", "H01"], ["RF", "H02"], ["LH", "GL"], ["RH", "GR"]],
    },
]


# ---------- 기존 문제에서 뼈대를 가져와 바꾸기 ----------
import json as _json
import os as _os

_GEN = _os.path.join(_os.path.dirname(__file__), "..", "..", "game", "data", "routes", "general")
_SWAP = {"LH": "RH", "RH": "LH", "LF": "RF", "RF": "LF"}


def derive(src, new_id, grade, order, name, note, mirror=False, shift=0.05, retype=None, move=None, add=None, drop=(),
           moves=None, required=None, crux=None, gates=None, goal=None):
    """src 문제의 홀드·순서를 가져온다. mirror면 좌우를 뒤집고(x → shift − x, 손발·정상 칸·방향을 바꿈).
    retype: hid → (종류, 크기[, rot]), move: hid → (x, y), add: 더할 H(...) 목록, drop: 뺄 hid, moves: 순서를 통째로 바꿈."""
    d = _json.load(open(_os.path.join(_GEN, src + ".json")))
    sx = (lambda x: round(shift - x, 3)) if mirror else (lambda x: x)
    holds = []
    goal_y = None
    gx = []
    for h in d["holds"]:
        if h["hold_id"] == "G01":
            for s in h["slots"]:
                goal_y = s["pos"][1]
                gx.append(sx(s["pos"][0]))
            continue
        if h["hold_id"] in drop:
            continue
        s = h["slots"][0]
        t, size, rot = s["hold_type"], s["size"], s.get("rot_deg", 0)
        if mirror:
            rot = (360 - rot) % 360
        x, y = sx(s["pos"][0]), s["pos"][1]
        if retype and h["hold_id"] in retype:
            r = retype[h["hold_id"]]
            t, size = r[0], r[1]
            rot = r[2] if len(r) > 2 else rot
        if move and h["hold_id"] in move:
            x, y = move[h["hold_id"]]
        holds.append(H(h["hold_id"], t, size, x, y, rot, None, s.get("hand_area", {}).get("matchable", False)))
    holds += add or []

    def limb(l):
        return _SWAP[l] if mirror else l

    def name_of(key):
        hid, sid = key.split("/")[1], key.split("/")[2]
        if hid == "G01":
            left = sid == "goal_left"
            return "GL" if left != mirror else "GR"
        return hid

    st = d["start_pose"]
    start = {limb(l): name_of(k) for l, k in st["slots"].items()}
    start["pelvis"] = [sx(st["pelvis"][0]), st["pelvis"][1]]
    if moves is None:
        moves = []
        for m in d["intended_moves"]:
            if m[0] in ("BODY", "REST"):
                moves.append(m)
            else:
                moves.append([limb(m[0])] + [name_of(v) if isinstance(v, str) and "/" in v else v for v in m[1:]])
    return {"id": new_id, "grade": grade, "order": order, "name": name, "note": note, "holds": holds,
            "goal": goal or (round((gx[0] + gx[1]) / 2.0, 3), goal_y), "start": start, "moves": moves,
            "required": required if required is not None else d.get("required_techniques", []),
            "crux": crux if crux is not None else d.get("crux_steps", {}),
            **({"gates": gates} if gates is not None else {})}


# ---------- V4 ----------
ROUTES.append(derive(
    "G_V3_04", "G_V4_01", "V4", 2, "외발 계단",
    "작업 5 V4: 높은 디딤(V3)을 좌우로 뒤집고 손홀드를 크림프 L로 바꿨다. 오른발 하이스텝(#3)이 관문. 발판이 적어 한 발 구간이 길다. 쉬는 자리 없음.",
    mirror=True, retype={h: ("crimp", "L") for h in ("H03", "H05")},
    gates=[("F05", "T_HIGH_STEP")]))


# ---------- V5 ----------
ROUTES.append(derive(
    "G_V3_02", "G_V5_01", "V5", 1, "작은 쉼표",
    "작업 5 V5: 모아서 뻗기(V3)를 뒤집고 작은 홀드(크림프·포켓)로 바꿨다. 가운데 파란 저그(H07)가 유일한 쉬는 자리이자 매치 관문(#10). 작은 홀드 구간은 짧다.",
    mirror=True, retype={"H03": ("crimp", "L"), "H04": ("pocket", "L"), "H05": ("crimp", "L"), "H06": ("pocket", "L"), "H08": ("crimp", "L")},
    gates=[("H07", "T_MATCH")]))
ROUTES.append(derive(
    "G_V3_03", "G_V5_02", "V5", 2, "거꾸로 사선",
    "작업 5 V5: 가는 사선을 뒤집었다. 하이스텝(#8)이 관문, 위쪽 파란 저그(H08)가 쉬는 자리.",
    mirror=True, retype={"H05": ("jug", "S"), "H07": ("jug", "S")}, gates=[("F07", "T_HIGH_STEP")]))


# ---------- V6 ----------
ROUTES.append(derive(
    "G_V3_03", "G_V6_01", "V6", 1, "두 고비",
    "작업 5 V6: 가는 사선의 뼈대에 관문 둘을 잇는다. 왼발 하이스텝(#8)으로 올라선 뒤 파란 저그(H08)에서 매치(#12)해야 오른손이 H09로 간다. 아래 핀치를 크림프로, 발판을 작게 바꿨다.",
    retype={"H01": ("crimp", "M"), "H02": ("crimp", "L"), "H05": ("crimp", "L"), "H09": ("crimp", "M"),
            **{f: ("foot_chip", "S") for f in ("F03", "F04", "F05", "F06", "F08", "F09", "F10")}},
    move={"H09": (0.25, 3.3)},
    required=["T_HIGH_STEP", "T_MATCH"], crux={"T_HIGH_STEP": 8, "T_MATCH": 12},
    gates=[("F07", "T_HIGH_STEP"), ("H08", "T_MATCH")]))
ROUTES.append(derive(
    "G_V3_02", "G_V6_02", "V6", 2, "높이 모아",
    "작업 5 V6: 모아서 뻗기의 뼈대에서 중간 발판(F05)을 높여 왼발 하이스텝(#4)을 만들고, 위쪽 파란 저그(H07) 매치(#10)를 그대로 둔다. 손홀드는 크림프·포켓.",
    move={"F05": (-0.12, 1.2), "F07": (0.1, 1.52)},
    retype={"H05": ("pocket", "L"), "H06": ("crimp", "L"), "H08": ("crimp", "M")},
    required=["T_HIGH_STEP", "T_MATCH"], crux={"T_HIGH_STEP": 4, "T_MATCH": 10},
    gates=[("F05", "T_HIGH_STEP"), ("H07", "T_MATCH")]))


# ---------- V7 ----------
# 방향 홀드만으로는 관문이 되지 않았다(다른 손발이 받치면 위로 당겨도 버팀, R7 격자 304/305). 그래서 V7도 검증된 관문 둘
# (하이스텝·매치)을 두고, 옆·아래를 보는 홀드는 몸 위치를 맞춰야 덜 지치는 어려움 재료로 쓴다.
ROUTES.append(derive(
    "G_V3_03", "G_V7_01", "V7", 1, "비틀린 사선",
    "작업 5 V7: 가는 사선을 뒤집고 손홀드를 작은 크림프로, 중간 두 홀드를 옆을 보게(사이드풀) 돌렸다. 오른발 하이스텝(#8) → 파란 저그 매치(#12)가 관문. 쉬는 자리 없음.",
    mirror=True,
    retype={"H01": ("crimp", "M"), "H02": ("crimp", "M"), "H03": ("crimp", "M"), "H04": ("crimp", "L", 90), "H05": ("crimp", "L"),
            "H06": ("crimp", "L", 270), "H07": ("crimp", "M"), "H09": ("crimp", "M")},
    move={"H08": (0.4, 3.11)},
    required=["T_HIGH_STEP", "T_MATCH"], crux={"T_HIGH_STEP": 8, "T_MATCH": 12},
    gates=[("F07", "T_HIGH_STEP"), ("H08", "T_MATCH")]))
ROUTES.append(derive(
    "G_V6_02", "G_V7_02", "V7", 2, "아래로 잡기",
    "작업 5 V7: 높이 모아(V6)를 뒤집고 가운데 홀드(H05)를 아래를 보는 크림프(언더클링)로 돌렸다. 발을 높이 둬야 버틴다. 오른발 하이스텝(#4) → 파란 저그 매치(#10)가 관문.",
    mirror=True, retype={"H05": ("crimp", "L", 180), "H06": ("crimp", "S"), "H08": ("crimp", "S")},
    gates=[("F05", "T_HIGH_STEP"), ("H07", "T_MATCH")]))
