#!/usr/bin/env python3
"""작업 5 새 일반 문제 생성기(docs/superpowers/specs/2026-11-19-5-routes-design.md §5.2).

문제마다 ROUTES의 짧은 표를 game/data/routes/general/<id>.json으로 쓴다. 기존 파일의 score_ref·score_gates는
tools/score_ref.gd가 따로 쓰므로 그대로 둔다(덮어쓰지 않음).
사용: python3 tools/routes/gen_routes.py [route_id ...]
"""
import json
import os
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "game", "data", "routes", "general")
FOOT_TYPES = ("foot_chip", "foot_big")


def hold(hid, t, size, x, y, rot=0, allowed=None, matchable=False):
    return {"hid": hid, "t": t, "size": size, "x": x, "y": y, "rot": rot, "allowed": allowed, "matchable": matchable}


def build(r):
    rid = r["id"]
    holds = []
    slot_of = {}
    for h in r["holds"]:
        foot = h["t"] in FOOT_TYPES
        sid = "foot_1" if foot else "hand_1"
        s = {"slot_id": sid, "pos": [h["x"], h["y"]], "allowed": h["allowed"] or (["LF", "RF"] if foot else ["LH", "RH"]),
             "hold_type": h["t"], "size": h["size"], "rot_deg": h["rot"]}
        if h["matchable"]:
            s["hand_area"] = {"matchable": True}
        holds.append({"hold_id": h["hid"], "slots": [s]})
        slot_of[h["hid"]] = "%s/%s/%s" % (rid, h["hid"], sid)
    gx, gy = r["goal"]
    holds.append({"hold_id": "G01", "slots": [
        {"slot_id": "goal_left", "pos": [round(gx - 0.2, 3), gy], "allowed": ["LH", "RH"], "hold_type": "goal", "size": "M", "rot_deg": 0},
        {"slot_id": "goal_right", "pos": [round(gx + 0.2, 3), gy], "allowed": ["LH", "RH"], "hold_type": "goal", "size": "M", "rot_deg": 0}]})
    slot_of["GL"] = "%s/G01/goal_left" % rid
    slot_of["GR"] = "%s/G01/goal_right" % rid

    def key(v):
        return slot_of[v] if isinstance(v, str) and v in slot_of else v

    moves = []
    for m in r["moves"]:
        moves.append([m[0]] + [key(v) for v in m[1:]])
    st = r["start"]
    d = {
        "route_id": rid, "mode": "general", "grade": r["grade"], "order": r["order"], "name_ko": r["name"],
        "content_version": r.get("version", 1), "validation_status": "Draft", "note": r["note"],
        "bounds": {"x_min": -1.5, "x_max": 1.5, "y_min": 0.0, "y_max": 4.5}, "fail_line_y": -0.5,
        "check_swapped": False, "time_medal_seconds": r.get("time_medal", 120),
        "goal_slots": [slot_of["GL"], slot_of["GR"]],
        "start_pose": {"angle": 0.0, "pelvis": st.get("pelvis", [0.05, 0.75]), "slots": {l: slot_of[st[l]] for l in ("LH", "RH", "LF", "RF")}},
        "platforms": [{"platform_id": "P00", "foot_slot_keys": [slot_of[st["LF"]], slot_of[st["RF"]]], "top_y": 0.1, "x_range": [-0.5, 0.6]}],
        "intended_moves": moves,
        "required_techniques": r.get("required", []),
        "crux_steps": r.get("crux", {}),
        "holds": holds,
    }
    if "gates" in r:
        d["score_gates"] = [{"slot": slot_of[s], "technique": t} for s, t in r["gates"]]
    path = os.path.join(ROOT, rid + ".json")
    if os.path.exists(path):
        old = json.load(open(path))
        for k in ("score_ref",):
            if k in old:
                d[k] = old[k]
        if "score_gates" not in d and "score_gates" in old:
            d["score_gates"] = old["score_gates"]
    with open(path, "w") as f:
        json.dump(d, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")
    print("wrote", rid)


sys.path.insert(0, os.path.dirname(__file__))
from route_specs import ROUTES  # noqa: E402

if __name__ == "__main__":
    want = sys.argv[1:]
    for r in ROUTES:
        if not want or r["id"] in want:
            build(r)
