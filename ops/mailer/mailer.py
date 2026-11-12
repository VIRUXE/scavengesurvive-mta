"""Scavenge & Survive mailer: sends the rows the game queues in email_outbox (auth's email confirmation codes).

Every POLL_S seconds it takes the unsent rows with fewer than MAX_ATTEMPTS tries, sends each over SMTP (implicit TLS,
smtp.gmail.com:465 by default) and marks it sent, or counts the failed try with its error. The game never waits on
it: while this is down the rows simply wait.

Configuration (environment, see example.env; systemd reads /etc/scavengesurvive-mailer.env):
  SMTP_USER, SMTP_PASS        login (for Gmail an app password, not the account password)
  SMTP_HOST, SMTP_PORT        default smtp.gmail.com, 465
  MAIL_FROM                   From address, default SMTP_USER
  MAIL_FROM_NAME              From name, default "Scavenge & Survive"
  SSMTA_DB_HOST, SSMTA_DB_PORT, SSMTA_DB_NAME, SSMTA_DB_USER, SSMTA_DB_PASS (or SSMTA_DB_DEFAULTS_FILE)
  MAILER_POLL_S               seconds between polls, default 2

Usage: python3 mailer.py [--once] [--dry-run]
  --once     one pass, then exit
  --dry-run  print what would be sent (the body included) and change nothing; no SMTP login needed
"""
from __future__ import annotations

import argparse
import os
import smtplib
import ssl
import sys
import time
from email.message import EmailMessage
from email.utils import formataddr, make_msgid

import pymysql

MAX_ATTEMPTS = 5
BATCH = 20
# a row older than this is not worth sending any more: the code in it expired after 15 minutes
MAX_AGE_MIN = 30


def log(msg: str) -> None:
    print(time.strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


def connect():
    kwargs = dict(
        host=os.environ.get("SSMTA_DB_HOST", "127.0.0.1"),
        port=int(os.environ.get("SSMTA_DB_PORT", "3306")),
        database=os.environ.get("SSMTA_DB_NAME", "scavengesurvive"),
        charset="utf8mb4",
        connect_timeout=5,
        read_timeout=15,
        autocommit=True,
        cursorclass=pymysql.cursors.DictCursor,
    )
    defaults = os.environ.get("SSMTA_DB_DEFAULTS_FILE")
    if defaults:
        kwargs["read_default_file"] = defaults
    else:
        kwargs["user"] = os.environ.get("SSMTA_DB_USER", "")
        kwargs["password"] = os.environ.get("SSMTA_DB_PASS", "")
    return pymysql.connect(**kwargs)


def pending(db):
    with db.cursor() as cur:
        cur.execute(
            "SELECT id, to_addr, subject, body, attempts FROM email_outbox"
            " WHERE sent_at IS NULL AND attempts < %s AND created_at > NOW() - INTERVAL %s MINUTE"
            " ORDER BY id LIMIT %s",
            (MAX_ATTEMPTS, MAX_AGE_MIN, BATCH),
        )
        return cur.fetchall()


def build(row, sender: str, sender_name: str) -> EmailMessage:
    msg = EmailMessage()
    msg["From"] = formataddr((sender_name, sender))
    msg["To"] = row["to_addr"]
    msg["Subject"] = row["subject"]
    msg["Message-ID"] = make_msgid(domain=sender.split("@")[-1] or None)
    msg.set_content(row["body"])
    return msg


class Smtp:
    """One SMTP connection per batch, opened on first use and reopened after an error."""

    def __init__(self):
        self.host = os.environ.get("SMTP_HOST", "smtp.gmail.com")
        self.port = int(os.environ.get("SMTP_PORT", "465"))
        self.user = os.environ.get("SMTP_USER", "")
        self.password = os.environ.get("SMTP_PASS", "")
        self.conn = None

    def send(self, msg: EmailMessage) -> None:
        if self.conn is None:
            self.conn = smtplib.SMTP_SSL(self.host, self.port, context=ssl.create_default_context(), timeout=30)
            self.conn.login(self.user, self.password)
        try:
            self.conn.send_message(msg)
        except (smtplib.SMTPServerDisconnected, OSError):
            self.close()
            raise

    def close(self) -> None:
        if self.conn is not None:
            try:
                self.conn.quit()
            except Exception:
                pass
            self.conn = None


def run_once(db, smtp: Smtp | None, sender: str, sender_name: str, dry_run: bool) -> int:
    rows = pending(db)
    for row in rows:
        msg = build(row, sender, sender_name)
        if dry_run:
            print(f"--- outbox #{row['id']} (attempts {row['attempts']})\n{msg}", flush=True)
            continue
        try:
            smtp.send(msg)
        except Exception as e:  # noqa: BLE001 - every failure counts as a try
            err = f"{type(e).__name__}: {e}"[:500]
            with db.cursor() as cur:
                cur.execute(
                    "UPDATE email_outbox SET attempts = attempts + 1, last_error = %s WHERE id = %s", (err, row["id"])
                )
            log(f"outbox #{row['id']} failed (try {row['attempts'] + 1}): {err}")
            if isinstance(e, smtplib.SMTPAuthenticationError):
                smtp.close()
                break
            continue
        with db.cursor() as cur:
            cur.execute(
                "UPDATE email_outbox SET sent_at = NOW(), attempts = attempts + 1, last_error = NULL WHERE id = %s",
                (row["id"],),
            )
        log(f"outbox #{row['id']} sent")
    if smtp is not None:
        smtp.close()  # mail is rare: no idle connection for the server to drop between batches
    return len(rows)


def main() -> int:
    p = argparse.ArgumentParser(description="Send the queued email_outbox rows.")
    p.add_argument("--once", action="store_true", help="one pass, then exit")
    p.add_argument("--dry-run", action="store_true", help="print what would be sent, change nothing")
    args = p.parse_args()

    sender = os.environ.get("MAIL_FROM") or os.environ.get("SMTP_USER", "")
    sender_name = os.environ.get("MAIL_FROM_NAME", "Scavenge & Survive")
    poll = float(os.environ.get("MAILER_POLL_S", "2"))
    if not args.dry_run and not (os.environ.get("SMTP_USER") and os.environ.get("SMTP_PASS")):
        log("SMTP_USER and SMTP_PASS must be set")
        return 2
    smtp = None if args.dry_run else Smtp()
    db = None
    log(f"mailer started ({'dry run' if args.dry_run else 'from ' + sender})")
    while True:
        try:
            if db is None:
                db = connect()
            run_once(db, smtp, sender, sender_name, args.dry_run)
        except pymysql.MySQLError as e:
            log(f"database error: {e}")
            try:
                if db is not None:
                    db.close()
            except Exception:
                pass
            db = None
        if args.once or args.dry_run:
            break
        time.sleep(poll)
    if smtp is not None:
        smtp.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
