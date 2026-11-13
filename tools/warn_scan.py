"""GDScript warning scanner via Godot LSP.

Usage:
  godot --editor --path . --lsp-port 6017
  python tools/warn_scan.py 6017
"""
from __future__ import annotations

import json
import socket
import sys
import time
from pathlib import Path

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 6017
ROOT = Path(__file__).resolve().parents[1]


def encode(payload: dict) -> bytes:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    return f"Content-Length: {len(body)}\r\n\r\n".encode("ascii") + body


class Lsp:
    def __init__(self, sock: socket.socket):
        self.sock = sock
        self.buf = b""

    def send(self, payload: dict) -> None:
        self.sock.sendall(encode(payload))

    def read(self, timeout: float = 1.0):
        self.sock.settimeout(timeout)
        while True:
            header_end = self.buf.find(b"\r\n\r\n")
            if header_end >= 0:
                length = 0
                for line in self.buf[:header_end].decode("ascii", "replace").split("\r\n"):
                    if line.lower().startswith("content-length:"):
                        length = int(line.split(":", 1)[1])
                total = header_end + 4 + length
                if len(self.buf) >= total:
                    body = self.buf[header_end + 4:total]
                    self.buf = self.buf[total:]
                    return json.loads(body)
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                return None
            if not chunk:
                return None
            self.buf += chunk


def main() -> None:
    files = sorted(
        p for p in ROOT.rglob("*.gd")
        if ".godot" not in p.parts and "build" not in p.parts
    )
    sock = socket.create_connection(("127.0.0.1", PORT), timeout=3)
    lsp = Lsp(sock)
    lsp.send({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "processId": None,
            "rootUri": ROOT.as_uri(),
            "capabilities": {},
            "workspaceFolders": [{"uri": ROOT.as_uri(), "name": "skywire-remake"}],
        },
    })
    lsp.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    for path in files:
        lsp.send({
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": {
                "textDocument": {
                    "uri": path.as_uri(),
                    "languageId": "gdscript",
                    "version": 1,
                    "text": path.read_text(encoding="utf-8"),
                }
            },
        })
    deadline = time.time() + 10.0
    seen = {}
    while time.time() < deadline:
        msg = lsp.read(0.5)
        if not msg or msg.get("method") != "textDocument/publishDiagnostics":
            continue
        uri = msg["params"].get("uri", "")
        for item in msg["params"].get("diagnostics", []):
            key = (uri, item.get("code"), item.get("message"), item.get("range", {}).get("start", {}).get("line"))
            seen[key] = item
    by_uri = {}
    for (uri, *_), item in seen.items():
        by_uri.setdefault(uri, []).append(item)
    print(f"FILES SCANNED: {len(files)}")
    print(f"DIAGNOSTIC FILES: {len(by_uri)}")
    warnings = 0
    errors = 0
    for uri in sorted(by_uri):
        path = uri.replace("file:///", "").replace("%3A", ":").replace("%20", " ")
        for item in sorted(by_uri[uri], key=lambda d: d.get("range", {}).get("start", {}).get("line", 0)):
            severity = item.get("severity")
            warnings += severity == 2
            errors += severity == 1
            line = item.get("range", {}).get("start", {}).get("line", 0) + 1
            char = item.get("range", {}).get("start", {}).get("character", 0) + 1
            print(f"{path}:{line}:{char} severity={severity} code={item.get('code')} {item.get('message')}")
    print(f"WARNINGS: {warnings}")
    print(f"ERRORS: {errors}")
    sock.close()


if __name__ == "__main__":
    main()
