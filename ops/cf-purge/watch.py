"""Purge changed MTA client files from the Cloudflare edge.

httpdownloadurl points at dl.scavengesurvive-reborn.com/downloads, which Cloudflare caches for a day. When a
resource changes, MTA rewrites its copy under resource-cache/http-client-files, but the edge can still hold the
old bytes. A client that gets them fails the checksum (#1011), and the fallback over the server's own HTTP fails
too when the old file is still on its disk (#1013 "File not readable"). If the bad file is a script, that resource
does not start on that client. data/shared/api.lua failing is why world items showed no models on first join.

This polls http-client-files and, once a batch of changes has settled, purges each changed file's URL (http and
https) through the Cloudflare API. It uses polling instead of inotify (inotify-tools is not installed), and a full
scan of the ~5k files takes a few milliseconds.

Env (/etc/ssmta-cf-purge.env, mode 0600):
  CF_API_TOKEN  token with Zone > Cache Purge on the scavengesurvive-reborn.com zone
  CF_ZONE_ID    that zone's id
Optional: SSMTA_CF_ROOT, SSMTA_CF_BASE_URL, SSMTA_CF_POLL_S (5), SSMTA_CF_SETTLE_S (10).
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.environ.get(
    "SSMTA_CF_ROOT",
    "/gta/sa/mta/servers/scavengesurvive/mods/deathmatch/resource-cache/http-client-files",
)
BASE = os.environ.get("SSMTA_CF_BASE_URL", "dl.scavengesurvive-reborn.com/downloads")
POLL_S = float(os.environ.get("SSMTA_CF_POLL_S", "5"))
SETTLE_S = float(os.environ.get("SSMTA_CF_SETTLE_S", "10"))
TOKEN = os.environ.get("CF_API_TOKEN", "")
ZONE = os.environ.get("CF_ZONE_ID", "")
BATCH = 30  # Cloudflare's per-request limit for purge by URL on non-Enterprise plans


def log(msg):
    print(msg, flush=True)


def scan():
    state = {}
    for dirpath, _, files in os.walk(ROOT):
        for name in files:
            path = os.path.join(dirpath, name)
            try:
                st = os.stat(path)
            except FileNotFoundError:
                continue
            state[os.path.relpath(path, ROOT)] = (st.st_mtime_ns, st.st_size)
    return state


def urls_for(rel):
    path = urllib.parse.quote(rel.replace(os.sep, "/"))
    return [f"{scheme}://{BASE}/{path}" for scheme in ("http", "https")]


def purge(urls):
    req = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/zones/{ZONE}/purge_cache",
        data=json.dumps({"files": urls}).encode(),
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = json.load(resp)
    except urllib.error.HTTPError as e:
        body = {"success": False, "errors": e.read().decode(errors="replace")}
    except OSError as e:
        body = {"success": False, "errors": str(e)}
    return body.get("success", False), body.get("errors")


def purge_all(rels):
    urls = [u for rel in sorted(rels) for u in urls_for(rel)]
    failed = []
    for i in range(0, len(urls), BATCH):
        chunk = urls[i : i + BATCH]
        for attempt in range(3):
            ok, errors = purge(chunk)
            if ok:
                break
            log(f"purge failed (attempt {attempt + 1}): {errors}")
            time.sleep(5 * (attempt + 1))
        else:
            failed.extend(chunk)
    log(f"purged {len(rels)} file(s), {len(urls) - len(failed)}/{len(urls)} urls ok: {', '.join(sorted(rels)[:10])}"
        + (" ..." if len(rels) > 10 else ""))
    return failed


def main():
    if not TOKEN or not ZONE:
        log("CF_API_TOKEN / CF_ZONE_ID not set; nothing to do")
        return 1
    if "--once" in sys.argv:  # purge the given relative paths and exit, e.g. watch.py --once data/shared/api.lua
        rels = [a for a in sys.argv[1:] if a != "--once"]
        return 1 if purge_all(rels) else 0
    known = scan()
    log(f"watching {len(known)} files under {ROOT}")
    pending, last_change = set(), 0.0
    while True:
        time.sleep(POLL_S)
        now = scan()
        changed = {rel for rel, sig in now.items() if known.get(rel) != sig}
        known = now
        if changed:
            pending |= changed
            last_change = time.monotonic()
        if pending and time.monotonic() - last_change >= SETTLE_S:
            batch, pending = pending, set()
            purge_all(batch)


if __name__ == "__main__":
    sys.exit(main())
