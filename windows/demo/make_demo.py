"""Builds a throwaway Windows profile with a month of ImageGenKit history, for screenshots and UI tests.

    python make_demo.py <profile-dir>

Run the app with USERPROFILE (and APPDATA) pointing at that folder. Only demo images and made-up prompts: never a
real log. Providers look set up: OpenAI and Gemini through fake keys in environment variables (set by the caller),
Grok and Codex through stand-in login files, and "On this PC" through a registry with two small stand-in models.
"""
import datetime as dt
import json
import random
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
profile = Path(sys.argv[1]).resolve()
conf = profile / ".config" / "imagegenkit"
pics = profile / "Pictures" / "ImageGenKit"
conf.mkdir(parents=True, exist_ok=True)

SUBJECTS = [
    ("demo-01.jpg", "demo-02.jpg", "A sage green ceramic mug on a light oak table, soft morning window light, product photo"),
    ("demo-03.jpg", "demo-04.jpg", "Cozy reading nook with a cream armchair, olive tree and warm lamp light at dusk"),
    ("demo-05.jpg", "demo-06.jpg", "Layered blue mountains above a calm lake at sunrise, soft pastel sky, minimal poster"),
    ("demo-07.jpg", "demo-08.jpg", "Cute robot sticker waving, pastel colors, white outline, transparent background"),
    ("demo-09.jpg", "demo-10.jpg", "Steaming bowl of tonkotsu ramen with egg and nori, dark wooden table, moody light"),
]
PROJECTS = ["Coffee Shop", "Travel Blog", "Sticker Pack", "Cookbook", "Home Decor"]
RUNS = [  # provider, type, model, cost model
    ("grok", "grok-build", "grok-imagine", None),
    ("grok", "grok-build", "grok-imagine", None),
    ("openai", "openai", "gpt-image-2.5-flare", "openai"),
    ("local", "local", "FLUX.2 klein 4B", None),
    ("gemini", "gemini", "gemini-nano-banana-2.1", None),
    ("codex", "codex-cli", "gpt-image (Codex)", None),
]

for f in HERE.glob("images/*.jpg"):
    (pics / "Demo").mkdir(parents=True, exist_ok=True)
    shutil.copy(f, pics / "Demo" / f.name)

rnd = random.Random(11)
now = dt.datetime.now().replace(second=0, microsecond=0)
lines = []
for i in range(58):
    day = now - dt.timedelta(days=rnd.choice([0, 0, 1, 1, 2, 3, 4, 5, 7, 8, 9, 11, 12, 14, 16, 18, 20, 22, 25, 27]),
                             hours=rnd.randint(0, 9), minutes=rnd.randint(0, 59))
    a, b, prompt = SUBJECTS[i % len(SUBJECTS)]
    provider, kind, model, cost = RUNS[rnd.randrange(len(RUNS))]
    n = rnd.choice([1, 1, 2, 4]) if provider != "openai" else rnd.choice([1, 2])
    outs = [str(pics / "Demo" / (a if k % 2 == 0 else b)) for k in range(n)]
    entry = {
        "ts": day.isoformat(timespec="seconds"), "provider": provider, "type": kind, "model": model,
        "task": rnd.choice(["draft", "draft", "final", "edit"]), "prompt": prompt,
        "params": {"size": rnd.choice(["1024x1024", "1536x1024", "1024x1536"]), "quality": "medium", "n": n},
        "refs": [], "outputs": outs, "thumbs": outs, "seconds": round(rnd.uniform(12, 70), 1),
        "cwd": str(profile / "Projects" / PROJECTS[i % len(PROJECTS)]),
        "caller": {"agent": rnd.choice(["claude", "codex", "", ""])},
    }
    if cost == "openai":
        entry["usage"] = {"input_tokens": 300, "input_tokens_details": {"text_tokens": 300, "image_tokens": 0},
                          "output_tokens": 1600 * n}
    if provider == "local":
        entry["params"]["seed"] = rnd.randint(1, 2 ** 31)
        entry["params"]["model_id"] = "flux2-klein-4b"
    lines.append(entry)
lines.sort(key=lambda e: e["ts"])
(conf / "log.jsonl").write_text("".join(json.dumps(e) + "\n" for e in lines), encoding="utf-8")

(conf / "config.json").write_text(json.dumps({
    "order": ["grok", "openai", "local", "gemini", "codex"],
    "tasks": {"draft": {"provider": "grok"}, "final": {"provider": "openai"}, "edit": {"provider": "openai"},
              "transparent": {"provider": "openai"}},
    "output_dir": str(pics),
    "limits": {"monthly_cost": 20, "stop_paid": True},
}, indent=2), encoding="utf-8")

# Grok Build and Codex "logged in" (stand-ins: the screenshots never run them)
(profile / ".grok" / "bin").mkdir(parents=True, exist_ok=True)
(profile / ".grok" / "bin" / "grok.cmd").write_text("@echo grok stand-in\r\n")
(profile / ".grok" / "auth.json").write_text("{}")
npm = profile / "AppData" / "Roaming" / "npm"
npm.mkdir(parents=True, exist_ok=True)
(npm / "codex.cmd").write_text("@echo codex stand-in\r\n")
(profile / ".codex").mkdir(exist_ok=True)
(profile / ".codex" / "auth.json").write_text("{}")
(profile / ".claude").mkdir(exist_ok=True)

# "On this PC": an engine stand-in and two models whose files exist
share = profile / ".local" / "share" / "imagegenkit"
engine = share / "engine" / "demo"
engine.mkdir(parents=True, exist_ok=True)
(engine / "sd-cli.exe").write_bytes(b"MZ")
models = share / "models"
files = {}
for rel in ["leejet/FLUX.2-klein-4B-GGUF/flux-2-klein-4b-Q4_0.gguf", "unsloth/Qwen3-4B-GGUF/Qwen3-4B-Q4_K_M.gguf",
            "Comfy-Org/flux2-klein-4B/split_files/vae/flux2-vae.safetensors",
            "leejet/Z-Image-Turbo-GGUF/z_image_turbo-Q4_K.gguf",
            "unsloth/Qwen3-4B-Instruct-2507-GGUF/Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
            "Comfy-Org/z_image_turbo/split_files/vae/ae.safetensors"]:
    (models / rel).parent.mkdir(parents=True, exist_ok=True)
    (models / rel).write_bytes(b"demo")
(share / "local-models.json").write_text(json.dumps({
    "engine": {"version": "demo", "binary": "sd-cli.exe", "dir": "demo", "backend": "vulkan"},
    "models": [
        {"id": "flux2-klein-4b", "name": "FLUX.2 klein 4B", "recipe": "flux2-klein-4b", "edit": True, "bytes": 5293871164,
         "license": "Apache 2.0", "files": {"diffusion_model": "leejet/FLUX.2-klein-4B-GGUF/flux-2-klein-4b-Q4_0.gguf",
                                            "llm": "unsloth/Qwen3-4B-GGUF/Qwen3-4B-Q4_K_M.gguf",
                                            "vae": "Comfy-Org/flux2-klein-4B/split_files/vae/flux2-vae.safetensors"}},
        {"id": "z-image-turbo", "name": "Z-Image Turbo", "recipe": "z-image-turbo", "edit": False, "bytes": 6703000000,
         "license": "Apache 2.0", "files": {"diffusion_model": "leejet/Z-Image-Turbo-GGUF/z_image_turbo-Q4_K.gguf",
                                            "llm": "unsloth/Qwen3-4B-Instruct-2507-GGUF/Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
                                            "vae": "Comfy-Org/z_image_turbo/split_files/vae/ae.safetensors"}},
    ]}, indent=1), encoding="utf-8")
print(f"demo profile: {profile} ({len(lines)} runs)")
