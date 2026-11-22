# Website hosting (scavengesurvive-reborn.com)

**When:** the website, `discord.`, `wiki.` or `sv.scavengesurvive-reborn.com` is down, a deploy fails, the deploy key has to be
rotated, the Discord invite changes, or the site moves to another host.

**What runs where:**

| Piece | Where | Notes |
| --- | --- | --- |
| Domain | Namecheap (registrar), bought 2026-11-22 | nameservers set to Cloudflare's `arya` / `matias.ns.cloudflare.com` |
| DNS | Cloudflare, zone `scavengesurvive-reborn.com` (Free) | `A @`, `A discord`, `A wiki` → `78.47.205.20` (juniper), `CNAME www` → apex, all proxied; `www` is the canonical host; SSL/TLS **Full (strict)** |
| Web server | juniper (`juniper.flaviopereira.dev`), nginx | `/etc/nginx/sites-available/scavengesurvive-reborn.com`: `www` serves `/var/www/scavengesurvive-reborn.com/public`, the apex and all `http://` 301 to `https://www`, `discord` 302s to the invite, `wiki` serves `/var/www/scavengesurvive-reborn.com/wiki` (English at `/`, Portuguese under `/pt/`, `/Home` 301s to `/`); logs `/var/log/nginx/ssr_*.log` |
| Certificate | certbot, `--cert-name scavengesurvive-reborn.com` | webroot `/var/www/letsencrypt` (`snippets/acme.conf`), covers apex, `www`, `discord` and `wiki`; renewed by certbot's own timer (HTTP-01 works through the Cloudflare proxy) |
| Deploy | `.github/workflows/pages.yml`, job `site` | rsyncs `site/` (minus `PLACEHOLDERS.md`) on every push to `main` that touches `site/`; user `deploy-ssr` (home `/var/www/scavengesurvive-reborn.com`), key in `~/.ssh/authorized_keys` limited to `restrict,command="/usr/bin/rrsync /var/www/scavengesurvive-reborn.com/public"` |
| Wiki deploy | `.github/workflows/pages.yml`, job `wiki-site` | `python -m tools.wiki_site --strict` builds `wiki/` (MkDocs Material, pictures from `docs/images`) and rsyncs `build/wiki-site/` as `deploy-ssr` with a second key (secret `JUNIPER_WIKI_DEPLOY_KEY`), limited to `restrict,command="/usr/bin/rrsync /var/www/scavengesurvive-reborn.com/wiki"`; the `wiki` job turns every GitHub wiki page into a stub linking its new address |
| Old URL | GitHub Pages, job `pages` | `viruxe.github.io/scavengesurvive-mta/<path>` forwards to `scavengesurvive-reborn.com/<path>` (generated stub, `noindex`) |
| Game server name | `CNAME sv` → `nasa.flaviopereira.dev`, **DNS only** | the only address players, the site, the wiki and Rich Presence use; no port needed since the server listens on MTA's default 22003. It follows nasa's own record, which nasa's cron `/root/ddns-update.sh` keeps on the WAN IP. Never proxy it: Cloudflare's proxy carries no UDP game traffic |
| Downloads and renders | `CNAME dl` → `nasa.flaviopereira.dev`, **proxied** (since 2026-11-22); nginx on nasa (`/etc/nginx/sites-available/dl.scavengesurvive-reborn.com`, certbot webroot `/var/www/html`) | `/downloads/` is the MTA `httpdownloadurl` (`http://dl.scavengesurvive-reborn.com/downloads` in prod `mtaserver.conf`, plain HTTP, gzip, the server's `resource-cache/http-client-files`), cached at Cloudflare's edges (see [Downloads through Cloudflare](#downloads-through-cloudflare)); `/images/items/` serves `docs/images/items/all/` for the Discord #spawns embeds (`discordchat` `spawnImageBase`). Replaces `ss.flaviopereira.dev`, which still serves the same folder unproxied at `/reborn/downloads/` |
| Discord invite | `discord.gg/CAs9Nsta8d` | never expires, made for this link in the Scavenge & Survive Reborn server (lands in `#general`) |

## Checks

```
curl -sI https://www.scavengesurvive-reborn.com/ | head -1          # 200, server: cloudflare
curl -sI http://scavengesurvive-reborn.com/x | grep -i location   # https://www.../x
curl -sI https://discord.scavengesurvive-reborn.com/ | grep -i location
ssh juniper.flaviopereira.dev 'nginx -t; certbot certificates --cert-name scavengesurvive-reborn.com'
```

A failed deploy shows in the `site` job of the `pages` workflow (`gh run list --workflow pages.yml`); rerun it with
`gh workflow run pages.yml` once fixed.

## Rotate the deploy key

1. `ssh-keygen -t ed25519 -N "" -C "github-actions deploy scavengesurvive-reborn.com" -f ssr_deploy`
2. On juniper, replace the key in `/var/www/scavengesurvive-reborn.com/.ssh/authorized_keys`, keeping the
   `restrict,command="/usr/bin/rrsync /var/www/scavengesurvive-reborn.com/public"` prefix (owner `deploy-ssr`, mode 600).
3. `gh secret set JUNIPER_DEPLOY_KEY < ssr_deploy`, delete the local private key, `gh workflow run pages.yml`.

The wiki key is rotated the same way: `-C "github-actions deploy wiki.scavengesurvive-reborn.com"`, the
`/var/www/scavengesurvive-reborn.com/wiki` rrsync root, and the `JUNIPER_WIKI_DEPLOY_KEY` secret.

To deploy the wiki by hand (the workflow failed, or a test build): `python -m tools.wiki_site --strict`, then
`tar czf - -C build/wiki-site . | ssh juniper.flaviopereira.dev 'tar xzf - -C /var/www/scavengesurvive-reborn.com/wiki --no-same-owner && chown -R deploy-ssr: /var/www/scavengesurvive-reborn.com/wiki'`
(old files stay until the next rsync `--delete`).

If juniper's host key changes: `ssh-keyscan -t ed25519,rsa,ecdsa juniper.flaviopereira.dev | gh secret set JUNIPER_KNOWN_HOSTS`.

## Downloads through Cloudflare

MTA clients fetch every resource file from `http://dl.scavengesurvive-reborn.com/downloads/<resource>/<file>`; with the
proxy on, a Cloudflare edge near the player answers instead of nasa (before/after:
`docs/reviews/2026-11-22-download-cdn.md`). The pieces:

- **Cache Rule** (zone `scavengesurvive-reborn.com`, phase `http_request_cache_settings`): host `dl…` and path starting
  `/downloads/` → eligible for cache, edge and browser TTL from the origin.
- **nginx on nasa** sends `Cache-Control: public, max-age=86400` on `/downloads/`, so an edge keeps a file a day and
  then revalidates it (a 304 when unchanged). The TTL lives in nginx because the Free plan has a minimum for rule
  overrides. A 5-minute TTL was tried first: copies expired between joins and the revalidation made small files slower
  than going direct (see the review).
- **Smart Tiered Cache** is on for the zone: an edge that misses fills from a Cloudflare tier near nasa.
- **Configuration Rule** (phase `http_config_settings`): host `dl…` → Browser Integrity Check off, Security Level
  "essentially off". The MTA client (`User-Agent: MTA:SA Server <ip>:22003 - See http://mtasa.com/agent/`) cannot pass a
  challenge; a challenge page would make it drop the external URL for the whole join.
- **Real client IPs:** `snippets/cloudflare-realip.conf` (Cloudflare's ranges from `https://www.cloudflare.com/ips/`,
  `real_ip_header CF-Connecting-IP`) is included in both `dl` server blocks. Refresh it if Cloudflare adds ranges.
- **Access log:** `/var/log/nginx/mta-downloads.log` (both `dl` and `ss`), rotated with the other nginx logs. With the
  proxy, only edge misses and revalidations reach it.

**After an `rr`, purge that resource:** Cloudflare dashboard → Caching → Configuration → Custom Purge → Prefix
`dl.scavengesurvive-reborn.com/downloads/<resource>/` (or the API: `POST /zones/<zone>/purge_cache` with
`{"prefixes": ["dl.scavengesurvive-reborn.com/downloads/<resource>/"]}`). Without it, edges keep the old copies of
that resource's changed files for up to a day.

**Stale files are safe.** An unpurged edge serves the old copy of a changed file. The client checksums every
file against the server (`CResourceFileDownloadManager.cpp` in mtasa-blue): on a mismatch it fetches that one file again
from the game server's own HTTP port (22005) and the server logs
`DIAGNOSTIC: <player> #1011 External HTTP file mismatch (Retrying this file with internal HTTP) [<file>]` in
`logs/server.log`. If the external URL fails outright (error or challenge) the client logs `#1012 … (Disabling External
HTTP)` and takes the rest of that join from port 22005 over one connection: a run of `#1012` means Cloudflare is
refusing the client. Check: `grep -c '#1011\|#1012' /gta/sa/mta/servers/scavengesurvive/mods/deathmatch/logs/server.log`.

```
curl -s -o /dev/null -D - http://dl.scavengesurvive-reborn.com/downloads/hat_models/hats.lua | grep -i 'cf-cache-status\|cache-control'
```

To take Cloudflare out: set `dl` back to DNS only (orange cloud off); nothing else needs to change.

## Change the Discord invite

Edit the `return 302 https://discord.gg/...` line in the `discord.scavengesurvive-reborn.com` server block on juniper,
`nginx -t && systemctl reload nginx`, and update the invite in this runbook. Nothing in the repository links the
invite itself: the site, README and wiki link `https://discord.scavengesurvive-reborn.com`.
