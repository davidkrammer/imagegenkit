#!/bin/bash
# ImageGenKit command line installer (no app needed).
#   curl -fsSL https://raw.githubusercontent.com/strics-at/imagegenkit/main/install.sh | bash
# Installs `imagegenkit` to ~/.local/bin and the agent skill for Claude Code and Codex (if installed).
set -euo pipefail

RAW="https://raw.githubusercontent.com/strics-at/imagegenkit/main"
SHARE="$HOME/.local/share/imagegenkit"
BIN="$HOME/.local/bin"

if ! /usr/bin/env python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null; then
  echo "imagegenkit needs Python 3.9+. Install Apple's Command Line Tools first:  xcode-select --install"
  exit 1
fi

mkdir -p "$SHARE" "$BIN"
curl -fsSL "$RAW/cli/imagegenkit.py" -o "$SHARE/imagegenkit.py.tmp"
mv "$SHARE/imagegenkit.py.tmp" "$SHARE/imagegenkit.py"
chmod 755 "$SHARE/imagegenkit.py"
ln -sf "$SHARE/imagegenkit.py" "$BIN/imagegenkit"

for dir in "$HOME/.claude" "$HOME/.codex"; do
  if [ -d "$dir" ]; then
    mkdir -p "$dir/skills/imagegenkit"
    curl -fsSL "$RAW/skill/SKILL.md" -o "$dir/skills/imagegenkit/SKILL.md"
    echo "Skill installed for $(basename "$dir" | tr -d .)"
  fi
done

echo "Installed $("$BIN/imagegenkit" --version)"
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo
     echo "Add ~/.local/bin to your PATH:"
     echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc" ;;
esac
echo
echo "Next: add a provider key, e.g.  imagegenkit set-key openai   (or use the ImageGenKit app)"
