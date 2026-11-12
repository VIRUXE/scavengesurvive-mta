# Mailer (email confirmation codes)

`auth` never sends mail itself: when a player has to confirm an email address it inserts a row into `email_outbox`
(to, subject, plain-text body with the 6-digit code). `mailer.py` polls that table every 2 s and sends each row over
SMTP with implicit TLS (`smtp.gmail.com:465` by default), then sets `sent_at`, or adds one to `attempts` and stores
`last_error`. A row gets at most 5 tries and is skipped once it is 30 minutes old (its code expired after 15). While
the mailer is down nothing breaks: rows wait, and players see "check your inbox and spam folder; it can take a
minute".

Python 3 standard library plus `pymysql` (the Debian `python3-pymysql` package, as `ops/dashboard` uses).

## Install
1. A database user that can only read and mark the outbox:
   `CREATE USER 'ssmta_mailer'@'127.0.0.1' IDENTIFIED BY '…';`
   `GRANT SELECT, UPDATE ON scavengesurvive.email_outbox TO 'ssmta_mailer'@'127.0.0.1';`
2. `/etc/scavengesurvive-mailer.env` from `example.env` (mode 0640, group mta): SMTP login (a Gmail app password),
   `MAIL_FROM_NAME`, the database user above.
3. Check it: `sudo -u mta bash -c 'set -a; . /etc/scavengesurvive-mailer.env; exec python3 mailer.py --dry-run'`
   prints what is queued without sending; `--once` sends one pass (quote values with spaces or `&` in the env file;
   systemd and the shell both read `KEY="value"`).
4. `cp scavengesurvive-mailer.service /etc/systemd/system/ && systemctl enable --now scavengesurvive-mailer`.
   Logs: `journalctl -u scavengesurvive-mailer`.

## Checks
- Queue: `SELECT id, to_addr, created_at, sent_at, attempts, last_error FROM email_outbox ORDER BY id DESC LIMIT 20;`
- A row stuck at 5 attempts never goes out; the player asks for a new code in the dialog (empty box + Accept).
- Gmail sends about 500 mails a day from a normal account; past that it refuses with a 5.4.5 error in `last_error`.
