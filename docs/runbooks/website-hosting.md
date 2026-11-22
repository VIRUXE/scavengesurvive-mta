# Website hosting (scavengesurvive-reborn.com)

**When:** the website, `discord.` or `sv.scavengesurvive-reborn.com` is down, a deploy fails, the deploy key has to be
rotated, the Discord invite changes, or the site moves to another host.

**What runs where:**

| Piece | Where | Notes |
| --- | --- | --- |
| Domain | Namecheap (registrar), bought 2026-11-22 | nameservers set to Cloudflare's `arya` / `matias.ns.cloudflare.com` |
| DNS | Cloudflare, zone `scavengesurvive-reborn.com` (Free) | `A @`, `A discord` → `78.47.205.20` (juniper), `CNAME www` → apex, all proxied; SSL/TLS **Full (strict)** |
| Web server | juniper (`juniper.flaviopereira.dev`), nginx | `/etc/nginx/sites-available/scavengesurvive-reborn.com`: apex serves `/var/www/scavengesurvive-reborn.com/public`, `www` 301s to the apex, `discord` 302s to the invite; logs `/var/log/nginx/ssr_*.log` |
| Certificate | certbot, `--cert-name scavengesurvive-reborn.com` | webroot `/var/www/letsencrypt` (`snippets/acme.conf`), covers apex, `www` and `discord`; renewed by certbot's own timer (HTTP-01 works through the Cloudflare proxy) |
| Deploy | `.github/workflows/pages.yml`, job `site` | rsyncs `site/` (minus `PLACEHOLDERS.md`) on every push to `main` that touches `site/`; user `deploy-ssr` (home `/var/www/scavengesurvive-reborn.com`), key in `~/.ssh/authorized_keys` limited to `restrict,command="/usr/bin/rrsync /var/www/scavengesurvive-reborn.com/public"` |
| Old URL | GitHub Pages, job `pages` | `viruxe.github.io/scavengesurvive-mta/<path>` forwards to `scavengesurvive-reborn.com/<path>` (generated stub, `noindex`) |
| Game server name | `CNAME sv` → `nasa.flaviopereira.dev`, **DNS only** | the only address players, the site, the wiki and Rich Presence use; no port needed since the server listens on MTA's default 22003. It follows nasa's own record, which nasa's cron `/root/ddns-update.sh` keeps on the WAN IP. Never proxy it: Cloudflare's proxy carries no UDP game traffic |
| Downloads and renders | `CNAME dl` → `nasa.flaviopereira.dev`, **DNS only**; nginx on nasa (`/etc/nginx/sites-available/dl.scavengesurvive-reborn.com`, certbot webroot `/var/www/html`) | `/downloads/` is the MTA `httpdownloadurl` (`http://dl.scavengesurvive-reborn.com/downloads` in prod `mtaserver.conf`, plain HTTP, gzip, the server's `resource-cache/http-client-files`); `/images/items/` serves `docs/images/items/all/` for the Discord #spawns embeds (`discordchat` `spawnImageBase`). Replaces `ss.flaviopereira.dev` |
| Discord invite | `discord.gg/CAs9Nsta8d` | never expires, made for this link in the Scavenge & Survive Reborn server (lands in `#general`) |

## Checks

```
curl -sI https://scavengesurvive-reborn.com/ | head -1          # 200, server: cloudflare
curl -sI https://www.scavengesurvive-reborn.com/x | grep -i location
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

If juniper's host key changes: `ssh-keyscan -t ed25519,rsa,ecdsa juniper.flaviopereira.dev | gh secret set JUNIPER_KNOWN_HOSTS`.

## Change the Discord invite

Edit the `return 302 https://discord.gg/...` line in the `discord.scavengesurvive-reborn.com` server block on juniper,
`nginx -t && systemctl reload nginx`, and update the invite in this runbook. Nothing in the repository links the
invite itself: the site, README and wiki link `https://discord.scavengesurvive-reborn.com`.
