"""Replay boundaries and provenance: python3 -m unittest discover -s ops/dashboard -p 'test_*.py'."""
import unittest
from unittest.mock import patch

import server


def version(start, end, *, item=1, spawn=7, holder=None, container=None, x=20, created=0):
    return (item, "Bottle", 7, "ls", spawn, holder, container, x, 30, 0, 0, created, start, end)


class PlayerTrackTests(unittest.TestCase):
    def test_live_trail_window_uses_timestamp_with_or_without_seat(self):
        old = [10, 20, 3, 0, 0, 422, 699, 1]
        legacy = [10, 20, 3, 0, 0, 422, 700]
        driver = [10, 20, 3, 0, 0, 422, 950, 0]
        passenger = [10, 20, 3, 0, 0, 422, 999, 1]
        snapshot = {"at": 1000, "players": [{"char": 1, "trail": [old, legacy, driver, passenger]}]}
        with patch.object(server, "read_snapshot", return_value=snapshot), \
                patch.object(server, "session_starts", return_value={}), \
                patch.object(server.time, "time", return_value=1000):
            result = server.api_live({"trail": "300"})
        self.assertEqual(result["players"][0]["trail"], [legacy, driver, passenger])

    def test_track_preserves_driver_passenger_and_unknown_seats(self):
        rows = [(10, 20, 3, 0, 0, 422, 950, seat) for seat in (0, 1, None)]
        with patch.object(server, "query", return_value=rows), \
                patch.object(server, "sparse_points", return_value=[]):
            result = server.api_track({"account": "1", "from": "900", "to": "1000"})
        self.assertEqual([point[7] for point in result["points"]], [0, 1, None])
        self.assertEqual([point[6] for point in result["points"]], [950, 950, 950])


class LootHistoryTests(unittest.TestCase):
    def test_tracks_loot_after_spawn_link_is_cleared(self):
        rows = [
            version(0, 10),
            version(10, 20, spawn=None, holder=12, x=None),
            version(20, 30, spawn=None, container=55, x=None),
            version(30, 40, spawn=None, x=100),
            version(40, 50, spawn=None, x=100),  # a data/HP update, not another movement
        ]
        result = server.build_loot_history(rows, 5, 60)
        self.assertEqual(result["items"], [{"id": 1, "type": "Bottle", "spawn": 7, "zone": "ls"}])
        self.assertEqual(result["initial"][0]["state"]["place"], "spawn")
        self.assertEqual([(e["at"], e["kind"]) for e in result["events"]], [
            (10, "picked up"), (20, "stored"), (30, "dropped"), (50, "removed"),
        ])
        self.assertIsNone(result["events"][-1]["state"])

    def test_exact_start_uses_new_version_without_replaying_transition(self):
        result = server.build_loot_history([
            version(0, 10), version(10, 50, spawn=None, holder=12, x=None),
        ], 10, 40)
        self.assertEqual(result["initial"], [{"item": 1, "state": {"place": "carried", "holder": 12}}])
        self.assertEqual(result["events"], [])

    def test_deleted_at_start_is_absent(self):
        result = server.build_loot_history([version(0, 10)], 10, 40)
        self.assertEqual(result["initial"], [])
        self.assertEqual(result["events"], [])

    def test_spawn_and_removal_at_end_are_included_and_sorted(self):
        rows = [version(20, 50), version(15, 100, item=2, created=15)]
        result = server.build_loot_history(rows, 10, 50)
        self.assertEqual([(e["at"], e["kind"]) for e in result["events"]], [
            (15, "spawned"), (20, "first recorded"), (50, "removed"),
        ])

    def test_invalid_windows_do_not_query_database(self):
        with patch.object(server, "query") as query:
            for params in [
                {"from": "x", "to": "100"},
                {"from": "100", "to": "100"},
                {"from": "-1", "to": "100"},
                {"from": "0", "to": str(7 * 86400 + 1)},
                {"from": "9999999999", "to": "10000000000"},
            ]:
                with self.subTest(params=params), self.assertRaises(server.ApiError) as raised:
                    server.api_loot_history(params)
                self.assertEqual(raised.exception.status, 400)
            query.assert_not_called()

    def test_large_history_fails_explicitly_instead_of_truncating(self):
        with patch.object(server, "query", return_value=[None] * (server.LOOT_HISTORY_LIMIT + 1)):
            with self.assertRaises(server.ApiError) as raised:
                server.api_loot_history({"from": "10", "to": "20"})
            self.assertEqual(raised.exception.status, 413)

    def test_window_cache_is_bounded(self):
        cache = server.Cache()
        for i in range(40):
            cache.get(i, 30, lambda: i)
        self.assertEqual(len(cache.items), 32)
        self.assertNotIn(0, cache.items)
        self.assertIn(39, cache.items)


if __name__ == "__main__":
    unittest.main()
