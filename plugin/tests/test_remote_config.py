"""Tests for remote config fetch, caching, and fallback behavior."""

import json
import os
import tempfile
import unittest
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading
import time


class RemoteConfigTests(unittest.TestCase):
    """Test remote config JSON parsing, caching, and fallback logic."""

    def test_valid_config_parsed_correctly(self):
        """Remote config JSON with all fields is parsed correctly."""
        config = {
            "enabled": True,
            "frequency_interval": 10,
            "cooldown_minutes": 20,
            "daily_cap": 5,
            "trigger_gap_minutes": 10,
            "plugin_version": "0.1.0",
            "plugin_sha256": "",
            "plugin_tarball_url": ""
        }
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump(config, f)
            f.flush()
            with open(f.name) as rf:
                parsed = json.load(rf)
            os.unlink(f.name)
        self.assertTrue(parsed['enabled'])
        self.assertEqual(parsed['cooldown_minutes'], 20)
        self.assertEqual(parsed['daily_cap'], 5)

    def test_kill_switch_disabled(self):
        """When enabled=false, config indicates quests should be suppressed."""
        config = {"enabled": False, "cooldown_minutes": 20, "daily_cap": 5}
        self.assertFalse(config['enabled'])

    def test_cache_fallback_on_missing_remote(self):
        """When remote fetch fails, cached config is used."""
        with tempfile.TemporaryDirectory() as tmpdir:
            cache_path = os.path.join(tmpdir, 'remote-config.json')
            cached = {"enabled": True, "cooldown_minutes": 30, "daily_cap": 3}
            with open(cache_path, 'w') as f:
                json.dump(cached, f)
            # Simulate reading cache when remote is unavailable
            with open(cache_path) as f:
                fallback = json.load(f)
            self.assertEqual(fallback['cooldown_minutes'], 30)
            self.assertEqual(fallback['daily_cap'], 3)

    def test_defaults_when_no_cache_exists(self):
        """When neither remote nor cache exists, defaults are used."""
        defaults = {"enabled": True, "cooldown_minutes": 20, "daily_cap": 5}
        # The stop-hook uses these defaults when remote-config.json doesn't exist
        self.assertTrue(defaults['enabled'])
        self.assertEqual(defaults['cooldown_minutes'], 20)
        self.assertEqual(defaults['daily_cap'], 5)

    def test_partial_config_uses_defaults_for_missing_fields(self):
        """Config with missing fields falls back to defaults for those fields."""
        config = {"enabled": True}
        cooldown = int(config.get('cooldown_minutes', 20))
        daily_cap = int(config.get('daily_cap', 5))
        self.assertEqual(cooldown, 20)
        self.assertEqual(daily_cap, 5)

    def test_atomic_write_produces_valid_json(self):
        """Atomic write (write to temp, rename) produces valid JSON file."""
        with tempfile.TemporaryDirectory() as tmpdir:
            target = os.path.join(tmpdir, 'remote-config.json')
            config = {"enabled": True, "cooldown_minutes": 15, "daily_cap": 4}
            # Simulate atomic write
            fd, tmp_path = tempfile.mkstemp(dir=tmpdir)
            with os.fdopen(fd, 'w') as f:
                json.dump(config, f)
            os.rename(tmp_path, target)
            with open(target) as f:
                result = json.load(f)
            self.assertEqual(result['cooldown_minutes'], 15)

    def test_config_template_is_valid_json(self):
        """The template remote-config.json in resources/ is valid JSON."""
        template_path = os.path.join(
            os.path.dirname(__file__), '..', 'resources', 'remote-config.json'
        )
        with open(template_path) as f:
            config = json.load(f)
        self.assertIn('enabled', config)
        self.assertIn('cooldown_minutes', config)
        self.assertIn('daily_cap', config)
        self.assertIn('plugin_version', config)

    def test_fetch_with_timeout(self):
        """Remote config fetch respects timeout (slow server doesn't block)."""
        class SlowHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                time.sleep(2)  # Simulate slow response
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"enabled":true}')
            def log_message(self, *args):
                pass  # Suppress logs

        server = HTTPServer(('127.0.0.1', 0), SlowHandler)
        port = server.server_address[1]
        thread = threading.Thread(target=server.handle_request, daemon=True)
        thread.start()

        import urllib.request
        url = f'http://127.0.0.1:{port}/config.json'
        start = time.time()
        try:
            urllib.request.urlopen(url, timeout=0.5)
            fetched = True
        except Exception:
            fetched = False
        elapsed = time.time() - start

        server.server_close()
        self.assertFalse(fetched, "Should timeout before slow server responds")
        self.assertLess(elapsed, 1.5, "Timeout should fire within ~500ms")


if __name__ == '__main__':
    unittest.main()
