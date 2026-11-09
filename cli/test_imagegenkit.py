"""Unit tests for the imagegenkit CLI (stdlib only, no real providers).

    /usr/bin/python3 -m unittest discover -s cli
"""
import atexit
import base64
import importlib.util
import shutil
import json
import os
import sys
import tempfile
import threading
import types
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

HOME = tempfile.mkdtemp(prefix="igk-test-")
atexit.register(shutil.rmtree, HOME, True)
os.environ["HOME"] = HOME  # the module reads ~/.config/imagegenkit at import
os.environ["IMAGEGENKIT_NO_UPDATE"] = "1"
_spec = importlib.util.spec_from_file_location("imagegenkit", Path(__file__).with_name("imagegenkit.py"))
igk = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(igk)

PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC")


class Handler(BaseHTTPRequestHandler):
    requests = []

    def log_message(self, *a):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        Handler.requests.append({"path": self.path, "auth": self.headers.get("Authorization"), "body": body})
        mode = self.path.split("/")[1]
        raw = {"badjson": b"{nope", "html": b"<html>oops</html>"}.get(mode)
        if raw is None:
            raw = json.dumps({"data": [{"b64_json": base64.b64encode(PNG).decode()}], "usage": {"cost": 0.01}}).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


def args(**kw):
    a = dict(prompt="a cat", prompt_file=None, out=None, image=None, n=1, model=None, aspect=None, resolution=None,
             size=None, quality=None, background=None, format=None, compression=None, moderation=None, mask=None,
             extra=None, overwrite=False, dry_run=False, provider=None)
    a.update(kw)
    return types.SimpleNamespace(**a)


class CLITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = HTTPServer(("127.0.0.1", 0), Handler)
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def test_openrouter_sends_the_api_key(self):
        os.environ["ZZ_OR_API_KEY"] = "or-test-key"
        spec = {"name": "zz-or", "label": "OR", "type": "openrouter", "env": "ZZ_OR_API_KEY",
                "base_url": f"{self.base}/ok/api/v1", "model": "m"}
        out = Path(HOME) / "or.png"
        igk.run_openrouter(args(out=str(out), quality="high"), igk.load_config(), spec, None)
        self.assertEqual(Handler.requests[-1]["auth"], "Bearer or-test-key")
        self.assertTrue(out.exists())

    def test_unreadable_answers_are_api_errors(self):
        for mode in ("badjson", "html"):
            with self.assertRaises(igk.ApiError) as e:
                igk.http("POST", f"{self.base}/{mode}/x", {}, b"{}")
            self.assertIn("unreadable", e.exception.message)

    def test_bad_base64_is_an_api_error(self):
        with self.assertRaises(igk.ApiError):
            igk.collect_images({"data": [{"b64_json": "!!!x"}]})

    def test_stop_paid_pauses_only_paid_providers(self):
        cfg = {"limits": {"monthly_images": 1, "monthly_cost": 100, "stop_paid": True}}
        igk.CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        ts = igk.dt.datetime.now().isoformat(timespec="seconds")
        igk.LOG_FILE.write_text(json.dumps({"ts": ts, "provider": "grok", "type": "grok-build", "outputs": ["/x"]}) + "\n")
        try:
            igk.check_limits(cfg, {"type": "grok-build"})  # subscription keeps working
            with self.assertRaises(igk.LimitReached):
                igk.check_limits(cfg, {"type": "openai"})
            igk.check_limits({"limits": "bad"}, {"type": "openai"})  # odd config never crashes
        finally:
            igk.LOG_FILE.unlink()

    def test_catalog_providers_without_the_app(self):
        igk.CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        repo_catalog = Path(__file__).resolve().parent.parent / "catalog" / "providers.json"
        (igk.CONFIG_DIR / "catalog.json").write_text(repo_catalog.read_text())
        try:
            provs = igk.all_providers(igk.load_config())
            for name in ("openrouter", "recraft", "together", "fal"):
                self.assertIn(name, provs)
            self.assertEqual(provs["recraft"]["size_style"], "aspect")
            self.assertEqual(provs["openai"]["type"], "openai")  # built-ins win
        finally:
            (igk.CONFIG_DIR / "catalog.json").unlink()

    def test_version_compare_never_downgrades(self):
        self.assertLess(igk.version_tuple("v1.0.0"), igk.version_tuple("1.0.5"))
        self.assertLess(igk.version_tuple("1.0.9"), igk.version_tuple("1.0.10"))


if __name__ == "__main__":
    unittest.main()
