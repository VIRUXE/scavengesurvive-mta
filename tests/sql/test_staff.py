"""M7 staff procedures: bans, warnings, action log (sql/migrations/0006_staff_m7.sql)."""
from tests.sql.conftest import call


def _account(db, name):
    with db.cursor() as cur:
        cur.execute("INSERT INTO accounts (name, password_hash, last_ip, last_serial) VALUES (%s, REPEAT('x', 60), '10.0.0.9', REPEAT('A', 32))",
                    (name,))
        return cur.lastrowid


def _unique(prefix):
    import uuid
    return f"{prefix}{uuid.uuid4().hex[:8]}"


def test_staff_ban_writes_ban_and_action_log(db):
    name = _unique("Ban")
    acc = _account(db, name)
    ok, code, payload = call(db, "staff_ban", name, acc, "10.0.0.9", "A" * 32, "cheating", None, "Mod", 3600)
    assert (ok, code) == (1, "OK"), code
    assert payload["ban_id"] > 0 and payload["expires_at"] is not None
    with db.cursor() as cur:
        cur.execute("SELECT active, serial, TIMESTAMPDIFF(MINUTE, NOW(), expires_at) AS mins FROM bans WHERE id=%s", (payload["ban_id"],))
        r = cur.fetchone()
        assert r["active"] == 1 and r["serial"] == "A" * 32 and 58 <= r["mins"] <= 60
        cur.execute("SELECT action, target_name, details FROM staff_actions WHERE target_name=%s ORDER BY id DESC LIMIT 1", (name,))
        a = cur.fetchone()
        assert a["action"] == "ban" and a["details"].startswith("cheating (until ")
    # a second ban on an active one is refused, and lifting it is logged
    ok, code, _ = call(db, "staff_ban", name, acc, None, None, "again", None, "Mod", 0)
    assert (ok, code) == (0, "ALREADY_BANNED")
    ok, code, payload = call(db, "staff_unban", name, None, "Lead")
    assert (ok, code) == (1, "OK") and payload["lifted"] == 1
    ok, code, _ = call(db, "staff_unban", name, None, "Lead")
    assert (ok, code) == (0, "NOT_BANNED")


def test_permanent_ban_has_no_expiry_and_the_event_ignores_it(db):
    name = _unique("Perma")
    ok, code, payload = call(db, "staff_ban", name, None, None, None, "forever", None, "Server", 0)
    assert (ok, code) == (1, "OK") and payload["expires_at"] is None
    with db.cursor() as cur:
        # the scheduler event body, run by hand: only expired timed bans flip
        cur.execute("UPDATE bans SET active = 0 WHERE active = 1 AND expires_at IS NOT NULL AND expires_at < NOW()")
        cur.execute("SELECT active FROM bans WHERE id=%s", (payload["ban_id"],))
        assert cur.fetchone()["active"] == 1
        cur.execute("SELECT COUNT(*) AS n FROM information_schema.events WHERE event_schema = DATABASE() AND event_name = 'ev_expire_bans'")
        assert cur.fetchone()["n"] == 1


def test_expired_timed_ban_is_deactivated_by_the_event_body(db):
    name = _unique("Timed")
    ok, _, payload = call(db, "staff_ban", name, None, None, None, "short", None, "Server", 1)
    assert ok == 1
    with db.cursor() as cur:
        cur.execute("UPDATE bans SET expires_at = NOW() - INTERVAL 1 MINUTE WHERE id=%s", (payload["ban_id"],))
        cur.execute("UPDATE bans SET active = 0 WHERE active = 1 AND expires_at IS NOT NULL AND expires_at < NOW()")
        cur.execute("SELECT active FROM bans WHERE id=%s", (payload["ban_id"],))
        assert cur.fetchone()["active"] == 0


def test_staff_warn_counts_up_and_bans_on_the_fifth(db):
    name = _unique("Warn")
    acc = _account(db, name)
    for i in range(1, 5):
        ok, code, payload = call(db, "staff_warn", acc, name, "10.0.0.9", None, None, "GM", f"reason {i}", 5, 86400)
        assert (ok, code) == (1, "OK") and payload == {"warnings": i, "banned": 0, "ban_id": 0}
    ok, code, payload = call(db, "staff_warn", acc, name, "10.0.0.9", None, None, "GM", "last straw", 5, 86400)
    assert (ok, code) == (1, "OK") and payload["warnings"] == 5 and payload["banned"] == 1 and payload["ban_id"] > 0
    with db.cursor() as cur:
        cur.execute("SELECT warnings FROM accounts WHERE id=%s", (acc,))
        assert cur.fetchone()["warnings"] == 0  # counter restarts after the ban
        cur.execute("SELECT reason, TIMESTAMPDIFF(HOUR, NOW(), expires_at) AS hours FROM bans WHERE id=%s", (payload["ban_id"],))
        r = cur.fetchone()
        assert r["reason"] == "Getting 5 warnings" and 23 <= r["hours"] <= 24
        cur.execute("SELECT COUNT(*) AS n FROM staff_actions WHERE target_account_id=%s AND action='warn'", (acc,))
        assert cur.fetchone()["n"] == 5
    ok, code, _ = call(db, "staff_warn", 0, "nobody", None, None, None, "GM", "x", 5, 86400)
    assert (ok, code) == (0, "NO_ACCOUNT")


def test_staff_settings_seeded(db):
    with db.cursor() as cur:
        cur.execute("SELECT skey, svalue FROM settings WHERE skey IN ('server.whitelist','staff.max_warnings','staff.warn_ban_hours')")
        rows = {r["skey"]: r["svalue"] for r in cur.fetchall()}
        assert rows == {"server.whitelist": "0", "staff.max_warnings": "5", "staff.warn_ban_hours": "24"}
