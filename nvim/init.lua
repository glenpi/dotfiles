-- Warm built-in colorscheme, deliberately distinct from the cool blue/purple
-- Ghostty theme so it's obvious at a glance when you're inside nvim.
vim.cmd.colorscheme("retrobox")

-- Show line numbers. Set relativenumber too for relative numbering.
vim.opt.number = true
-- vim.opt.relativenumber = true

-- Route yank/delete/paste through the system clipboard (via pbcopy/pbpaste
-- on macOS) instead of only vim's internal unnamed register, so `y` in nvim
-- can be pasted elsewhere with Cmd-V and vice versa.
vim.opt.clipboard = "unnamedplus"

-- Let netrw (:Explore) change the actual working directory as you browse,
-- instead of only updating its own internal listing -- so shell commands
-- run from nvim (:!) and relative paths follow wherever you've navigated to.
vim.g.netrw_keepdir = 0

-- Show diagnostic messages as wrapped lines below the code line, instead of
-- clipped virtual_text at the end of the line.
vim.diagnostic.config({ virtual_text = false, virtual_lines = { only_current_line = true } })

-- Fuzzy-match native completion (Neovim 0.11+) so typing e.g. "wrst" can
-- still surface "WriteString" instead of only matching by strict prefix.
-- No "noselect": the first entry is pre-selected so <CR> (mapped below to
-- <C-y> when the popup is visible) accepts it directly. "noinsert" keeps
-- that selection from being written into the buffer as you type/navigate --
-- without it, the highlighted candidate's text is inserted live, so any key
-- that dismisses the popup (not just <CR>) leaves it behind.
vim.opt.completeopt = { "menuone", "noinsert", "popup", "fuzzy" }

-- <CR> confirms the highlighted completion entry when the popup menu is
-- open; otherwise it's a normal newline. Native completion doesn't bind
-- Enter to "select" on its own, only <C-y>.
vim.keymap.set("i", "<CR>", function()
  return vim.fn.pumvisible() == 1 and "<C-y>" or "<CR>"
end, { expr = true, noremap = true })

-- Navigate the completion popup with Cmd-j / Cmd-k instead of the arrow
-- keys. Requires the terminal to forward Cmd as a distinct modifier (e.g.
-- Ghostty/Kitty keyboard protocol) -- if these don't fire, Cmd isn't
-- reaching Neovim and <C-j>/<C-k> is the fallback.
vim.keymap.set("i", "<D-j>", function()
  return vim.fn.pumvisible() == 1 and "<C-n>" or "<D-j>"
end, { expr = true, noremap = true })

vim.keymap.set("i", "<D-k>", function()
  return vim.fn.pumvisible() == 1 and "<C-p>" or "<D-k>"
end, { expr = true, noremap = true })

-- Toggle for the eager-identifier-completion autocmd set up below (in
-- LspAttach). Flip to false if the popup showing up while typing plain
-- words gets annoying -- see the comment down there for the tradeoffs.
local eager_identifier_completion = true
local ident_completion_timers = {}

-- nvim-lspconfig is installed as an "opt" package, so load it explicitly.
vim.cmd("packadd nvim-lspconfig")

-- Enable the gopls server. nvim-lspconfig ships lsp/gopls.lua, which sets
-- the command, filetypes (go, gomod, gowork, gotmpl) and root detection.
vim.lsp.enable("gopls")

-- Enable zls (Zig Language Server, installed via `brew install zls`).
-- nvim-lspconfig ships lsp/zls.lua, which sets the command, filetype (zig)
-- and root detection (build.zig / build.zig.zon).
vim.lsp.enable("zls")

-- Enable rust-analyzer (installed via `rustup component add rust-analyzer`).
-- nvim-lspconfig ships lsp/rust_analyzer.lua, which sets the command,
-- filetype (rust) and root detection (Cargo.toml / rust-project.json).
vim.lsp.enable("rust_analyzer")

-- Python: two servers, same split of duties as elsewhere (a type/nav server
-- plus a fast separate linter/formatter). basedpyright (installed via
-- `uv tool install basedpyright`) gives hover/go-to-def/rename/type
-- diagnostics. nvim-lspconfig ships lsp/basedpyright.lua.
vim.lsp.enable("basedpyright")

-- ruff (installed via `uv tool install ruff`) gives lint diagnostics plus
-- the format/organize-imports code actions used in the on-save autocmd
-- below. nvim-lspconfig ships lsp/ruff.lua.
vim.lsp.enable("ruff")

-- LSP keymaps + Go-specific autoformat, wired up once a server attaches.
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local bufnr = args.buf
    local opts = { buffer = bufnr }

    -- Native LSP completion (no plugin needed, Neovim 0.11+). Without this,
    -- gopls attaching doesn't give you an autocomplete popup at all.
    vim.lsp.completion.enable(true, args.data.client_id, bufnr, { autotrigger = true })

    -- autotrigger only fires on the server's triggerCharacters (for gopls,
    -- just "."), so plain identifiers (e.g. local vars) never auto-pop the
    -- menu. Manually request completion for that case.
    vim.keymap.set("i", "<C-Space>", function()
      vim.lsp.completion.get()
    end, opts)

    -- Eager auto-popup on plain identifiers too (e.g. typing "appe" shows
    -- append/appends), not just after ".". Tradeoffs vs. the <C-Space>-only
    -- approach above: sends a completion request to gopls on every word
    -- character typed (debounced 100ms) instead of only on "."; no syntax
    -- awareness, so it also pops the menu inside comments/strings and while
    -- naming new variables; and combined with the <CR> remap up top,
    -- pressing Enter right after a word can confirm a completion instead of
    -- inserting a newline if the menu happened to be open. Set
    -- eager_identifier_completion to false above to turn this off again.
    if eager_identifier_completion then
      vim.api.nvim_create_autocmd("InsertCharPre", {
        buffer = bufnr,
        callback = function()
          if vim.fn.pumvisible() ~= 0 or not vim.v.char:match("[%w_]") then
            return
          end
          local timer = ident_completion_timers[bufnr]
          if timer then
            timer:stop()
            timer:close()
          end
          timer = vim.uv.new_timer()
          ident_completion_timers[bufnr] = timer
          timer:start(
            100,
            0,
            vim.schedule_wrap(function()
              vim.lsp.completion.get()
            end)
          )
        end,
      })
    end

    vim.keymap.set("n", "gd", require("fzf-lua").lsp_definitions, opts)
    vim.keymap.set("n", "gr", require("fzf-lua").lsp_references, opts)
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)

    -- rust-analyzer-specific: force it to re-run `cargo metadata` and pick
    -- up newly created files (e.g. a fresh src/bin/*.rs) without needing to
    -- close/reopen the buffer or restart the whole LSP client.
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client.name == "rust_analyzer" then
      vim.keymap.set("n", "<leader>rw", function()
        vim.lsp.buf_request(bufnr, "rust-analyzer/reloadWorkspace", vim.NIL, function()
          vim.notify("rust-analyzer: workspace reloaded")
        end)
      end, vim.tbl_extend("force", opts, { desc = "rust-analyzer: reload workspace" }))
    end
  end,
})

-- Open Claude Code in a vertical terminal split, pre-filled with a prompt
-- referencing the current file (claude's "@path" context syntax). The
-- closing quote is sent then the cursor is moved back inside it (via a
-- terminal cursor-left escape) so you can type your ask and hit <CR> to run.
vim.keymap.set("n", "<leader>claude", function()
  local file = vim.fn.expand("%:.")
  if file == "" then
    vim.notify("No file in this buffer", vim.log.levels.WARN)
    return
  end
  vim.cmd("vsplit")
  vim.cmd("terminal")
  vim.fn.chansend(vim.b.terminal_job_id, 'claude "@' .. file .. '"')
  vim.fn.chansend(vim.b.terminal_job_id, "\x1b[D")
  vim.cmd("startinsert")
end, { desc = "Claude Code: open with current file as context" })

-- fzf-lua: fuzzy file/text finder, backed by the fzf, fd and rg binaries
-- (installed via `brew install fzf fd ripgrep`). <leader>ff fuzzy-matches
-- filenames (fd for listing, so .gitignore'd files are skipped); <leader>fg
-- live-greps file contents (rg).
vim.cmd("packadd fzf-lua")
require("fzf-lua").setup({})
vim.keymap.set("n", "<leader>ff", require("fzf-lua").files, { desc = "fzf-lua: find files" })
vim.keymap.set("n", "<leader>fg", require("fzf-lua").live_grep, { desc = "fzf-lua: live grep" })

-- render-markdown.nvim renders markdown (headers, bold/italic, checkboxes,
-- tables, code blocks) inline in the buffer for viewing, not raw text.
-- It relies on nvim-treesitter for the markdown/markdown_inline parsers.
vim.cmd("packadd nvim-treesitter")
vim.cmd("packadd render-markdown.nvim")
require("render-markdown").setup({})

-- Display tabs as 4 columns wide in Go files. This is purely visual -- the
-- file on disk still stores tabs (gofmt always emits tabs, unconfigurably),
-- this just changes how wide a tab renders in this editor.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "go",
  callback = function()
    vim.bo.tabstop = 4
    vim.bo.shiftwidth = 4
  end,
})

-- On save of a Go file: organize imports, then format.
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*.go",
  callback = function()
    -- goimports-style organize imports via a code action
    local params = vim.lsp.util.make_range_params(0, "utf-8")
    params.context = { only = { "source.organizeImports" } }
    local result = vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, 1000)
    for _, res in pairs(result or {}) do
      for _, action in pairs(res.result or {}) do
        if action.edit then
          vim.lsp.util.apply_workspace_edit(action.edit, "utf-8")
        end
      end
    end
    vim.lsp.buf.format({ async = false })
  end,
})

-- zig fmt on save. No organize-imports step here -- Zig has no equivalent
-- code action (imports are just `const x = @import(...)` declarations, not
-- a separate managed block gofmt-style tooling would reorder).
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*.zig",
  callback = function()
    vim.lsp.buf.format({ async = false })
  end,
})

-- rustfmt on save, via rust-analyzer's formatting request (same mechanism as
-- `cargo fmt`, just applied in-buffer instead of shelling out).
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*.rs",
  callback = function()
    vim.lsp.buf.format({ async = false })
  end,
})

-- On save of a Python file: organize imports via ruff's code action, then
-- format with ruff specifically (not vim.lsp.buf.format, which would let
-- basedpyright answer the formatting request first since it's also
-- attached -- basedpyright doesn't format, so that silently no-ops).
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*.py",
  callback = function()
    local params = vim.lsp.util.make_range_params(0, "utf-8")
    -- ruff's server requires `diagnostics` per the LSP spec (gopls, used by
    -- the equivalent Go autocmd above, tolerates it being omitted -- ruff
    -- doesn't and rejects the request with a JSON parsing failure).
    params.context = { only = { "source.organizeImports" }, diagnostics = {} }
    local result = vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, 1000)
    for _, res in pairs(result or {}) do
      for _, action in pairs(res.result or {}) do
        if action.edit then
          vim.lsp.util.apply_workspace_edit(action.edit, "utf-8")
        end
      end
    end

    local ruff_clients = vim.lsp.get_clients({ bufnr = 0, name = "ruff" })
    if #ruff_clients > 0 then
      vim.lsp.buf.format({ async = false, id = ruff_clients[1].id })
    end
  end,
})
