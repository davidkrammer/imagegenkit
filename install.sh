#!/bin/bash
# ImageGenKit command line installer (no app needed).
#   curl -fsSL https://raw.githubusercontent.com/davidkrammer/imagegenkit/main/install.sh | bash
# Installs `imagegenkit` to ~/.local/bin and the agent skill for Claude Code and Codex (if installed).
set -euo pipefail

RAW="${IMAGEGENKIT_RAW:-https://raw.githubusercontent.com/davidkrammer/imagegenkit/main}"
SHARE="$HOME/.local/share/imagegenkit"
BIN="$HOME/.local/bin"

if ! /usr/bin/env python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null; then
  echo "imagegenkit needs Python 3.9+. Install Apple's Command Line Tools first:  xcode-select --install"
  exit 1
fi

fetch() {
  curl -fsSL "$1" -o "$2" || { rm -f "$2"; echo "Couldn't download $1. Check your internet connection and try again."; exit 1; }
}

mkdir -p "$SHARE" "$BIN"
fetch "$RAW/cli/imagegenkit.py" "$SHARE/imagegenkit.py.tmp"
mv "$SHARE/imagegenkit.py.tmp" "$SHARE/imagegenkit.py"
chmod 755 "$SHARE/imagegenkit.py"
ln -sf "$SHARE/imagegenkit.py" "$BIN/imagegenkit"

for dir in "$HOME/.claude" "$HOME/.codex"; do
  if [ -d "$dir" ]; then
    mkdir -p "$dir/skills/imagegenkit"
    fetch "$RAW/skill/SKILL.md" "$dir/skills/imagegenkit/SKILL.md"
    echo "Skill installed for $(basename "$dir" | tr -d .)"
  fi
done

echo "Installed $("$BIN/imagegenkit" --version)"

# Provider list (models, prices, OpenRouter/Recraft/...); the command refreshes it once a day.
# After the first run above, which moves an old ~/.config/imagegen into place.
CONF="$HOME/.config/imagegenkit"
if [ ! -f "$CONF/catalog.json" ]; then
  mkdir -p "$CONF"
  curl -fsSL "$RAW/catalog/providers.json" -o "$CONF/catalog.json.tmp" && mv "$CONF/catalog.json.tmp" "$CONF/catalog.json" || rm -f "$CONF/catalog.json.tmp"
fi
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo
     echo "Add ~/.local/bin to your PATH:"
     echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc" ;;
esac
echo
echo "Next: add a provider key, e.g.  imagegenkit set-key openai   (or use the ImageGenKit app)"
