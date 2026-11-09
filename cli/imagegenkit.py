#!/usr/bin/env python3
"""imagegenkit - one command for AI image generation across providers (the CLI of the ImageGenKit Mac app).

  imagegenkit draft "PROMPT"         quick mockups and ideas   (provider from your settings)
  imagegenkit final "PROMPT"         final designs
  imagegenkit edit "PROMPT" -i x.png edit or refine an image
  imagegenkit transparent "PROMPT"   transparent PNG
  imagegenkit <provider> "PROMPT"    use one provider directly (openai, grok, xai, gemini, or your own)

Providers: OpenAI (API key), Grok (grok.com subscription via the Grok Build CLI), xAI API (API key),
Google Gemini (API key), and any OpenAI-compatible endpoint you add. API keys live in the macOS Keychain
("imagegenkit-<provider>"); env vars like OPENAI_API_KEY override them. Settings: ~/.config/imagegenkit/config.json,
best edited in the ImageGenKit app. Saved image paths go to stdout (one per line); everything else to stderr.
Stdlib only, Python 3.9+, macOS.
"""
import argparse
import base64
import datetime as dt
import getpass
import hashlib
import json
import math
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

VERSION = "1.0.5"
HOMEPAGE = "https://github.com/davidkrammer/imagegenkit"
GITHUB_REPO = "davidkrammer/imagegenkit"
CATALOG_URL = f"https://raw.githubusercontent.com/{GITHUB_REPO}/main/catalog/providers.json"

CONFIG_DIR = Path.home() / ".config" / "imagegenkit"
LEGACY_DIR = Path.home() / ".config" / "imagegen"  # used by the old `imagegen` CLI
CONFIG_FILE = CONFIG_DIR / "config.json"
LOG_FILE = CONFIG_DIR / "log.jsonl"
THUMB_DIR = CONFIG_DIR / "thumbs"  # 512 px previews, so the history keeps its pictures after files are deleted
THUMB_PX = 512
TIMEOUT = 600

TASKS = {
    "draft": "quick mockups, ideas and drafts",
    "final": "final designs and final-level mockups",
    "edit": "edit or refine existing images (needs -i)",
    "transparent": "transparent PNGs: logos, stickers, cut-outs",
}

# Built-in defaults. Override with `imagegenkit config set <key> <value>` or in the ImageGenKit app.
DEFAULTS = {
    "openai_model": "gpt-image-2.5-flare",        # fast everyday generation
    "openai_edit_model": "gpt-image-2.5-sunburst",  # used when reference images are given
    "xai_model": "grok-imagine-image",
    "gemini_model": "gemini-nano-banana-2.1",
    "resolution": "2K",
    "quality": "medium",
    "output_dir": "~/Pictures/ImageGenKit",
    "order": ["grok", "codex", "openai", "xai", "gemini"],  # fallback order when the task's provider isn't set up
    "tasks": {
        "draft": {"provider": "grok", "quality": "low", "resolution": "1K"},
        "final": {"provider": "openai"},
        "edit": {"provider": "openai"},
        "transparent": {"provider": "openai"},
    },
    "providers": {},  # your own OpenAI-compatible endpoints: {"name": {"base_url": ..., "model": ...}}
    "provider_defaults": {},  # per provider: {"openai": {"quality": "medium", "resolution": "2K", "model": ...}}
    "limits": {},  # {"monthly_cost": 20, "monthly_images": 500, "stop_paid": true}
}

# Price estimates in USD (same defaults as the app; config "prices" and the cached catalog override them).
DEFAULT_PRICES = {
    "openai": {"text_in": 5, "image_in": 8, "image_out": 30},
    "xai": {"per_image": 0.02}, "gemini": {"per_image": 0.0336}, "openrouter": {"per_image": 0.009},
    "recraft": {"per_image": 0.035}, "together": {"per_image": 0.0154}, "fal": {"per_image": 0.003},
}

BUILTIN_PROVIDERS = {
    "openai": {"type": "openai", "label": "OpenAI", "base_url": "https://api.openai.com/v1",
               "env": "OPENAI_API_KEY", "key_url": "https://platform.openai.com/api-keys"},
    "grok": {"type": "grok-build", "label": "Grok subscription", "key_url": "https://grok.com"},
    "codex": {"type": "codex-cli", "label": "Codex subscription", "key_url": "https://chatgpt.com/codex"},
    "xai": {"type": "xai", "label": "xAI API", "base_url": "https://api.x.ai/v1",
            "env": "XAI_API_KEY", "key_url": "https://console.x.ai"},
    "gemini": {"type": "gemini", "label": "Google Gemini", "base_url": "https://generativelanguage.googleapis.com/v1beta",
               "env": "GEMINI_API_KEY", "key_url": "https://aistudio.google.com/apikey"},
}
CAN_TRANSPARENT = {"openai"}  # provider types that return real alpha
SUBSCRIPTION_TYPES = {"grok-build", "codex-cli"}  # log in instead of an API key
RESERVED = set(TASKS) | {"usage", "update", "check", "models", "set-key", "delete-key", "config", "providers", "provider", "version",
                         "help", "log"}

MIME_BY_EXT = {
    ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp",
    ".gif": "image/gif", ".heic": "image/heic", ".heif": "image/heif",
}
EXT_BY_MIME = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp", "image/gif": ".gif"}
GROK_HOME = Path(os.environ.get("GROK_HOME", Path.home() / ".grok"))
GROK_WORKDIR = CONFIG_DIR / "grok-work"  # keeps these runs out of project session lists
CODEX_HOME = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
CODEX_WORKDIR = CONFIG_DIR / "codex-work"
GROK_ASPECTS = ["1:1", "16:9", "9:16", "3:2", "2:3"]
GROK_SYSTEM = ('You are an image generation runner. Do exactly what the user asks with the image tools, passing '
               'the prompt verbatim, then reply "done". Never call other tools. If a tool call is blocked or '
               'fails, reply with the error message instead.')
XAI_ASPECTS = ["1:1", "3:4", "4:3", "9:16", "16:9", "2:3", "3:2", "1:2", "2:1", "9:19.5", "19.5:9", "9:20",
               "20:9", "21:9", "5:2"]
GEMINI_API_REVISION = "2026-05-20"


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(f"HTTP {status}: {message}")
        self.status = status
        self.message = message


class Unavailable(Exception):
    """The provider isn't set up (no key, not logged in). Task commands fall back to the next one."""


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def die(msg, code=1):
    log(f"imagegenkit: {msg}")
    sys.exit(code)


# ---------- config ----------

def migrate_legacy():
    """Move ~/.config/imagegen (old CLI) to ~/.config/imagegenkit once, leaving a symlink so logged paths stay valid."""
    try:
        if LEGACY_DIR.is_dir() and not LEGACY_DIR.is_symlink() and not CONFIG_DIR.exists():
            LEGACY_DIR.rename(CONFIG_DIR)
            LEGACY_DIR.symlink_to(CONFIG_DIR)
    except OSError:
        pass


def read_user_config():
    if not CONFIG_FILE.exists():
        return {}
    try:
        data = json.loads(CONFIG_FILE.read_text())
    except ValueError as e:
        die(f"bad JSON in {CONFIG_FILE}: {e}")
    return data if isinstance(data, dict) else {}


def write_user_config(data):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = CONFIG_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    tmp.replace(CONFIG_FILE)


def load_config():
    cfg = json.loads(json.dumps(DEFAULTS))
    user = read_user_config()
    cfg["_user_keys"] = sorted(user)
    for k, v in user.items():
        if k == "tasks" and isinstance(v, dict):
            for task, preset in v.items():
                if isinstance(preset, dict):
                    cfg["tasks"].setdefault(task, {}).update(preset)
        else:
            cfg[k] = v
    return cfg


def enable_provider(name):
    """Add a provider to the fallback order (so task commands use it)."""
    data = read_user_config()
    order = data.get("order") or list(load_config().get("order") or [])
    if name not in order:
        order.append(name)
        data["order"] = order
        write_user_config(data)


def catalog_entry(name):
    """The provider's entry in the cached catalog (~/.config/imagegenkit/catalog.json), refreshed from GitHub."""
    try:
        for e in json.loads((CONFIG_DIR / "catalog.json").read_text()).get("providers", []):
            if e.get("id") == name:
                return e
    except (OSError, ValueError):
        pass
    return {}


def refresh_catalog():
    """Download the latest provider catalog (default models, prices, guides). Keeps the newer copy."""
    req = urllib.request.Request(CATALOG_URL, headers={"User-Agent": "imagegenkit"})
    with urllib.request.urlopen(req, timeout=8) as r:
        data = r.read()
    new = json.loads(data)
    if not new.get("providers"):
        return False
    path = CONFIG_DIR / "catalog.json"
    try:
        old = json.loads(path.read_text())
        if str(old.get("updated", "")) > str(new.get("updated", "")):
            return False
    except (OSError, ValueError):
        pass
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(data)
    tmp.replace(path)
    return True


def pref(cfg, spec, key, legacy=None):
    """A provider setting: your choice (provider_defaults.<name>.<key>, or an old global key you set),
    then the catalog's default (so new default models arrive without an update), then the built-in default."""
    d = (cfg.get("provider_defaults") or {}).get(spec["name"]) or {}
    if d.get(key) not in (None, ""):
        return d[key]
    if legacy and legacy in (cfg.get("_user_keys") or []):
        return cfg.get(legacy)
    if key in ("model", "edit_model"):
        e = catalog_entry(spec.get("catalog") or spec["name"])
        if e.get(key):
            return e[key]
    return cfg.get(legacy) if legacy else None


def all_providers(cfg):
    out = {}
    for name, spec in BUILTIN_PROVIDERS.items():
        out[name] = dict(spec, name=name, builtin=True)
    for name, spec in (cfg.get("providers") or {}).items():
        if name in out or name in RESERVED or not isinstance(spec, dict):
            continue
        s = dict(spec)
        s.setdefault("type", "openai-compatible")
        if s["type"] not in ("openai-compatible", "openrouter", "together", "fal"):
            s["type"] = "openai-compatible"
        s.setdefault("label", name)
        s.setdefault("env", re.sub(r"[^A-Z0-9]", "_", name.upper()) + "_API_KEY")
        s.update(name=name, builtin=False)
        out[name] = s
    return out


# ---------- keys & readiness ----------

def keychain_service(name):
    return f"imagegenkit-{name}"


def keychain_store(service, key, label):
    cmd = f'add-generic-password -U -a "{getpass.getuser()}" -s "{service}" -l "{label}" -w "{key}"\n'
    r = subprocess.run(["security", "-i"], input=cmd, capture_output=True, text=True)  # stdin keeps the key out of argv
    return r.returncode == 0


def keychain_read(service):
    try:
        r = subprocess.run(["security", "find-generic-password", "-s", service, "-w"], capture_output=True, text=True)
    except FileNotFoundError:
        return None
    return (r.stdout.strip() or None) if r.returncode == 0 else None


def key_for(spec):
    env = spec.get("env")
    if env and os.environ.get(env):
        return os.environ[env], f"env {env}"
    k = keychain_read(keychain_service(spec["name"]))
    if not k:  # key saved by the old `imagegen` CLI: copy it to the new name
        k = keychain_read(f"imagegen-{spec['name']}")
        if k:
            keychain_store(keychain_service(spec["name"]), k, f"ImageGenKit {spec['label']} API key")
    return (k, "Keychain") if k else (None, None)


def require_key(spec):
    k, _ = key_for(spec)
    if not k:
        raise Unavailable(f"no API key. Add one in ImageGenKit or run: imagegenkit set-key {spec['name']}")
    return k


def codex_bin():
    g = shutil.which("codex")
    if g:
        return g
    candidates = [Path("/opt/homebrew/bin/codex"), Path("/usr/local/bin/codex"), Path.home() / ".local/bin/codex"]
    candidates += sorted(Path.home().glob(".nvm/versions/node/*/bin/codex"), reverse=True)
    return next((str(c) for c in candidates if c.exists()), None)


def grok_bin():
    g = shutil.which("grok") or str(GROK_HOME / "bin" / "grok")
    return g if Path(g).exists() else None


def readiness(spec):
    """Fast local check (no network): (ready, reason)."""
    if spec["type"] == "grok-build":
        if not grok_bin():
            return False, "Grok Build CLI not installed"
        if not (GROK_HOME / "auth.json").exists():
            return False, "not logged in (run: grok login)"
        return True, "logged in"
    if spec["type"] == "codex-cli":
        if not codex_bin():
            return False, "Codex CLI not installed"
        if not (CODEX_HOME / "auth.json").exists():
            return False, "not logged in (run: codex login)"
        return True, "logged in"
    k, src = key_for(spec)
    if not k:
        return False, "no API key"
    if spec["type"] in ("openai-compatible", "openrouter", "together") and not spec.get("base_url"):
        return False, "no base_url"
    return True, f"key from {src}"


# ---------- http ----------

def http(method, url, headers=None, body=None, retries=2):
    for attempt in range(retries + 1):
        req = urllib.request.Request(url, data=body, method=method, headers=headers or {})
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            try:
                err = json.loads(raw).get("error", raw)
                msg = err.get("message", raw) if isinstance(err, dict) else str(err)
            except (ValueError, AttributeError):
                msg = raw[:2000]
            if e.code in (429, 500, 502, 503, 504) and attempt < retries:
                wait = 5 * (attempt + 1)
                log(f"  HTTP {e.code}, retrying in {wait}s: {msg[:200]}")
                time.sleep(wait)
                continue
            raise ApiError(e.code, msg)
        except urllib.error.URLError as e:
            if attempt < retries:
                time.sleep(3)
                continue
            raise ApiError(0, f"network error: {e.reason}")


def multipart(fields, files):
    boundary = uuid.uuid4().hex
    chunks = []
    for name, value in fields:
        chunks.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    for name, path in files:
        p = Path(path)
        chunks.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"; filename="{p.name}"\r\n'
            f'Content-Type: {mime_of(p)}\r\n\r\n'.encode() + p.read_bytes() + b"\r\n")
    chunks.append(f"--{boundary}--\r\n".encode())
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


# ---------- helpers ----------

def mime_of(path):
    return MIME_BY_EXT.get(Path(path).suffix.lower(), "application/octet-stream")


def sniff(data, fallback="image/png"):
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if data[:3] == b"\xff\xd8\xff":
        return "image/jpeg"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "image/gif"
    return fallback


def data_uri(path):
    return f"data:{mime_of(path)};base64,{base64.b64encode(Path(path).read_bytes()).decode()}"


def read_prompt(a):
    if a.prompt_file:
        text = Path(a.prompt_file).expanduser().read_text()
    elif a.prompt == "-":
        text = sys.stdin.read()
    else:
        text = a.prompt
    if not text or not text.strip():
        die("empty prompt (pass it as an argument, '-' for stdin, or --prompt-file)")
    return text.strip()


def check_refs(paths):
    out = []
    for p in paths or []:
        pp = Path(p).expanduser()
        if not pp.is_file():
            die(f"reference image not found: {p}")
        out.append(pp)
    return out


def parse_extra(pairs):
    extra = {}
    for kv in pairs or []:
        if "=" not in kv:
            die(f"--extra expects key=value, got {kv!r}")
        k, v = kv.split("=", 1)
        try:
            extra[k] = json.loads(v)
        except ValueError:
            extra[k] = v
    return extra


def note_unsupported(a, provider, names):
    for n in names:
        if getattr(a, n, None) not in (None, False, []):
            log(f"  note: {provider} ignores --{n.replace('_', '-')}")


def slug(text, words=7):
    s = re.sub(r"[^a-z0-9]+", "-", " ".join(text.lower().split()[:words])).strip("-")
    return s[:48].strip("-") or "image"


def unique(path, overwrite):
    if overwrite or not path.exists():
        return path
    i = 2
    while True:
        cand = path.with_name(f"{path.stem}-{i}{path.suffix}")
        if not cand.exists():
            return cand
        i += 1


def save_images(images, out, prompt, overwrite, cfg):
    """images: list of (bytes, mime). Returns saved paths."""
    now = dt.datetime.now()
    if out:
        target = Path(out).expanduser()
        if out.endswith("/") or target.is_dir():
            stem, user_ext = target / f"{now:%H%M%S}-{slug(prompt)}", None
        else:
            stem, user_ext = target.with_suffix(""), target.suffix.lower() or None
    else:
        base = Path(str(cfg.get("output_dir") or DEFAULTS["output_dir"])).expanduser()
        stem, user_ext = base / f"{now:%Y-%m-%d}" / f"{now:%H%M%S}-{slug(prompt)}", None
    saved = []
    for i, (data, mime) in enumerate(images):
        mime = sniff(data, mime or "image/png")
        if user_ext == ".png" and mime != "image/png":
            data, mime = convert_png(data, mime)
        ext = EXT_BY_MIME.get(mime, ".png")
        if user_ext and MIME_BY_EXT.get(user_ext) == mime:
            ext = user_ext  # keep .jpeg vs .jpg as requested
        elif user_ext and user_ext != ext:
            log(f"  note: provider returned {mime}; saving with {ext} instead of {user_ext}")
        name = stem if len(images) == 1 else stem.with_name(f"{stem.name}-{i + 1}")
        path = unique(name.with_name(name.name + ext), overwrite)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        saved.append(path)
    return saved


def convert_png(data, mime):
    """JPEG/WebP -> PNG via macOS sips, when -o asks for .png."""
    GROK_WORKDIR.mkdir(parents=True, exist_ok=True)
    src = GROK_WORKDIR / f"{uuid.uuid4().hex}{EXT_BY_MIME.get(mime, '.img')}"
    dst = src.with_suffix(".png")
    try:
        src.write_bytes(data)
        subprocess.run(["sips", "-s", "format", "png", str(src), "--out", str(dst)], capture_output=True)
        if dst.exists():
            return dst.read_bytes(), "image/png"
    finally:
        for f in (src, dst):
            if f.exists():
                f.unlink()
    return data, mime


def append_log(entry):
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        with LOG_FILE.open("a") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError as e:
        log(f"  (could not write log: {e})")


def thumb_key(ts, path):
    """Shared with the ImageGenKit app: sha1('<ts>|<absolute output path>')[:16]."""
    return hashlib.sha1(f"{ts}|{path}".encode()).hexdigest()[:16]


def archive_thumbs(ts, paths):
    """512 px previews in ~/.config/imagegenkit/thumbs/<YYYY-MM>/. Never fails the run."""
    thumbs = []
    for p in paths:
        try:
            alpha = "hasAlpha: yes" in subprocess.run(["sips", "-g", "hasAlpha", str(p)], capture_output=True,
                                                      text=True, timeout=30).stdout
            out = THUMB_DIR / ts[:7] / (thumb_key(ts, p) + (".png" if alpha else ".jpg"))
            out.parent.mkdir(parents=True, exist_ok=True)
            fmt = ["-s", "format", "png"] if alpha else ["-s", "format", "jpeg", "-s", "formatOptions", "72"]
            subprocess.run(["sips", "-Z", str(THUMB_PX)] + fmt + [str(p), "--out", str(out)],
                           capture_output=True, timeout=60)
            thumbs.append(str(out) if out.exists() else None)
        except (OSError, subprocess.SubprocessError):
            thumbs.append(None)
    return thumbs


def caller_info():
    """Who ran imagegenkit (agent, Claude account, T3 thread), for the usage log."""
    env = os.environ
    info = {}
    if env.get("CLAUDECODE") or env.get("CLAUDE_CODE_ENTRYPOINT"):
        m = re.search(r"\.claude-account(\d+)", env.get("CLAUDE_CONFIG_DIR", ""))
        info.update(agent="claude", account=int(m.group(1)) if m else 1)
    elif any(k.startswith("CODEX_") for k in env):
        info["agent"] = "codex"
    else:
        info["agent"] = "terminal" if sys.stdin.isatty() else "other"
    for key, var in (("entrypoint", "CLAUDE_CODE_ENTRYPOINT"), ("session", "CLAUDE_CODE_SESSION_ID"),
                     ("t3_thread", "T3CODE_THREAD_ID")):
        if env.get(var):
            info[key] = env[var]
    return info


def finish(a, cfg, spec, task, model, prompt, params, refs, images, usage, t0, extra=None):
    """Save images, print their paths, append the log entry."""
    if not images:
        die("the provider returned no image")
    paths = save_images(images, a.out, prompt, a.overwrite, cfg)
    secs = round(time.time() - t0, 1)
    log(f"  done in {secs}s, {len(paths)} image(s)")
    for p in paths:
        print(p, flush=True)
    ts = dt.datetime.now().isoformat(timespec="seconds")
    outputs = [Path(p).absolute() for p in paths]
    entry = {"ts": ts, "provider": spec["name"], "type": spec["type"], "model": model, "task": task,
             "prompt": prompt, "params": params, "refs": [str(r.absolute()) for r in refs],
             "outputs": [str(p) for p in outputs], "usage": usage, "seconds": secs, "cwd": os.getcwd()}
    entry.update(extra or {})
    entry.update(thumbs=archive_thumbs(ts, outputs), caller=caller_info(), v=VERSION)
    append_log(entry)


def parse_aspect(aspect):
    m = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*[:x/]\s*(\d+(?:\.\d+)?)\s*", aspect or "")
    if not m:
        die(f"bad --aspect {aspect!r}, expected like 16:9")
    return float(m.group(1)), float(m.group(2))


def nearest_aspect(aspect, allowed):
    rw, rh = parse_aspect(aspect)
    r = rw / rh
    return min(allowed, key=lambda s: abs(math.log(r / (lambda w, h: w / h)(*parse_aspect(s)))))


def image_aspect(path):
    """'W:H' of an image via macOS sips, or None."""
    try:
        out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
                             capture_output=True, text=True).stdout
        w = int(re.search(r"pixelWidth: (\d+)", out).group(1))
        h = int(re.search(r"pixelHeight: (\d+)", out).group(1))
    except (OSError, AttributeError, ValueError):
        return None
    return f"{w}:{h}" if 1 / 3 <= w / h <= 3 else None


def openai_size(aspect, resolution):
    """Map aspect + 1K/2K/4K to a GPT Image custom size (edges multiple of 16, <=3840, ratio 1:3..3:1)."""
    rw, rh = parse_aspect(aspect or "1:1")
    r = rw / rh
    if not (1 / 3 <= r <= 3):
        die(f"OpenAI only supports aspect ratios between 1:3 and 3:1 (got {aspect})")
    budget = {"1K": 1024 * 1024, "2K": 2560 * 1440, "4K": 8_294_400}.get((resolution or "1K").upper())
    if not budget:
        die("--resolution must be 1K, 2K or 4K")
    w, h = math.sqrt(budget * r), math.sqrt(budget / r)
    scale = min(1.0, 3840 / max(w, h))
    w, h = int(w * scale) // 16 * 16, int(h * scale) // 16 * 16
    return f"{w}x{h}"


def collect_images(resp, skip=()):
    """Base64 or URL images from an OpenAI-style `data` list."""
    images = []
    for item in resp.get("data", []) or []:
        if item.get("b64_json"):
            data = base64.b64decode(item["b64_json"])
        elif item.get("url"):
            with urllib.request.urlopen(item["url"], timeout=TIMEOUT) as r:
                data = r.read()
        else:
            continue
        if hashlib.sha1(data).hexdigest() not in skip:
            images.append((data, item.get("mime_type") or sniff(data)))
        if item.get("revised_prompt"):
            log(f"  revised prompt: {item['revised_prompt']}")
    return images


# ---------- usage & limits ----------

def prices_for(cfg, provider, model=None):
    """USD prices: built-in, then the catalog (per provider, then per model), then your own in config."""
    p = dict(DEFAULT_PRICES.get(provider, {}))
    entry = catalog_entry(provider)
    p.update(entry.get("prices") or {})
    if model:
        p.update((entry.get("model_prices") or {}).get(model) or {})
    p.update((cfg.get("prices") or {}).get(provider) or {})
    return p


def estimate_cost(entry, cfg):
    """Estimated USD of one logged run (0 for subscriptions). Mirrors ConfigStore.cost in the app."""
    if entry.get("type") in SUBSCRIPTION_TYPES or entry.get("provider") == "grok":
        return 0.0
    u = entry.get("usage") or {}
    if isinstance(u.get("cost_usd"), (int, float)):
        return float(u["cost_usd"])
    if isinstance(u.get("cost_in_usd_ticks"), (int, float)):
        return u["cost_in_usd_ticks"] / 1e10
    provider = entry.get("provider", "")
    p = prices_for(cfg, provider, entry.get("model"))
    if ("input_tokens" in u or "output_tokens" in u) and not p.get("image_out") and entry.get("type") == "openai":
        p = prices_for(cfg, "openai", entry.get("model"))
    if ("input_tokens" in u or "output_tokens" in u) and p.get("image_out"):
        d = u.get("input_tokens_details") or {}
        text = d.get("text_tokens") or 0
        image = d.get("image_tokens") if d.get("image_tokens") is not None else (u.get("input_tokens", 0) - text)
        return (text * p.get("text_in", 0) + image * p.get("image_in", 0) + u.get("output_tokens", 0) * p["image_out"]) / 1e6
    if p.get("per_image"):
        return p["per_image"] * len(entry.get("outputs") or [])
    return 0.0


def month_usage(cfg):
    """This calendar month: (estimated spend, images, runs)."""
    month = dt.datetime.now().strftime("%Y-%m")
    cost = images = runs = 0
    try:
        with LOG_FILE.open() as f:
            for line in f:
                if f'"ts": "{month}' not in line:
                    continue
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                cost += estimate_cost(e, cfg)
                images += len(e.get("outputs") or [])
                runs += 1
    except OSError:
        pass
    return cost, images, runs


def check_limits(cfg, spec):
    """With 'stop_paid', refuse paid providers past the spend limit and everything past the image limit."""
    lim = cfg.get("limits") or {}
    if not lim.get("stop_paid"):
        return
    cost_limit, image_limit = lim.get("monthly_cost"), lim.get("monthly_images")
    if not cost_limit and not image_limit:
        return
    cost, images, _ = month_usage(cfg)
    if image_limit and images >= image_limit:
        raise Unavailable(f"monthly image limit reached ({images} of {image_limit}). Change it in ImageGenKit › Settings › Limits")
    if cost_limit and spec["type"] not in SUBSCRIPTION_TYPES and cost >= cost_limit:
        raise Unavailable(f"monthly spend limit reached (${cost:.2f} of ${cost_limit:.2f}). Subscriptions still work; "
                          "change it in ImageGenKit › Settings › Limits")


# ---------- providers ----------

def run_openai(a, cfg, spec, task):
    """OpenAI Images API, also used for any OpenAI-compatible endpoint."""
    key = "<dry-run>" if a.dry_run else require_key(spec)
    prompt = read_prompt(a)
    refs = check_refs(a.image)
    mask = check_refs([a.mask])[0] if a.mask else None
    official = spec["type"] == "openai"
    if official:
        model = a.model or (pref(cfg, spec, "edit_model", "openai_edit_model") if refs else pref(cfg, spec, "model", "openai_model"))
    else:
        model = a.model or pref(cfg, spec, "model") or (
            spec.get("edit_model") if refs and spec.get("edit_model") else spec.get("model"))
        if not model:
            die(f"no model set for {spec['name']} (imagegenkit provider add {spec['name']} ... --model <id>)")
    fmt = a.format
    if not fmt and a.out and Path(a.out).suffix.lower() in (".png", ".jpg", ".jpeg", ".webp"):
        fmt = {".jpg": "jpeg"}.get(Path(a.out).suffix.lower(), Path(a.out).suffix.lower()[1:])
    fmt = fmt or pref(cfg, spec, "format")
    resolution = a.resolution or pref(cfg, spec, "resolution", "resolution" if official else None)
    params = {}
    if a.n > 1:
        params["n"] = a.n
    if a.size:
        params["size"] = a.size
    elif official:
        aspect = a.aspect
        if not aspect and refs:  # keep the input image's shape instead of forcing square
            aspect = image_aspect(refs[0])
        params["size"] = openai_size(aspect, resolution) if aspect or not refs else "auto"
    elif a.aspect and spec.get("size_style") == "aspect":  # e.g. Recraft takes "16:9"
        w, h = parse_aspect(a.aspect)
        params["size"] = f"{w:g}:{h:g}"
    elif a.aspect:
        params["size"] = openai_size(a.aspect, resolution or "1K")
    quality = a.quality or pref(cfg, spec, "quality", "quality" if official else None)
    background = a.background or pref(cfg, spec, "background")
    for k, v in (("quality", quality), ("background", background), ("output_format", fmt if official else None),
                 ("output_compression", a.compression), ("moderation", a.moderation)):
        if v is not None:
            params[k] = v
    params.update(parse_extra(a.extra))

    log(f"{spec['label']} {model} | {'edit with ' + str(len(refs)) + ' ref(s)' if refs else 'generate'} | {params or 'defaults'}")
    if a.dry_run:
        return log(json.dumps({"url": spec["base_url"], "model": model, "prompt": prompt, **params}, indent=2))
    t0 = time.time()
    base = spec["base_url"].rstrip("/")
    headers = {"Authorization": f"Bearer {key}"}
    if refs:
        fields = [("model", model), ("prompt", prompt)] + [
            (k, json.dumps(v) if isinstance(v, (dict, list, bool)) else v) for k, v in params.items()]
        files = [("image[]", p) for p in refs] + ([("mask", mask)] if mask else [])
        body, ctype = multipart(fields, files)
        resp = http("POST", f"{base}/images/edits", {**headers, "Content-Type": ctype}, body)
    else:
        body = json.dumps({"model": model, "prompt": prompt, **params}).encode()
        resp = http("POST", f"{base}/images/generations", {**headers, "Content-Type": "application/json"}, body)
    finish(a, cfg, spec, task, model, prompt, params, refs, collect_images(resp), resp.get("usage"), t0)


def run_xai(a, cfg, spec, task):
    """xAI API (Grok Imagine models), billed per image to your xAI account."""
    key = "<dry-run>" if a.dry_run else require_key(spec)
    prompt = read_prompt(a)
    refs = check_refs(a.image)
    note_unsupported(a, spec["label"], ["quality", "background", "size", "mask", "compression", "moderation"])
    model = a.model or pref(cfg, spec, "model", "xai_model")
    params = {}
    if a.n > 1:
        params["n"] = a.n
    if a.aspect:
        params["aspect_ratio"] = nearest_aspect(a.aspect, XAI_ASPECTS)
    resolution = a.resolution or pref(cfg, spec, "resolution")
    if resolution:  # API default is 1k, the cheapest
        params["resolution"] = "1k" if resolution.upper() == "1K" else "2k"
    params.update(parse_extra(a.extra))
    body = {"model": model, "prompt": prompt, "response_format": "b64_json", **params}
    if refs:
        imgs = [{"url": data_uri(p), "type": "image_url"} for p in refs]
        body["image" if len(imgs) == 1 else "images"] = imgs[0] if len(imgs) == 1 else imgs
    log(f"{spec['label']} {model} | {'edit with ' + str(len(refs)) + ' ref(s)' if refs else 'generate'} | {params or 'defaults'}")
    if a.dry_run:
        return log(json.dumps({k: (v if k not in ("image", "images") else "<data uri>") for k, v in body.items()}, indent=2))
    t0 = time.time()
    path = "/images/edits" if refs else "/images/generations"
    resp = http("POST", spec["base_url"].rstrip("/") + path,
                {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}, json.dumps(body).encode())
    finish(a, cfg, spec, task, model, prompt, params, refs, collect_images(resp), resp.get("usage"), t0)


def run_gemini(a, cfg, spec, task):
    """Google Gemini image models (Nano Banana) through the Interactions API."""
    key = "<dry-run>" if a.dry_run else require_key(spec)
    prompt = read_prompt(a)
    refs = check_refs(a.image)
    note_unsupported(a, spec["label"], ["quality", "background", "size", "mask", "compression", "moderation"])
    model = a.model or pref(cfg, spec, "model", "gemini_model")
    fmt = {"type": "image"}
    if a.aspect:
        w, h = parse_aspect(a.aspect)
        fmt["aspect_ratio"] = f"{w:g}:{h:g}"
    resolution = a.resolution or pref(cfg, spec, "resolution")
    if resolution:
        fmt["image_size"] = resolution.upper()
    inputs = [{"type": "text", "text": prompt}] + [
        {"type": "image", "mime_type": mime_of(p), "data": base64.b64encode(p.read_bytes()).decode()} for p in refs]
    body = {"model": model, "input": inputs, "response_format": fmt}
    body.update(parse_extra(a.extra))
    params = {k: v for k, v in fmt.items() if k != "type"}
    if a.n > 1:
        params["n"] = a.n
    log(f"{spec['label']} {model} | {'edit with ' + str(len(refs)) + ' ref(s)' if refs else 'generate'} | {params or 'defaults'}")
    if a.dry_run:
        return log(json.dumps({**body, "input": [i if i["type"] == "text" else "<image>" for i in inputs]}, indent=2))
    t0 = time.time()
    headers = {"x-goog-api-key": key, "Content-Type": "application/json", "Api-Revision": GEMINI_API_REVISION}
    skip = {hashlib.sha1(p.read_bytes()).hexdigest() for p in refs}
    images, usage = [], None
    for _ in range(a.n):  # one image per request
        resp = http("POST", spec["base_url"].rstrip("/") + "/interactions", headers, json.dumps(body).encode())
        images += find_inline_images(resp, skip)
        usage = resp.get("usage") or resp.get("usageMetadata") or resp.get("usage_metadata") or usage
        if not images:
            die(f"no image in response: {json.dumps(resp)[:1500]}")
    finish(a, cfg, spec, task, model, prompt, params, refs, images, usage, t0)


def find_inline_images(obj, skip=()):
    """Every base64 image block in a response, whatever the nesting (deduplicated)."""
    found, seen = [], set(skip)

    def walk(o):
        if isinstance(o, dict):
            data = mime = None
            if o.get("type") == "image" and isinstance(o.get("data"), str):
                data, mime = o["data"], o.get("mime_type") or o.get("mimeType")
            for k in ("inlineData", "inline_data"):
                if isinstance(o.get(k), dict) and isinstance(o[k].get("data"), str):
                    data, mime = o[k]["data"], o[k].get("mimeType") or o[k].get("mime_type")
            if data:
                raw = base64.b64decode(data)
                digest = hashlib.sha1(raw).hexdigest()
                if digest not in seen:
                    seen.add(digest)
                    found.append((raw, mime or sniff(raw)))
                return
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)

    walk(obj)
    return found


def run_grok(a, cfg, spec, task):
    """Grok Imagine through the logged-in Grok Build CLI (grok.com subscription, no API key)."""
    prompt = read_prompt(a)
    refs = check_refs(a.image)
    note_unsupported(a, spec["label"], ["quality", "background", "size", "mask", "compression", "moderation",
                                        "resolution", "format", "extra"])
    g = grok_bin()
    if not g:
        raise Unavailable("Grok Build CLI not installed (curl -fsSL https://x.ai/cli/install.sh | bash)")
    aspect = None
    if a.aspect:
        aspect = nearest_aspect(a.aspect, GROK_ASPECTS)
        if aspect != a.aspect.strip():
            log(f"  note: Grok only supports {', '.join(GROK_ASPECTS)}; using {aspect}")
    tool = "image_edit" if refs else "image_gen"
    call = f"Call the {tool} tool exactly once" if a.n == 1 else f"Call the {tool} tool exactly {a.n} times (separate calls, same arguments)"
    if refs:
        call += f" with image {json.dumps([str(r.resolve()) for r in refs])}"
    if aspect:
        call += f' with aspect_ratio "{aspect}"'
    instruction = (f"{call}, using exactly the text between the <prompt> tags as the prompt.\n\n"
                   f"<prompt>\n{prompt}\n</prompt>\n\nThen reply with just: done")
    sid = str(uuid.uuid4())
    cmd = [g, "-p", instruction, "--tools", "image_gen,image_edit", "--system-prompt-override", GROK_SYSTEM,
           "--disable-web-search", "--no-subagents", "--no-plan", "--max-turns", str(2 + a.n),
           "--always-approve", "--session-id", sid, "--cwd", str(GROK_WORKDIR)]
    if a.model:
        cmd += ["-m", a.model]
    log(f"Grok {tool} | {len(refs)} ref(s) | aspect {aspect or 'auto'} | n={a.n}")
    if a.dry_run:
        return log(" ".join(shlex.quote(c) for c in cmd))
    GROK_WORKDIR.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT, cwd=GROK_WORKDIR)
    except subprocess.TimeoutExpired:
        die(f"Grok timed out after {TIMEOUT}s")
    files = sorted(GROK_HOME.glob(f"sessions/*/{sid}/images/*"), key=lambda f: f.stat().st_mtime)
    if not files:
        said = (r.stdout.strip() + " " + r.stderr.strip()).strip()[-1000:]
        if r.returncode and re.search(r"log ?in|auth|unauthori", said, re.I):
            raise Unavailable(f"not logged in (run: grok login). Grok said: {said}")
        die(f"Grok returned no image (exit {r.returncode}). Grok said: {said or '(nothing)'}")
    images = [(f.read_bytes(), MIME_BY_EXT.get(f.suffix.lower(), "image/jpeg")) for f in files]
    log(f"  grok session {sid}")
    usage = None
    try:
        u = subprocess.run([g, "usage", sid], capture_output=True, text=True, timeout=30)
        sess = json.loads(u.stdout).get("session", {})
        usage = {k: sess.get(k) for k in ("inputTokens", "outputTokens", "cachedReadTokens", "costUsdTicks",
                                         "primaryModelId")}
    except (subprocess.SubprocessError, ValueError, OSError):
        pass
    finish(a, cfg, spec, task, a.model or "default", prompt, {"tool": tool, "aspect": aspect, "n": a.n}, refs,
           images, usage, t0, {"grok_session": sid})


def run_openrouter(a, cfg, spec, task):
    """OpenRouter Image API: one key for many image models (POST /images, base64 out)."""
    key = "<dry-run>" if a.dry_run else require_key(spec)
    prompt = read_prompt(a)
    refs = check_refs(a.image)
    note_unsupported(a, spec["label"], ["background", "size", "mask", "compression", "moderation"])
    model = a.model or pref(cfg, spec, "model") or spec.get("model")
    if not model:
        die(f"no model set for {spec['name']}")
    params = {}
    if a.n > 1:
        params["n"] = a.n
    if a.aspect:
        w, h = parse_aspect(a.aspect)
        params["aspect_ratio"] = f"{w:g}:{h:g}"
    for name, val in (("resolution", (a.resolution or pref(cfg, spec, "resolution") or "").upper() or None),
                      ("quality", a.quality or pref(cfg, spec, "quality")),
                      ("output_format", a.format or pref(cfg, spec, "format"))):
        if val:
            params[name] = val
    params.update(parse_extra(a.extra))
    body = {"model": model, "prompt": prompt, **params}
    if refs:
        body["input_references"] = [{"type": "image_url", "image_url": {"url": data_uri(p)}} for p in refs]
    log(f"{spec['label']} {model} | {'edit with ' + str(len(refs)) + ' ref(s)' if refs else 'generate'} | {params or 'defaults'}")
    if a.dry_run:
        return log(json.dumps({**body, **({"input_references": "<data uris>"} if refs else {})}, indent=2))
    t0 = time.time()
    resp = http("POST", spec["base_url"].rstrip("/") + "/images",
                {"Authorization": f"Bearer {key}", "Content-Type": "application/json",
                 "X-Title": "ImageGenKit", "HTTP-Referer": HOMEPAGE}, json.dumps(body).encode())
    usage = resp.get("usage")
    if isinstance(usage, dict) and isinstance(usage.get("cost"), (int, float)):
        usage = dict(usage, cost_usd=usage["cost"])
    finish(a, cfg, spec, task, model, prompt, params, refs, collect_images(resp), usage, t0)


def run_together(a, cfg, spec, task):
    """Together AI images API (FLUX models): width/height instead of size, base64 out."""
    key = "<dry-run>" if a.dry_run else require_key(spec)
    prompt = read_prompt(a)
    refs = check_refs(a.image)
    note_unsupported(a, spec["label"], ["quality", "background", "mask", "compression", "moderation"])
    model = a.model or pref(cfg, spec, "model") or spec.get("model")
    resolution = a.resolution or pref(cfg, spec, "resolution")
    params = {}
    if a.n > 1:
        params["n"] = a.n
    size = a.size if a.size and "x" in a.size else (openai_size(a.aspect, resolution or "1K") if a.aspect or resolution else None)
    if size:
        w, h = size.split("x")
        params.update(width=int(w), height=int(h))
    if a.format in ("png", "jpeg"):
        params["output_format"] = a.format
    params.update(parse_extra(a.extra))
    body = {"model": model, "prompt": prompt, "response_format": "base64", **params}
    if refs:
        body["image_url"] = data_uri(refs[0])
    log(f"{spec['label']} {model} | {'edit' if refs else 'generate'} | {params or 'defaults'}")
    if a.dry_run:
        return log(json.dumps({k: (v if k != "image_url" else "<data uri>") for k, v in body.items()}, indent=2))
    t0 = time.time()
    resp = http("POST", spec["base_url"].rstrip("/") + "/images/generations",
                {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}, json.dumps(body).encode())
    finish(a, cfg, spec, task, model, prompt, params, refs, collect_images(resp), resp.get("usage"), t0)


def run_fal(a, cfg, spec, task):
    """fal.ai synchronous endpoint (fal.run/<model>). Generation only."""
    key = "<dry-run>" if a.dry_run else require_key(spec)
    prompt = read_prompt(a)
    if a.image:
        die(f"{spec['label']}: reference images aren't supported yet; use another provider for edits")
    note_unsupported(a, spec["label"], ["quality", "background", "mask", "compression", "moderation"])
    model = a.model or pref(cfg, spec, "model") or spec.get("model")
    resolution = a.resolution or pref(cfg, spec, "resolution")
    params = {"num_images": a.n} if a.n > 1 else {}
    size = a.size if a.size and "x" in a.size else (openai_size(a.aspect, resolution or "1K") if a.aspect or resolution else None)
    if size:
        w, h = size.split("x")
        params["image_size"] = {"width": int(w), "height": int(h)}
    if a.format in ("png", "jpeg"):
        params["output_format"] = a.format
    params.update(parse_extra(a.extra))
    body = {"prompt": prompt, "sync_mode": True, **params}
    base = (spec.get("base_url") or "https://fal.run").rstrip("/")
    log(f"{spec['label']} {model} | generate | {params or 'defaults'}")
    if a.dry_run:
        return log(json.dumps({"url": f"{base}/{model}", **body}, indent=2))
    t0 = time.time()
    resp = http("POST", f"{base}/{model}", {"Authorization": f"Key {key}", "Content-Type": "application/json"},
                json.dumps(body).encode())
    images = []
    for item in resp.get("images", []) or []:
        url = item.get("url", "")
        if url.startswith("data:"):
            data = base64.b64decode(url.split(",", 1)[1])
        elif url:
            with urllib.request.urlopen(url, timeout=TIMEOUT) as r:
                data = r.read()
        else:
            continue
        images.append((data, item.get("content_type") or sniff(data)))
    finish(a, cfg, spec, task, model, prompt, params, [], images, None, t0)


def run_codex(a, cfg, spec, task):
    """Images through the logged-in Codex CLI (ChatGPT plan, no API key): its built-in image tool."""
    prompt = read_prompt(a)
    refs = check_refs(a.image)
    note_unsupported(a, spec["label"], ["size", "mask", "compression", "moderation", "format", "extra", "model"])
    c = codex_bin()
    if not c:
        raise Unavailable("Codex CLI not installed (npm install -g @openai/codex)")
    call = "Use your image generation tool exactly once" if a.n == 1 else \
        f"Use your image generation tool exactly {a.n} times (separate calls, same prompt)"
    if refs:
        call += ", editing or combining the attached image(s)"
    hints = []
    if a.aspect:
        w, h = parse_aspect(a.aspect)
        hints.append(f"aspect ratio {w:g}:{h:g}")
    quality = a.quality or pref(cfg, spec, "quality")
    if quality and quality != "auto":
        hints.append(f"{quality} quality")
    if (a.background or pref(cfg, spec, "background")) == "transparent":
        hints.append("transparent background")
    if hints:
        call += " with " + ", ".join(hints)
    instruction = (f"{call}, passing exactly the text between the <prompt> tags as the prompt. Do not run shell "
                   f"commands or edit files.\n\n<prompt>\n{prompt}\n</prompt>\n\nThen reply with just: done")
    cmd = [c, "exec", "--json", "--skip-git-repo-check", "-C", str(CODEX_WORKDIR), "-s", "read-only",
           "-c", "model_reasoning_effort=low"]
    for r in refs:
        cmd += ["-i", str(r.resolve())]
    cmd.append(instruction)
    log(f"Codex image_gen | {len(refs)} ref(s) | {', '.join(hints) or 'auto'} | n={a.n}")
    if a.dry_run:
        return log(" ".join(shlex.quote(x) for x in cmd))
    CODEX_WORKDIR.mkdir(parents=True, exist_ok=True)
    gen_dir = CODEX_HOME / "generated_images"
    t0 = time.time()
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT, cwd=CODEX_WORKDIR,
                           stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        die(f"Codex timed out after {TIMEOUT}s")
    thread, failure, paths = None, None, []
    for line in r.stdout.splitlines():
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if ev.get("type") == "thread.started":
            thread = ev.get("thread_id")
        elif ev.get("type") == "turn.failed":
            failure = (ev.get("error") or {}).get("message", "turn failed")
        paths += re.findall(r'[^"\s]*generated_images/[^"\s]+\.(?:png|jpe?g|webp)', line)
    files = [Path(p) for p in dict.fromkeys(paths) if Path(p).exists()]
    if not files and thread:
        files = sorted((gen_dir / thread).glob("*"), key=lambda f: f.stat().st_mtime) if (gen_dir / thread).is_dir() else []
    if not files:  # last resort: anything Codex saved during this run
        files = sorted((f for f in gen_dir.glob("*/*") if f.stat().st_mtime >= t0 - 1),
                       key=lambda f: f.stat().st_mtime)
    files = [f for f in files if f.suffix.lower() in MIME_BY_EXT][: max(a.n, 1) * 2]
    if not files:
        said = failure or (r.stderr.strip()[-600:] or "(nothing)")
        if re.search(r"401|unauthori|log ?in|refresh token|sign in", said, re.I):
            raise Unavailable(f"not logged in (run: codex login). Codex said: {said}")
        die(f"Codex returned no image (exit {r.returncode}). Codex said: {said}")
    images = [(f.read_bytes(), MIME_BY_EXT.get(f.suffix.lower(), "image/png")) for f in files]
    finish(a, cfg, spec, task, "gpt-image (Codex)", prompt, {"tool": "image_gen", "aspect": a.aspect, "n": a.n},
           refs, images, None, t0, {"codex_thread": thread})


RUNNERS = {"openai": run_openai, "openai-compatible": run_openai, "xai": run_xai, "gemini": run_gemini,
           "grok-build": run_grok, "codex-cli": run_codex, "openrouter": run_openrouter, "together": run_together,
           "fal": run_fal}


def run_provider(a, cfg):
    spec = all_providers(cfg)[a.cmd]
    try:
        if not a.dry_run:
            check_limits(cfg, spec)
        RUNNERS[spec["type"]](a, cfg, spec, None)
    except Unavailable as e:
        die(f"{spec['name']}: {e}")


def run_task(a, cfg):
    """draft / final / edit / transparent: the provider from your settings, then the fallback order."""
    task = a.cmd
    preset = cfg["tasks"].get(task) or {}
    provs = all_providers(cfg)
    if task == "edit" and not a.image:
        die("edit needs at least one reference image: -i image.png")
    first = a.provider or preset.get("provider")
    candidates = []
    for name in [first] + list(cfg.get("order") or []):
        if name and name in provs and name not in candidates:
            candidates.append(name)
    if a.provider:
        candidates = [a.provider] if a.provider in provs else die(f"unknown provider {a.provider}")
    skipped = []
    for name in candidates:
        spec = provs[name]
        if task == "transparent" and spec["type"] not in CAN_TRANSPARENT:
            skipped.append(f"{name}: no transparency")
            continue
        ok, why = readiness(spec)
        if not ok:
            skipped.append(f"{name}: {why}")
            continue
        if spec["type"] in ("openai", "openai-compatible", "xai", "gemini"):
            if not a.quality and preset.get("quality") and spec["type"] == "openai":
                a.quality = preset["quality"]
            if not a.resolution and preset.get("resolution"):
                a.resolution = preset["resolution"]
        if task == "transparent":
            a.background = "transparent"
            if not a.format and not (a.out and Path(a.out).suffix):
                a.format = "png"
        try:
            if not a.dry_run:
                check_limits(cfg, spec)
        except Unavailable as e:
            skipped.append(f"{name}: {e}")
            continue
        log(f"{task} -> {name}" + (f" (skipped {'; '.join(skipped)})" if skipped else ""))
        try:
            return RUNNERS[spec["type"]](a, cfg, spec, task)
        except Unavailable as e:
            skipped.append(f"{name}: {e}")
        except ApiError as e:
            if e.status not in (401, 403):
                raise
            skipped.append(f"{name}: {e}")
    die(f"no provider ready for '{task}' ({'; '.join(skipped) or 'none configured'}). "
        "Set one up in the ImageGenKit app, or: imagegenkit set-key openai")


# ---------- utility commands ----------

def check_provider(spec, cfg):
    """(status, message) with a live call where possible. status: ok | missing | error."""
    ok, why = readiness(spec)
    if not ok:
        return "missing", why
    if spec["type"] == "codex-cli":
        try:
            out = subprocess.run([codex_bin(), "login", "status"], capture_output=True, text=True, timeout=60,
                                 stdin=subprocess.DEVNULL)
            text = (out.stdout + out.stderr).strip()
        except subprocess.SubprocessError:
            text = ""
        return ("ok", text.splitlines()[0]) if "logged in" in text.lower() else ("error", "not logged in (run: codex login)")
    if spec["type"] == "grok-build":
        try:
            out = subprocess.run([grok_bin(), "models"], capture_output=True, text=True, timeout=60).stdout
        except subprocess.SubprocessError:
            out = ""
        m = re.search(r"logged in with ([^\s.]+(?:\.[a-z]+)?)", out)
        return ("ok", f"logged in with {m.group(1)}") if m else ("error", "not logged in (run: grok login)")
    key, src = key_for(spec)
    base = (spec.get("base_url") or "").rstrip("/")
    try:
        if spec["type"] == "fal":
            return "ok", f"key from {src} (checked on first run)"
        if spec["type"] == "openrouter":
            resp = http("GET", f"{base}/key", {"Authorization": f"Bearer {key}"}, retries=0)
            d = resp.get("data", {})
            left = d.get("limit_remaining")
            return "ok", f"key from {src}" + (f"; ${left:.2f} left" if isinstance(left, (int, float)) else "")
        if spec["type"] == "gemini":
            resp = http("GET", f"{base}/models?pageSize=200", {"x-goog-api-key": key}, retries=0)
            names = [m.get("name", "") for m in resp.get("models", [])]
            return "ok", f"key from {src}; {sum('image' in n or 'banana' in n for n in names)} image models"
        if spec["type"] == "xai":
            resp = http("GET", f"{base}/image-generation-models", {"Authorization": f"Bearer {key}"}, retries=0)
            ids = [m.get("id") for m in resp.get("models", resp.get("data", []))]
            return "ok", f"key from {src}; models: {', '.join(i for i in ids if i) or '?'}"
        resp = http("GET", f"{base}/models", {"Authorization": f"Bearer {key}"}, retries=0)
        ids = [m.get("id", "") for m in resp.get("data", [])]
        if spec["type"] == "openai":
            image_ids = [i for i in ids if re.search(r"image|dall-e", i)]
            missing = [m for m in (cfg["openai_model"], cfg["openai_edit_model"]) if m not in image_ids]
            return "ok", f"key from {src}; {len(image_ids)} image models" + (
                f"; not available: {', '.join(missing)}" if missing else "")
        return "ok", f"key from {src}; {len(ids)} models"
    except ApiError as e:
        if e.status in (401, 403):
            return "error", f"key rejected ({e.message[:120]})"
        if e.status in (404, 405) and spec["type"] not in ("openai", "xai", "gemini"):
            return "ok", f"key from {src} (endpoint has no /models list)"
        return "error", str(e)[:200]


def cmd_check(a, cfg):
    provs = all_providers(cfg)
    names = [a.provider] if a.provider else list(provs)
    results = []
    for n in names:
        if n not in provs:
            die(f"unknown provider {n}")
        status, msg = check_provider(provs[n], cfg)
        results.append({"provider": n, "label": provs[n]["label"], "status": status, "message": msg})
    if a.json:
        print(json.dumps(results, indent=2))
    else:
        for r in results:
            print(f"{r['label']:<18} {r['status'].upper():<8} {r['message']}")
    sys.exit(0 if any(r["status"] == "ok" for r in results) else 1)


def cmd_providers(a, cfg):
    provs = all_providers(cfg)
    rows = []
    for name, spec in provs.items():
        ready, why = readiness(spec)
        rows.append({"name": name, "label": spec["label"], "type": spec["type"], "builtin": spec["builtin"],
                     "needs_key": spec["type"] not in SUBSCRIPTION_TYPES, "keychain": keychain_service(name)
                     if spec["type"] not in SUBSCRIPTION_TYPES else None, "env": spec.get("env"), "ready": ready,
                     "status": why, "base_url": spec.get("base_url"), "model": spec.get("model"),
                     "key_url": spec.get("key_url")})
    if a.json:
        print(json.dumps({"providers": rows, "order": cfg.get("order"), "tasks": cfg.get("tasks")}, indent=2))
        return
    for r in rows:
        print(f"{r['name']:<12} {r['label']:<18} {'ready' if r['ready'] else '-':<6} {r['status']}")
    print("\norder: " + " > ".join(cfg.get("order") or []))
    for t, p in (cfg.get("tasks") or {}).items():
        print(f"{t:<12} -> {p.get('provider')}")


def cmd_provider(a, cfg):
    data = read_user_config()
    custom = data.setdefault("providers", {})
    if a.action == "add":
        if not re.fullmatch(r"[a-z][a-z0-9-]{1,30}", a.name or ""):
            die("provider name: lowercase letters, digits and dashes, 2-31 chars")
        if a.name in BUILTIN_PROVIDERS or a.name in RESERVED:
            die(f"'{a.name}' is reserved")
        if not a.base_url or not a.model:
            die("usage: imagegenkit provider add <name> --base-url https://.../v1 --model <id> [--edit-model <id>] [--label X]")
        spec = {"type": "openai-compatible", "label": a.label or a.name, "base_url": a.base_url.rstrip("/"),
                "model": a.model}
        if a.edit_model:
            spec["edit_model"] = a.edit_model
        custom[a.name] = spec
        order = data.setdefault("order", list(DEFAULTS["order"]))
        if a.name not in order:
            order.append(a.name)
        write_user_config(data)
        print(f"Added {a.name}. Store its key with: imagegenkit set-key {a.name}")
    elif a.action == "remove":
        if custom.pop(a.name, None) is None:
            die(f"no custom provider named {a.name}")
        if a.name in data.get("order", []):
            data["order"].remove(a.name)
        write_user_config(data)
        print(f"Removed {a.name} (its Keychain key stays until: imagegenkit delete-key {a.name})")


def cmd_set_key(a, cfg):
    provs = all_providers(cfg)
    spec = provs.get(a.provider)
    if not spec:
        die(f"unknown provider {a.provider} (see: imagegenkit providers)")
    if spec["type"] in SUBSCRIPTION_TYPES:
        die(f"{spec['label']} has no key. Log in with: {'grok login' if spec['type'] == 'grok-build' else 'codex login'}")
    if a.clipboard:
        key = subprocess.run(["pbpaste"], capture_output=True, text=True).stdout.strip()
        if not key:
            die("clipboard is empty")
    elif a.stdin or not sys.stdin.isatty():
        key = sys.stdin.read().strip()
    else:
        key = getpass.getpass(f"Paste {spec['label']} API key (input hidden): ").strip()
    if not key or re.search(r'[\s"\\]', key):
        die("that does not look like an API key")
    service = keychain_service(a.provider)
    if not keychain_store(service, key, f"ImageGenKit {spec['label']} API key") or keychain_read(service) != key:
        die("could not store the key in the Keychain")
    enable_provider(a.provider)
    if a.clipboard:
        subprocess.run(["pbcopy"], input="", text=True)
    print(f"Saved in Keychain as '{service}'.")
    if spec.get("env") and os.environ.get(spec["env"]):
        print(f"note: env {spec['env']} is set and takes precedence.")
    status, msg = check_provider(spec, load_config())
    print(f"Check: {status.upper()} {msg}")


def cmd_delete_key(a, cfg):
    r = subprocess.run(["security", "delete-generic-password", "-s", keychain_service(a.provider)],
                       capture_output=True, text=True)
    print("Deleted." if r.returncode == 0 else f"No key stored for {a.provider}.")


def cmd_models(a, cfg):
    spec = all_providers(cfg).get(a.provider or "openai")
    if not spec or spec["type"] in ("grok-build", "codex-cli", "gemini"):
        die("models works for openai, xai and OpenAI-compatible providers")
    key = require_key(spec)
    if spec["type"] == "xai":
        resp = http("GET", spec["base_url"] + "/image-generation-models", {"Authorization": f"Bearer {key}"}, retries=0)
        ids = [m.get("id") for m in resp.get("models", resp.get("data", []))]
    else:
        resp = http("GET", spec["base_url"] + "/models", {"Authorization": f"Bearer {key}"}, retries=0)
        ids = [m["id"] for m in resp.get("data", []) if spec["type"] != "openai" or re.search(r"image|dall-e", m["id"])]
    for i in sorted(i for i in ids if i):
        print(i)


def cmd_usage(a, cfg):
    cost, images, runs = month_usage(cfg)
    lim = cfg.get("limits") or {}
    out = {"month": dt.datetime.now().strftime("%Y-%m"), "cost": round(cost, 4), "images": images, "runs": runs,
           "limits": lim}
    if a.json:
        print(json.dumps(out, indent=2))
        return
    print(f"{out['month']}: ${cost:.2f} estimated · {images} images · {runs} runs")
    if lim.get("monthly_cost"):
        print(f"spend limit  ${lim['monthly_cost']:.2f}  ({cost / lim['monthly_cost']:.0%} used)")
    if lim.get("monthly_images"):
        print(f"image limit  {lim['monthly_images']}  ({images / lim['monthly_images']:.0%} used)")
    if lim and not lim.get("stop_paid"):
        print("limits warn only (stop_paid is off)")


def version_tuple(v):
    return tuple(int(x) if x.isdigit() else 0 for x in re.split(r"[.\-]", str(v).lstrip("vV")))


def self_update(force_check=True):
    """Install the CLI (and ImageGenKit-managed skills) from the latest GitHub release. Returns a short message."""
    ua = {"User-Agent": "imagegenkit", "Accept": "application/vnd.github+json"}
    req = urllib.request.Request(f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest", headers=ua)
    with urllib.request.urlopen(req, timeout=8) as r:
        tag = json.loads(r.read())["tag_name"]

    def fetch(path):
        url = f"https://raw.githubusercontent.com/{GITHUB_REPO}/{tag}/{path}"
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "imagegenkit"}), timeout=20) as r:
            return r.read()

    code = fetch("cli/imagegenkit.py")
    m = re.search(rb'^VERSION = "([^"]+)"', code, re.M)
    if not m:
        return f"latest release {tag} has no CLI version"
    remote = m.group(1).decode()
    if version_tuple(remote) <= version_tuple(VERSION):
        return f"up to date ({VERSION})"
    compile(code, "imagegenkit.py", "exec")  # never install something that doesn't parse
    me = Path(os.path.realpath(__file__))
    tmp = me.with_name(me.name + ".new")
    tmp.write_bytes(code)
    tmp.chmod(0o755)
    tmp.replace(me)
    try:
        skill = fetch("skill/SKILL.md")
        for home in (Path.home() / ".claude", Path.home() / ".codex"):
            target = home / "skills" / "imagegenkit" / "SKILL.md"
            if target.exists() and "managed-by: ImageGenKit" in target.read_text(errors="ignore"):
                target.write_bytes(skill)
    except (OSError, urllib.error.URLError):
        pass
    return f"updated {VERSION} -> {remote}"


def auto_update(cfg):
    """Once a day, after a normal run: quietly update from the latest release (config auto_update: false turns it off)."""
    if cfg.get("auto_update") is False or os.environ.get("IMAGEGENKIT_NO_UPDATE"):
        return
    stamp = CONFIG_DIR / ".update-check"
    try:
        if stamp.exists() and time.time() - stamp.stat().st_mtime < 86400:
            return
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        stamp.touch()
        try:
            refresh_catalog()
        except Exception:
            pass
        msg = self_update()
        if msg.startswith("updated"):
            log(f"imagegenkit: {msg}")
    except Exception:  # offline, rate limited, private repo, read-only install: try again tomorrow
        pass


def cmd_update(a, cfg):
    try:
        if refresh_catalog():
            print("Provider list updated.")
    except (urllib.error.URLError, OSError, ValueError):
        pass
    try:
        print(self_update())
    except urllib.error.HTTPError as e:
        die(f"couldn't check GitHub (HTTP {e.code}). {HOMEPAGE}/releases")
    except (urllib.error.URLError, OSError) as e:
        die(f"couldn't update: {e}")


def set_dotted(data, dotted, value):
    keys = dotted.split(".")
    node = data
    for k in keys[:-1]:
        node = node.setdefault(k, {})
        if not isinstance(node, dict):
            die(f"{dotted}: {k} is not an object")
    if value is None:
        node.pop(keys[-1], None)
    else:
        node[keys[-1]] = value


def cmd_config(a, cfg):
    if a.action in ("set", "unset"):
        if not a.key or (a.action == "set" and a.value is None):
            die("usage: imagegenkit config set <key> <value>   (dotted keys work: tasks.draft.provider openai)")
        data = read_user_config()
        value = None
        if a.action == "set":
            try:
                value = json.loads(a.value)
            except ValueError:
                value = a.value
        set_dotted(data, a.key, value)
        write_user_config(data)
    elif a.action == "reset":
        if CONFIG_FILE.exists():
            CONFIG_FILE.unlink()
    print(json.dumps({k: v for k, v in load_config().items() if not k.startswith("_")}, indent=2, ensure_ascii=False))


# ---------- CLI ----------

def add_gen_args(p, task=False):
    p.add_argument("prompt", nargs="?", help="prompt text, or '-' to read stdin")
    p.add_argument("-f", "--prompt-file", help="read the prompt from a file")
    p.add_argument("-o", "--out", help="output file, or a directory ending in / (default ~/Pictures/ImageGenKit/<date>/)")
    p.add_argument("-i", "--image", action="append", help="reference image to edit or combine (repeatable)")
    p.add_argument("-n", type=int, default=1, help="number of images (default 1)")
    p.add_argument("-m", "--model", help="model id")
    p.add_argument("--aspect", help="aspect ratio, e.g. 1:1 3:2 16:9 9:16")
    p.add_argument("--resolution", help="1K | 2K | 4K")
    p.add_argument("--size", help="exact WIDTHxHEIGHT or auto (OpenAI-style providers)")
    p.add_argument("--quality", help="low | medium | high | auto (OpenAI)")
    p.add_argument("--background", help="transparent | opaque | auto (OpenAI)")
    p.add_argument("--format", help="png | jpeg | webp")
    p.add_argument("--compression", type=int, help="0-100 for jpeg/webp (OpenAI)")
    p.add_argument("--moderation", help="auto | low (OpenAI)")
    p.add_argument("--mask", help="PNG mask with alpha, transparent = area to edit (OpenAI)")
    p.add_argument("--extra", action="append", help="pass-through API param key=value (JSON values ok)")
    p.add_argument("--overwrite", action="store_true", help="overwrite existing output instead of adding -2, -3")
    p.add_argument("--dry-run", action="store_true", help="show the request without calling the provider")
    if task:
        p.add_argument("-p", "--provider", help="use this provider instead of the one in your settings")


def main():
    migrate_legacy()
    cfg = load_config()
    provs = all_providers(cfg)
    ap = argparse.ArgumentParser(
        prog="imagegenkit", formatter_class=argparse.RawDescriptionHelpFormatter,
        description=f"One command for AI image generation across providers (ImageGenKit {VERSION}).",
        epilog="examples:\n"
               "  imagegenkit draft \"creator filming a laser engraver, top-down\" --aspect 9:16 -o idea.jpg\n"
               "  imagegenkit final \"product photo of a red mug on marble\" -o mug.png --aspect 4:5\n"
               "  imagegenkit edit \"same mug, on a wooden table\" -i mug.png -o mug-wood.png\n"
               "  imagegenkit transparent \"flat sticker of a smiling sun\" -o sun.png\n"
               "  imagegenkit openai \"...\" --quality high     imagegenkit grok \"...\"\n"
               "  imagegenkit providers | check | set-key <provider> | config set tasks.draft.provider openai\n"
               f"\n{HOMEPAGE}")
    ap.add_argument("--version", action="version", version=f"imagegenkit {VERSION}")
    sub = ap.add_subparsers(dest="cmd", required=True, metavar="command")

    for task, desc in TASKS.items():
        preset = cfg["tasks"].get(task) or {}
        p = sub.add_parser(task, help=f"{desc} (now: {preset.get('provider', '?')})", description=desc)
        add_gen_args(p, task=True)
        p.set_defaults(fn=run_task)
    for name, spec in provs.items():
        p = sub.add_parser(name, help=f"{spec['label']} directly", description=f"{spec['label']} ({spec['type']})")
        add_gen_args(p)
        p.set_defaults(fn=run_provider)

    p = sub.add_parser("providers", help="list providers, readiness, fallback order and task routing")
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_providers)
    p = sub.add_parser("check", help="verify keys and logins with a live call (never prints keys)")
    p.add_argument("provider", nargs="?")
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_check)
    p = sub.add_parser("set-key", help="store a provider's API key in the macOS Keychain")
    p.add_argument("provider")
    p.add_argument("--clipboard", action="store_true", help="read the key from the clipboard, then clear it")
    p.add_argument("--stdin", action="store_true", help="read the key from stdin")
    p.set_defaults(fn=cmd_set_key)
    p = sub.add_parser("delete-key", help="remove a provider's API key from the Keychain")
    p.add_argument("provider")
    p.set_defaults(fn=cmd_delete_key)
    p = sub.add_parser("provider", help="add or remove your own OpenAI-compatible provider")
    p.add_argument("action", choices=["add", "remove"])
    p.add_argument("name")
    p.add_argument("--base-url")
    p.add_argument("--model")
    p.add_argument("--edit-model")
    p.add_argument("--label")
    p.set_defaults(fn=cmd_provider)
    p = sub.add_parser("models", help="image models a provider's key can use (openai, xai, custom)")
    p.add_argument("provider", nargs="?")
    p.set_defaults(fn=cmd_models)
    p = sub.add_parser("config", help="show or change settings (~/.config/imagegenkit/config.json)")
    p.add_argument("action", nargs="?", choices=["show", "set", "unset", "reset"], default="show")
    p.add_argument("key", nargs="?")
    p.add_argument("value", nargs="?")
    p.set_defaults(fn=cmd_config)
    p = sub.add_parser("usage", help="this month's estimated spend, images and limits")
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_usage)
    p = sub.add_parser("update", help="update imagegenkit (and its skills) from the latest GitHub release")
    p.set_defaults(fn=cmd_update)
    p = sub.add_parser("version", help="print the version")
    p.set_defaults(fn=lambda a, c: print(VERSION))

    a = ap.parse_args()
    if getattr(a, "n", 1) < 1:
        die("-n must be >= 1")
    try:
        a.fn(a, cfg)
        if a.fn in (run_task, run_provider) and not getattr(a, "dry_run", False):
            auto_update(cfg)  # after the images are saved and printed
    except ApiError as e:
        die(str(e))
    except Unavailable as e:
        die(str(e))
    except KeyboardInterrupt:
        die("interrupted", 130)


if __name__ == "__main__":
    main()
