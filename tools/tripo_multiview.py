# Tripo 여러 장 입력(정면·왼쪽·뒤·오른쪽 그림) → 3D 모델(glb). 2026-11-22, 국제판 API(api.tripo3d.ai v2).
# 키는 저장소에 두지 않는다: 환경 변수 TRIPO_API_KEY에서만 읽는다.
# 사용: python3 tools/tripo_multiview.py 출력폴더 --front f.png [--left l.png] [--back b.png] [--right r.png]
#        [--texture-quality standard|detailed] [--pbr] [--model v3.1-20260211]
# 왼쪽(left) 그림은 캐릭터가 화면 왼쪽을 보는 옆모습(남성 v2와 같음). 비용(2026-11-22 가격표): standard 30, detailed 40크레딧.
import argparse, json, os, sys, time, urllib.request, uuid

API = "https://api.tripo3d.ai/v2/openapi/"


def call(path, key, body=None, files=None):
    headers = {"Authorization": "Bearer " + key, "User-Agent": "curl/8.7.1"}  # 파이썬 기본 값은 Cloudflare가 막음(1010)
    data = None
    if files:
        b = uuid.uuid4().hex
        parts = []
        for name, p in files:
            parts.append(f"--{b}\r\nContent-Disposition: form-data; name=\"{name}\"; filename=\"{os.path.basename(p)}\"\r\nContent-Type: image/png\r\n\r\n".encode() + open(p, "rb").read() + b"\r\n")
        parts.append(f"--{b}--\r\n".encode())
        data = b"".join(parts)
        headers["Content-Type"] = "multipart/form-data; boundary=" + b
    elif body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(API + path, data=data, headers=headers)
    try:
        res = json.loads(urllib.request.urlopen(req, timeout=120).read())
    except urllib.error.HTTPError as e:
        sys.exit("Tripo 오류 %d: %s" % (e.code, e.read().decode(errors="replace")[:500]))
    if res.get("code") != 0:
        sys.exit("Tripo 오류: %s" % json.dumps(res, ensure_ascii=False)[:500])
    return res["data"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    for v in ("front", "left", "back", "right"):
        ap.add_argument("--" + v)
    ap.add_argument("--texture-quality", default="standard")
    ap.add_argument("--pbr", action="store_true")
    ap.add_argument("--model", default="v3.1-20260211")
    a = ap.parse_args()
    key = os.environ.get("TRIPO_API_KEY", "")
    if not key:
        sys.exit("TRIPO_API_KEY가 없어요.")
    os.makedirs(a.out, exist_ok=True)
    files = []
    for v in ("front", "left", "back", "right"):
        p = getattr(a, v)
        if p:
            tok = call("upload", key, files=[("file", p)])["image_token"]
            files.append({"type": "png", "file_token": tok})
        else:
            files.append({})
    body = {"type": "multiview_to_model", "files": files, "model_version": a.model, "texture": True, "pbr": a.pbr, "texture_quality": a.texture_quality}
    tid = call("task", key, body=body)["task_id"]
    print("작업:", tid, flush=True)
    t0 = time.time()
    while True:
        d = call("task/" + tid, key)
        st = d.get("status")
        if st in ("success", "failed", "cancelled", "banned", "expired", "unknown"):
            break
        if time.time() - t0 > 900:
            sys.exit("15분 넘게 끝나지 않음: " + tid)
        time.sleep(8)
    if st != "success":
        sys.exit("실패(%s): %s" % (st, json.dumps(d, ensure_ascii=False)[:500]))
    out = d.get("output", {})
    saved = {}
    for k in ("model", "pbr_model", "base_model", "rendered_image"):
        url = out.get(k)
        if url:
            ext = ".webp" if k == "rendered_image" else ".glb"
            p = os.path.join(a.out, k + ext)
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "curl/8.7.1"}), timeout=300) as r:
                open(p, "wb").write(r.read())
            saved[k] = p
    rec = {"task_id": tid, "type": "multiview_to_model", "model": a.model, "texture": True, "pbr": a.pbr,
           "texture_quality": a.texture_quality, "credits_consumed": d.get("consumed_credit", d.get("credits_consumed")),
           "reference_order": ["front", "left", "back", "right"], "views": [v for v in ("front", "left", "back", "right") if getattr(a, v)],
           "seconds": round(time.time() - t0)}
    json.dump(rec, open(os.path.join(a.out, "task.json"), "w"), ensure_ascii=False, indent=1)
    print("저장:", saved, "\n기록:", rec)


main()
