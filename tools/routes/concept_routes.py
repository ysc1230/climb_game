#!/usr/bin/env python3
"""컨셉 문제 쓰기(concept_specs.CONCEPTS → game/data/routes/general/<id>.json). 사용: python3 tools/routes/concept_routes.py [route_id ...]
옛 문제를 다시 쓰는 gen_routes.py(인자 없으면 모두)와 따로 둔다."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from gen_routes import build  # noqa: E402
from concept_specs import CONCEPTS  # noqa: E402

if __name__ == "__main__":
    want = sys.argv[1:]
    for r in CONCEPTS:
        if not want or r["id"] in want:
            build(r)
