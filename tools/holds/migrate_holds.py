# 기존 문제 JSON에 홀드 종류·크기·방향을 채운다(작업 4 §4.1 "기존 문제 옮기기"). 한 번만 실행하는 도구.
# 실행: python3 tools/holds/migrate_holds.py [파일...]  (없으면 game/data/routes/general·course 전부)
# 손: 합손이거나 반폭 ≥ 0.08 → jug, < 0.05 → crimp, 사이 → jug S. 발 전용: foot_chip. 탑: goal.
# 크기는 그 종류의 S/M/L 반폭 중 가장 가까운 것(같으면 큰 쪽). rot는 grip_modes[0].axis에서(위 0, 시계 방향 +, 5° 단위).
# 옮긴 필드(hand_area.dir·half_width, grip_modes, foot_area)는 지우고 matchable만 남긴다. content_version + 1.
import glob, json, math, os, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "game")
TYPES = json.load(open(os.path.join(ROOT, "data", "hold_types.json")))["types"]
SIZES = ["S", "M", "L"]


def nearest(widths, hw):
    best = 0
    for i, w in enumerate(widths):
        if abs(w - hw) <= abs(widths[best] - hw) + 1e-9:
            best = i
    return SIZES[best]


def rot_of(slot):
    gm = slot.get("grip_modes")
    if not gm:
        return 0
    x, y = gm[0].get("axis", [0, 1])
    deg = math.degrees(math.atan2(x, y)) % 360
    return int(round(deg / 5.0) * 5) % 360


def migrate(path):
    d = json.load(open(path, encoding="utf-8"))
    goals = set(d.get("goal_slots", []))
    for h in d["holds"]:
        for s in h["slots"]:
            if "hold_type" in s:
                continue
            key = "%s/%s/%s" % (d["route_id"], h["hold_id"], s["slot_id"])
            hand = any(l in ("LH", "RH") for l in s["allowed"])
            ha = s.get("hand_area", {})
            if key in goals:
                t, size = "goal", "M"
            elif hand:
                hw = float(ha.get("half_width", 0.08))
                if ha.get("matchable") or hw >= 0.08 - 1e-9:
                    t, size = "jug", nearest(TYPES["jug"]["half_width"], hw)
                elif hw < 0.05 - 1e-9:
                    t, size = "crimp", nearest(TYPES["crimp"]["half_width"], hw)
                else:
                    t, size = "jug", "S"
            else:
                hw = float(s.get("foot_area", {}).get("half_width", 0.06))
                t, size = "foot_chip", nearest(TYPES["foot_chip"]["half_width"], hw)
            s["hold_type"], s["size"], s["rot_deg"] = t, size, rot_of(s)
            s.pop("grip_modes", None)
            s.pop("foot_area", None)
            if ha.get("matchable"):
                s["hand_area"] = {"matchable": True}
            else:
                s.pop("hand_area", None)
    d["content_version"] = float(d.get("content_version", 0)) + 1
    with open(path, "w", encoding="utf-8") as f:
        f.write(json.dumps(d, indent=1, ensure_ascii=False, sort_keys=True) + "\n")
    print("migrated", os.path.relpath(path, ROOT))


files = sys.argv[1:] or sorted(glob.glob(os.path.join(ROOT, "data", "routes", "general", "*.json")) + glob.glob(os.path.join(ROOT, "data", "routes", "course", "*.json")))
for p in files:
    migrate(p)
