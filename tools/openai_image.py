# OpenAI 이미지 생성(gpt-image-2.5-sunburst, gpt-image-1은 2026-10-23 종료)으로 캐릭터 설정 그림 등을 만든다(2026-11-22, Tripo에 넣을 정면·옆·뒤 그림용).
# 키는 저장소에 두지 않는다: 환경 변수 OPENAI_API_KEY에서만 읽는다.
# 사용:
#   python3 tools/openai_image.py "설명" 출력.png [--ref 참고.png ...] [--size 1536x1024] [--quality high] [--model gpt-image-2.5-sunburst]
#   --ref가 있으면 그 그림(들)을 참고해 새로 그린다(images/edits), 없으면 설명만으로 그린다(images/generations).
import argparse, base64, json, mimetypes, os, sys, urllib.request, uuid

API = "https://api.openai.com/v1/images/"


def post_json(url, body, key):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    return urllib.request.urlopen(req, timeout=300).read()


def post_multipart(url, fields, files, key):
    b = uuid.uuid4().hex
    parts = []
    for k, v in fields.items():
        parts.append(f"--{b}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode())
    for k, path in files:
        mime = mimetypes.guess_type(path)[0] or "image/png"
        head = f"--{b}\r\nContent-Disposition: form-data; name=\"{k}\"; filename=\"{os.path.basename(path)}\"\r\nContent-Type: {mime}\r\n\r\n"
        parts.append(head.encode() + open(path, "rb").read() + b"\r\n")
    parts.append(f"--{b}--\r\n".encode())
    req = urllib.request.Request(url, data=b"".join(parts), headers={"Authorization": "Bearer " + key, "Content-Type": "multipart/form-data; boundary=" + b})
    return urllib.request.urlopen(req, timeout=300).read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prompt")
    ap.add_argument("out")
    ap.add_argument("--ref", action="append", default=[])
    ap.add_argument("--size", default="1536x1024")
    ap.add_argument("--quality", default="high")
    ap.add_argument("--model", default="gpt-image-2.5-sunburst")
    a = ap.parse_args()
    key = os.environ.get("OPENAI_API_KEY", "")
    if not key:
        sys.exit("OPENAI_API_KEY가 없어요. 터미널에서 ~/.zshrc에 넣고 Claude Code를 다시 켜 주세요.")
    try:
        if a.ref:
            raw = post_multipart(API + "edits", {"model": a.model, "prompt": a.prompt, "size": a.size, "quality": a.quality},
                                 [("image[]", p) for p in a.ref], key)
        else:
            raw = post_json(API + "generations", {"model": a.model, "prompt": a.prompt, "size": a.size, "quality": a.quality}, key)
    except urllib.error.HTTPError as e:
        sys.exit("OpenAI 오류 %d: %s" % (e.code, e.read().decode(errors="replace")[:500]))
    res = json.loads(raw)
    open(a.out, "wb").write(base64.b64decode(res["data"][0]["b64_json"]))
    print("저장:", a.out)
    # 실제 쓴 토큰으로 비용 계산(2026-11-22 OpenAI 가격표: 이미지 입력 $8, 이미지 출력 $30, 글 입력 $5 / 100만 토큰)
    u = res.get("usage", {})
    det = u.get("input_tokens_details", {})
    img_in, txt_in, out = det.get("image_tokens", 0), det.get("text_tokens", 0), u.get("output_tokens", 0)
    cost = img_in * 8e-6 + txt_in * 5e-6 + out * 30e-6
    print("토큰: 그림 입력 %d, 글 입력 %d, 출력 %d → 약 $%.3f" % (img_in, txt_in, out, cost))


main()
