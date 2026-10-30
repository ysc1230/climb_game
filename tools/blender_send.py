"""로컬 Blender MCP 애드온(localhost:9876)에 Python 파일을 보내 실행한다.
사용: python3 -I tools/blender_send.py art_source/character/build_climber.py"""
import json, socket, sys

code = open(sys.argv[1], encoding="utf-8").read()
s = socket.create_connection(("localhost", 9876), timeout=600)
s.sendall(json.dumps({"type": "execute_code", "params": {"code": code}}).encode())
buf = b""
while True:
    chunk = s.recv(65536)
    if not chunk:
        break
    buf += chunk
    try:
        reply = json.loads(buf)
        break
    except json.JSONDecodeError:
        continue
res = reply.get("result", reply)
print(res.get("result", res) if isinstance(res, dict) else res)
if reply.get("status") != "success":
    sys.exit(1)
