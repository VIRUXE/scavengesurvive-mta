#!/usr/bin/env python3
"""Chat translator for the game server: Claude Haiku through the Claude Code CLI, with the conversation as context.

POST /translate  {"speaker": "Juan", "mode": "global", "text": "...", "targets": ["en", "pt"]}
            ->   {"source": "es", "t": {"en": "...", "pt": "..."}}

One `claude -p` process stays up in stream-json mode, so every line said in game is a turn of the same session and
Haiku sees the recent conversation (who said what, what "the red one" refers to). The session is recycled every
MAX_TURNS lines, or on an error or timeout. Requests are handled one at a time, in the order the game sends them.
Only listens on 127.0.0.1.
"""
import json
import os
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST, PORT = "127.0.0.1", int(os.environ.get("SSMTA_TRANSLATOR_PORT", "8130"))
MODEL = os.environ.get("SSMTA_TRANSLATOR_MODEL", "haiku")
MAX_TURNS = int(os.environ.get("SSMTA_TRANSLATOR_MAX_TURNS", "150"))
TIMEOUT_S = float(os.environ.get("SSMTA_TRANSLATOR_TIMEOUT", "15"))
MAX_TEXT = 400

# the game's language codes (auth's list) and what they mean
LANGUAGES = {
    "en": "English",
    "es": "Spanish",
    "fr": "French",
    "pt": "European Portuguese (Portugal)",
    "ptbr": "Brazilian Portuguese",
    "ru": "Russian",
    "ro": "Romanian",
    "id": "Indonesian",
    "bhs": "Bosnian/Croatian/Serbian, Latin script",
    "cs": "Czech",
}

SYSTEM = """You translate the chat of Scavenge and Survive, a multiplayer survival server for GTA San Andreas \
(MTA:SA). Players scavenge loot, craft, build bases, drive cars, fight and talk in local, global, radio and admin \
chat. Each user turn is one chat line, in the form:

[mode] speaker: message
targets: code, code, ...

Target codes: """ + ", ".join(f"{c} = {n}" for c, n in LANGUAGES.items()) + """.

Earlier turns are the recent conversation: use them to resolve what a line refers to (items, places, people, \
"it", "the red one"), but translate only the current line.

Rules:
- Translate the meaning the way a player would write it in that language: casual, short, same tone, keep slang, \
swearing, emoticons and gaming abbreviations (lol, xd, gg, afk, brb) natural for the target language.
- Never translate player names, @mentions, coordinates, numbers or commands starting with /.
- GTA place names (Los Santos, San Fierro, Las Venturas, Grove Street, Mount Chiliad, ...) stay as they are.
- Leave out any target whose language the line is already written in. Portuguese written in either variety counts \
as both pt and ptbr; Bosnian, Croatian and Serbian count as bhs.
- If the line has nothing to translate (only a name, a number, "ok", "xd", an emoticon), return an empty "t".
- Reply with one JSON object and nothing else:
{"source": "<code of the language the line is written in: one of the target codes, or an ISO 639-1 code>", \
"t": {"<target code>": "<translation>"}}"""

CMD = [
    "claude", "-p",
    "--model", MODEL,
    "--effort", "low",
    "--setting-sources", "",
    "--tools", "",
    "--strict-mcp-config",
    "--disable-slash-commands",
    "--no-session-persistence",
    "--input-format", "stream-json",
    "--output-format", "stream-json",
    "--verbose",
    "--system-prompt", SYSTEM,
]


def log(*parts):
    print(time.strftime("%H:%M:%S"), *parts, file=sys.stderr, flush=True)


class Session:
    """The long-lived CLI process; ask() is only ever called under the server lock."""

    def __init__(self):
        self.proc = None
        self.turns = 0
        self.lines = None

    def start(self):
        self.stop()
        self.proc = subprocess.Popen(
            CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, bufsize=1, cwd=os.environ.get("SSMTA_TRANSLATOR_WORKDIR", "/var/lib/ssmta-translator"),
        )
        self.turns = 0
        self.lines = _reader(self.proc.stdout)
        log("session started, pid", self.proc.pid)

    def stop(self):
        if self.proc and self.proc.poll() is None:
            try:
                self.proc.stdin.close()
                self.proc.wait(timeout=5)
            except Exception:
                self.proc.kill()
        self.proc = None

    def ask(self, prompt):
        if not self.proc or self.proc.poll() is not None or self.turns >= MAX_TURNS:
            self.start()
        self.turns += 1
        msg = {"type": "user", "message": {"role": "user", "content": prompt}}
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()
        deadline = time.time() + TIMEOUT_S
        while True:
            line = self.lines.get(deadline - time.time())
            if line is None:
                raise TimeoutError("no result from claude")
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if event.get("type") == "result":
                if event.get("is_error"):
                    raise RuntimeError(str(event.get("result"))[:200])
                return event.get("result") or ""


class _reader:
    """Reads the CLI's stdout on a thread so ask() can time out."""

    def __init__(self, stream):
        self.buf = []
        self.cond = threading.Condition()
        self.eof = False
        threading.Thread(target=self._run, args=(stream,), daemon=True).start()

    def _run(self, stream):
        for line in stream:
            with self.cond:
                self.buf.append(line)
                self.cond.notify()
        with self.cond:
            self.eof = True
            self.cond.notify()

    def get(self, timeout):
        with self.cond:
            end = time.time() + max(timeout, 0)
            while not self.buf:
                left = end - time.time()
                if self.eof or left <= 0:
                    return None
                self.cond.wait(left)
            return self.buf.pop(0)


session = Session()
lock = threading.Lock()


def parse_reply(raw):
    start, end = raw.find("{"), raw.rfind("}")
    if start < 0 or end < start:
        raise ValueError("no JSON in reply")
    data = json.loads(raw[start:end + 1])
    t = data.get("t") if isinstance(data.get("t"), dict) else {}
    return {"source": str(data.get("source") or "?"), "t": {str(k): str(v) for k, v in t.items() if isinstance(v, str)}}


def translate(req):
    text = str(req.get("text") or "").strip()[:MAX_TEXT]
    targets = [t for t in req.get("targets") or [] if t in LANGUAGES]
    if not text or not targets:
        return {"source": "?", "t": {}}
    speaker = str(req.get("speaker") or "?")[:40]
    mode = str(req.get("mode") or "chat")[:12]
    prompt = f"[{mode}] {speaker}: {text}\ntargets: {', '.join(targets)}"
    with lock:
        started = time.time()
        try:
            raw = session.ask(prompt)
        except Exception as e:
            log("ask failed:", e)
            session.stop()
            raise
        out = parse_reply(raw)
        out["t"] = {k: v for k, v in out["t"].items() if k in targets}
        log(f"{time.time() - started:.2f}s", out["source"], "->", ",".join(out["t"]) or "-")
        return out


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            return self._send(200, {"ok": True, "turns": session.turns})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/translate":
            return self._send(404, {"error": "not found"})
        try:
            length = int(self.headers.get("Content-Length") or 0)
            req = json.loads(self.rfile.read(length) or b"{}")
            if isinstance(req, list):  # MTA's toJSON wraps the value in an array
                req = req[0] if req else {}
            self._send(200, translate(req))
        except Exception as e:
            self._send(502, {"error": str(e)[:200]})


def main():
    os.makedirs(os.environ.get("SSMTA_TRANSLATOR_WORKDIR", "/var/lib/ssmta-translator"), exist_ok=True)
    with lock:
        session.start()
    log(f"listening on {HOST}:{PORT}, model {MODEL}")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
