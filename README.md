# dotfiles

My personal macOS setup: Neovim config and a Ghostty theme, kept in sync
across machines. Nothing fancy — just what I actually use day to day, tuned
as I go.

## What's here

- **`nvim/init.lua`** — LSP support for Go, Zig, Rust, and Python
  (basedpyright + ruff), fuzzy completion, [fzf-lua](https://github.com/ibhagwan/fzf-lua)
  for file/text search, Treesitter, system-clipboard-synced yank/paste, and
  a keymap to pop open [Claude Code](https://claude.com/claude-code) in a
  terminal split pre-filled with the current file.
- **`ghostty/config`** — TokyoNight Night theme, plus split-divider styling.
- **`install.sh`** — symlinks both configs into place, clones the nvim
  plugins as native packages, and installs `gopls`/Ghostty/`fzf`/`fd`/`ripgrep`
  via Homebrew. Safe to re-run.

## Setup

```sh
git clone https://github.com/glenpi/dotfiles.git
cd dotfiles
./install.sh
```

Requires [Homebrew](https://brew.sh) and the [Go toolchain](https://go.dev/dl/)
to already be installed. `zls` (Zig) and `rust-analyzer` (Rust) aren't
installed by the script — see the comments above their `lspconfig` setup in
`init.lua` for how to get each one.
