<p align="center">
  <img src="docs/icon.png" width="128" alt="ImageGenKit icon">
</p>

<h1 align="center">ImageGenKit</h1>

<p align="center">
  One Mac app and one command for AI images: use your own OpenAI, Grok, Gemini and other accounts,<br>
  see what you made and what it cost, and let Claude Code or Codex make images for you.
</p>

<p align="center">
  <a href="https://github.com/strics-at/imagegenkit/releases/latest"><b>Download for Mac</b></a> ·
  <a href="#install-with-your-ai-agent">Install with your AI agent</a> ·
  <a href="#command-line">Command line</a>
</p>

![ImageGenKit overview](docs/screenshots/overview.jpg)

## What it does

- **Generate** images by hand with any provider and every option it supports.
- **Gallery and history** of everything you or your agents generated, with prompts, sizes and files.
- **Usage and costs** per day, month, provider and project.
- **Providers**: add OpenAI, Google Gemini, xAI, OpenRouter, Recraft, Together AI or fal.ai with a step-by-step key guide, or log in to your Grok subscription. Keys stay in your macOS Keychain.
- **Use for**: pick which provider makes drafts, finals, edits and transparent PNGs. If one isn't set up, the next one in your list is used.
- **For AI agents**: installs the `imagegenkit` command and a skill for Claude Code and Codex, so your agent can make images that follow your settings.
- **Updates itself** from GitHub, and the provider list updates without a new app version.

| Gallery | Generate |
|---|---|
| ![Gallery](docs/screenshots/gallery.jpg) | ![Generate](docs/screenshots/generate.jpg) |

![Settings](docs/screenshots/settings.jpg)

## Install

### Download

1. Download **ImageGenKit.zip** from the [latest release](https://github.com/strics-at/imagegenkit/releases/latest) and move **ImageGenKit** to Applications.
2. Open it. Go to **Settings**, add a provider, and install the command line tool under **Agents**.

> If macOS says it can't check the app, open **System Settings › Privacy & Security** and click **Open Anyway**.

### Install with your AI agent

Paste this into Claude Code, Codex or another coding agent:

```text
Install ImageGenKit for me by following https://github.com/strics-at/imagegenkit/blob/main/docs/INSTALL-AGENT.md
```

### Command line only

```bash
curl -fsSL https://raw.githubusercontent.com/strics-at/imagegenkit/main/install.sh | bash
imagegenkit set-key openai
```

Requires macOS and Python 3.9+ (`xcode-select --install` provides it).

## Command line

```bash
imagegenkit draft "a cozy reading nook, warm light" -o nook.jpg   # quick, cheap
imagegenkit final "product photo of a red mug on marble" -o mug.png --aspect 4:5
imagegenkit edit "same mug on a wooden table" -i mug.png -o mug-wood.png
imagegenkit transparent "flat sticker of a smiling sun" -o sun.png
imagegenkit openai "..." --quality high       # one provider directly
imagegenkit providers                          # what's set up, order, task routing
imagegenkit check                              # live check of keys and logins
```

Saved paths go to stdout. Every run is logged to `~/.config/imagegenkit/log.jsonl`, which the app reads.

## Providers

| Provider | Sign in with | Status |
|---|---|---|
| OpenAI (GPT Image) | API key | Tested |
| Grok subscription | grok.com login via [Grok Build](https://x.ai/cli) | Tested |
| xAI API | API key | Beta |
| Google Gemini (Nano Banana) | API key | Beta |
| OpenRouter | API key | Beta |
| Recraft | API key | Beta |
| Together AI | API key | Beta |
| fal.ai | API key | Beta |
| Any OpenAI-compatible API | API key | Custom |

The provider list lives in [`catalog/providers.json`](catalog/providers.json). Pull requests that add or fix providers are welcome.

## Privacy

Everything stays on your Mac. API keys are stored in the macOS Keychain and are only sent to the provider you choose. The app talks to GitHub only to check for updates and to refresh the provider list.

## Build from source

```bash
brew install xcodegen
xcodegen generate
open ImageGenKit.xcodeproj
```

macOS 26+, Xcode 26+. The CLI (`cli/imagegenkit.py`) is plain Python with no dependencies.

## License

[MIT](LICENSE) © 2026 STRICS IT GmbH
