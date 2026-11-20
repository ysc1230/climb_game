# 점수 기준값을 문제 JSON에 쓴다(작업 3). 원래 키 순서·숫자 표기·한 칸 들여쓰기를 지킨다.
# 실행: godot --headless --path game --script res://tools/score_ref.gd -- --write | python3 tools/score_ref_write.py
import json, os, sys
from collections import OrderedDict

ROOT = os.path.join(os.path.dirname(__file__), "..", "game")
for line in sys.stdin:
    if not line.startswith("SCORE_JSON "):
        continue
    _, res, payload = line.rstrip("\n").split(" ", 2)
    path = os.path.join(ROOT, res.replace("res://", ""))
    with open(path, encoding="utf-8") as f:
        data = json.load(f, object_pairs_hook=OrderedDict)
    new = json.loads(payload)
    g = new["score_ref"]["grabs"]
    new["score_ref"]["grabs"] = int(g)
    data["score_ref"] = new["score_ref"]
    data["score_gates"] = new["score_gates"]
    with open(path, "w", encoding="utf-8") as f:
        f.write(json.dumps(data, indent=1, ensure_ascii=False) + "\n")
    print("wrote", res)
