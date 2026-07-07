#!/usr/bin/env bash
# Bootstraps this dotfiles repo onto a fresh macOS laptop: symlinks nvim and
# Ghostty configs, clones the nvim plugins as native packages, and installs
# gopls. Safe to re-run.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

link() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "Backing up existing $dest -> $dest.bak"
    mv "$dest" "$dest.bak"
  fi
  ln -sfn "$src" "$dest"
  echo "Linked $dest -> $src"
}

link "$DOTFILES_DIR/nvim/init.lua" "$HOME/.config/nvim/init.lua"
link "$DOTFILES_DIR/ghostty/config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"

clone_plugin() {
  local name="$1" url="$2"
  local dest="$HOME/.local/share/nvim/site/pack/$name/opt/$name"
  if [ -d "$dest" ]; then
    echo "$name already present, skipping clone"
  else
    git clone --depth 1 "$url" "$dest"
  fi
}

clone_plugin nvim-treesitter https://github.com/nvim-treesitter/nvim-treesitter.git
clone_plugin nvim-lspconfig https://github.com/neovim/nvim-lspconfig.git
clone_plugin render-markdown.nvim https://github.com/MeanderingProgrammer/render-markdown.nvim.git
clone_plugin fzf-lua https://github.com/ibhagwan/fzf-lua.git

if ! command -v go >/dev/null 2>&1; then
  echo "go not found. Install the Go toolchain first (https://go.dev/dl/), then re-run this script."
  exit 1
fi
go install golang.org/x/tools/gopls@latest
echo "gopls installed to $(go env GOPATH)/bin -- make sure that's on your PATH"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Install it first (https://brew.sh), then run: brew install --cask ghostty && brew install fzf fd ripgrep"
else
  if ! brew list --cask ghostty >/dev/null 2>&1; then
    echo "Installing Ghostty via Homebrew..."
    brew install --cask ghostty
  else
    echo "Ghostty already installed"
  fi
  # fzf-lua (nvim <leader>ff / <leader>fg) shells out to these for listing
  # files and grepping contents.
  brew install fzf fd ripgrep
fi

echo "Done."
