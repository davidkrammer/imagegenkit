# Install ImageGenKit (instructions for AI agents)

You are helping a user install ImageGenKit on their Mac or Windows PC. Follow these steps in order. Keep the user informed in short sentences.

**Never ask the user to paste an API key into the chat, and never print or store a key yourself.** Keys are entered in the ImageGenKit app (Settings › Providers) or by the user running `imagegenkit set-key <provider>` in their own Terminal.

## On Windows

Use these steps instead of the macOS ones below. Run them in PowerShell.

1. Check Python: `py -3 --version` (or `python --version`) must print 3.9 or newer. If not, ask the user before running
   `winget install Python.Python.3.13`.
2. Install the command, the app and the skills:

   ```powershell
   irm https://raw.githubusercontent.com/davidkrammer/imagegenkit/main/install.ps1 | iex
   ```

   It adds `%USERPROFILE%\.local\bin` to the user's PATH; new terminals pick it up.
3. Ask the user to open **ImageGenKit** from the Start menu (or run `imagegenkit app`) and connect a provider in
   Settings › Providers. Keys go into the Windows Credential Manager there, never into the chat.
4. Check with `imagegenkit providers` and try `imagegenkit draft "a cozy reading nook, warm light" -o "$HOME\Desktop\nook.jpg"`.

## 1. Install the app (macOS)

```bash
cd "$(mktemp -d)"
url=$(curl -fsSL https://api.github.com/repos/davidkrammer/imagegenkit/releases/latest \
  | grep -o '"browser_download_url": *"[^"]*ImageGenKit[^"]*\.zip"' | head -1 | cut -d'"' -f4)
curl -fL "$url" -o ImageGenKit.zip
ditto -x -k ImageGenKit.zip .
dest=/Applications; [ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
rm -rf "$dest/ImageGenKit.app" && mv ImageGenKit.app "$dest/"
open "$dest/ImageGenKit.app"
```

## 2. Install the command line tool and skills

Run the installer (it puts `imagegenkit` in `~/.local/bin` and installs the skill for Claude Code and Codex if they're present):

```bash
curl -fsSL https://raw.githubusercontent.com/davidkrammer/imagegenkit/main/install.sh | bash
```

If it says `~/.local/bin` isn't on the PATH, ask the user before changing their shell config, then add `export PATH="$HOME/.local/bin:$PATH"` to `~/.zshrc`.

## 3. Connect a provider

When ImageGenKit opens for the first time, its welcome tour finds what's already set up and connects it. Otherwise ask the user to open **ImageGenKit › Settings › Providers › Add Provider**:

- **ChatGPT or Grok subscription:** no key needed. The app installs and logs in to Codex or Grok Build for them (the login opens in the browser).
- **API key:** the app walks them through getting a key (OpenAI, Google Gemini, xAI, OpenRouter, Recraft, Together AI, fal.ai).

## 4. Check

```bash
imagegenkit providers
```

At least one provider should say `ready`. Then try a draft:

```bash
imagegenkit draft "a cozy reading nook, warm light" -o ~/Desktop/nook.jpg
```

Tell the user where the image was saved and that every image shows up in the ImageGenKit gallery.
