#!/usr/bin/env python3
"""Chat translator for the game server: Claude Haiku through the Claude Code CLI, with the conversation as context.

POST /translate  {"speaker": "Juan", "mode": "global", "text": "...", "targets": ["en", "pt"]}
            ->   {"source": "es", "t": {"en": "...", "pt": "..."}}

One `claude -p` process stays up in stream-json mode, so every line said in game is a turn of the same session and
Haiku sees the recent conversation (who said what, what "the red one" refers to). The session is recycled every
MAX_TURNS lines, or on an error or timeout. Requests are handled one at a time, in the order the game sends them.
Only listens on 127.0.0.1.

Fallback: when Claude fails (error, timeout, usage limit), the line goes to Google Cloud Translation v2 instead
(key in SSMTA_GOOGLE_TRANSLATE_KEY), one call per target, without context, and Claude is skipped for a while
(CLAUDE_PAUSE_LIMIT_S after a usage-limit error, CLAUDE_PAUSE_S after anything else).
"""
import json
import os
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST, PORT = "127.0.0.1", int(os.environ.get("SSMTA_TRANSLATOR_PORT", "8130"))
MODEL = os.environ.get("SSMTA_TRANSLATOR_MODEL", "haiku")
MAX_TURNS = int(os.environ.get("SSMTA_TRANSLATOR_MAX_TURNS", "150"))
TIMEOUT_S = float(os.environ.get("SSMTA_TRANSLATOR_TIMEOUT", "15"))
MAX_TEXT = 400
GOOGLE_KEY = os.environ.get("SSMTA_GOOGLE_TRANSLATE_KEY", "")
GOOGLE_URL = "https://translation.googleapis.com/language/translate/v2"
CLAUDE_PAUSE_S = 60
CLAUDE_PAUSE_LIMIT_S = 900
LIMIT_WORDS = ("limit", "quota", "usage", "rate", "overloaded", "credit")

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
    "lv": "Latvian",
    "ary": "Moroccan Darija, written in Latin script (Arabizi: 3, 7, 9 for ع ح ق)",
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
claude_paused_until = 0.0

# the game's codes to Google's (Google's "pt" is Brazilian; Google writes Darija/Arabic in Arabic script, which MTA
# can't shape, so Darija readers get French); and Google's detected source back to a game code
GOOGLE_TARGETS = {"en": "en", "es": "es", "fr": "fr", "pt": "pt-PT", "ptbr": "pt", "ru": "ru", "ro": "ro",
                  "id": "id", "bhs": "hr", "cs": "cs", "lv": "lv", "ary": "fr"}
GOOGLE_SOURCES = {"pt": "pt", "bs": "bhs", "hr": "bhs", "sr": "bhs"}


def same_language(source, code):
    """A line detected as `source` (game code or ISO) needs no translation for readers of game code `code`."""
    if code in ("pt", "ptbr"):
        return source in ("pt", "ptbr")
    return source == code


_getaddrinfo = socket.getaddrinfo


def _ipv4_only(host, *args, **kwargs):
    # this box has no IPv6 route out; trying AAAA first stalls every call for seconds
    return [a for a in _getaddrinfo(host, *args, **kwargs) if a[0] == socket.AF_INET]


socket.getaddrinfo = _ipv4_only


def google_translate(text, targets):
    if not GOOGLE_KEY:
        raise RuntimeError("no Google key")
    out, source = {}, "?"
    for code in targets:
        body = urllib.parse.urlencode({"q": text, "target": GOOGLE_TARGETS[code], "format": "text"}).encode()
        req = urllib.request.Request(GOOGLE_URL + "?key=" + GOOGLE_KEY, data=body, method="POST")
        with urllib.request.urlopen(req, timeout=5) as resp:
            t = json.loads(resp.read())["data"]["translations"][0]
        detected = str(t.get("detectedSourceLanguage") or "?").lower()
        source = GOOGLE_SOURCES.get(detected, detected)
        if same_language(source, code):
            continue
        out[code] = t["translatedText"].replace("&#39;", "'").replace("&quot;", '"').replace("&amp;", "&")
    return {"source": source, "t": out, "via": "google"}


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
    global claude_paused_until
    with lock:
        started = time.time()
        if time.time() >= claude_paused_until:
            try:
                out = parse_reply(session.ask(prompt))
                out["t"] = {k: v for k, v in out["t"].items() if k in targets}
                out["via"] = "claude"
                log(f"{time.time() - started:.2f}s claude", out["source"], "->", ",".join(out["t"]) or "-")
                return out
            except Exception as e:
                limited = any(w in str(e).lower() for w in LIMIT_WORDS)
                claude_paused_until = time.time() + (CLAUDE_PAUSE_LIMIT_S if limited else CLAUDE_PAUSE_S)
                log("claude failed, Google for", CLAUDE_PAUSE_LIMIT_S if limited else CLAUDE_PAUSE_S, "s:", e)
                session.stop()
        out = google_translate(text, targets)
        log(f"{time.time() - started:.2f}s google", out["source"], "->", ",".join(out["t"]) or "-")
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
            paused = max(0, round(claude_paused_until - time.time()))
            return self._send(200, {"ok": True, "turns": session.turns, "claude_paused_s": paused})
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
