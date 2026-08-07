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

-- netrw as the file tree (no plugin). liststyle 3 is the nested tree view.
vim.g.netrw_liststyle = 3
vim.g.netrw_banner = 0 -- hide the top banner
vim.g.netrw_winsize = 20 -- left split width, in percent

-- 4 = "open in the previous window", i.e. whichever code window you were
-- last in, so the sidebar itself is never replaced. Not 0: that reuses one
-- pinned window, which with two or more splits open means every <CR> lands
-- in the same split and the others become unreachable from the tree.
vim.g.netrw_browse_split = 4
vim.g.netrw_altfile = 1 -- keep <C-^> pointing at the real previous file, not netrw

-- Toggle the sidebar. :Lexplore is netrw's own left-split explorer, and
-- calling it again closes it.
vim.keymap.set("n", "<leader>e", ":Lexplore<cr>", { silent = true, desc = "netrw: toggle file tree" })

-- `nvim .` (or any directory argument) hands netrw the whole window rather
-- than the sidebar layout, so the first file you open replaces the tree
-- instead of appearing beside it. Convert it on startup: blank out the main
-- pane and reopen the tree via :Lexplore, giving the same left rail /
-- netrw_winsize ratio you get from <leader>e. The argc check keeps a bare
-- `nvim` out of this -- with no buffer name, "%:p" expands to the cwd and
-- would otherwise look like a directory argument.
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    local path = vim.fn.expand("%:p")
    if vim.fn.argc() ~= 1 or vim.fn.isdirectory(path) == 0 then
      return
    end
    local dirbuf = vim.api.nvim_get_current_buf()
    vim.cmd("cd " .. vim.fn.fnameescape(path))
    vim.cmd("enew") -- empty main pane for files to open into
    pcall(vim.api.nvim_buf_delete, dirbuf, { force = true })
    vim.cmd("Lexplore")
  end,
})

-- Closing the last file window leaves the tree as the only window, where it
-- stretches to full width and stops acting like a sidebar. netrw then has no
-- window to open into, so its one-window fallback (s:NetrwPrevWinOpen) carves
-- a horizontal split sized by netrw_winsize -- a 4-line strip above the tree
-- rather than a pane beside it. Restore the empty main pane instead, which
-- also gives netrw_browse_split = 4 something to target again.
vim.api.nvim_create_autocmd("WinClosed", {
  callback = function()
    -- WinClosed fires while the window still exists, so the count is only
    -- correct once it's actually gone.
    vim.schedule(function()
      if vim.v.exiting ~= vim.NIL then
        return
      end
      local wins = vim.api.nvim_tabpage_list_wins(0)
      if #wins ~= 1 or vim.bo[vim.api.nvim_win_get_buf(wins[1])].filetype ~= "netrw" then
        return
      end
      vim.cmd("botright vnew") -- empty pane on the right
      vim.cmd("wincmd h") -- back to the tree, ready to pick
      vim.cmd("vertical resize " .. math.floor(vim.o.columns * vim.g.netrw_winsize / 100))
    end)
  end,
})

-- Follow the focused file in the sidebar: move the tree's cursor onto
-- whichever file you switch to, expanding parent directories along the way,
-- so the highlighted line always reflects the active split. netrw already
-- sets 'cursorline' in its window (netrw_cursor defaults to 2) and that
-- highlight renders even while the window is unfocused, so once the cursor is
-- on the right line there's nothing further to draw.
local function netrw_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "netrw" then
      return w
    end
  end
end

-- Tree listing indents one "| " per level, e.g. "| | inner.go" at depth 2.
local function depth_of(line)
  local d = 0
  while line:sub(1, 2) == "| " do
    d, line = d + 1, line:sub(3)
  end
  return d
end

-- Find `name` at `depth`, scanning only from `from` until indentation rises
-- back out of the enclosing directory. Name plus depth is NOT unique -- two
-- files with the same name at the same depth under different parents render as
-- identical lines -- so the descent below narrows the range at every level.
local function tree_line(win, name, depth, from)
  local want = string.rep("| ", depth) .. name
  local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
  for i = from, #lines do
    if depth_of(lines[i]) < depth then
      return nil -- left the parent's subtree without a match
    end
    if lines[i] == want then
      return i
    end
  end
end

local function reveal_in_tree(win, file)
  local ok, treetop = pcall(vim.api.nvim_win_get_var, win, "netrw_treetop")
  if not ok or type(treetop) ~= "string" or treetop == "" then
    return
  end
  treetop = (vim.fn.fnamemodify(treetop, ":p"):gsub("/$", ""))
  -- Nothing to reveal for a file outside the tree's root.
  if file:sub(1, #treetop + 1) ~= treetop .. "/" then
    return
  end

  local parts = vim.split(file:sub(#treetop + 2), "/", { plain = true })

  -- Start below the tree root's own line: the listing opens with "../" and the
  -- root, both at depth 0, and scanning from line 1 would stop instantly.
  local from = 1
  for i, line in ipairs(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)) do
    if depth_of(line) == 0 and line ~= "../" then
      from = i + 1
      break
    end
  end

  -- Walk down the path, expanding any ancestor netrw hasn't opened yet.
  -- w:netrw_treedict is keyed by expanded directory (absolute, no trailing
  -- slash), so it answers "already open?" directly -- which matters because
  -- netrw's <CR> toggles, and pressing it on an open directory collapses it.
  local dir = treetop
  for i = 1, #parts do
    local is_dir = i < #parts
    local name = parts[i] .. (is_dir and "/" or "")
    local ln = tree_line(win, name, i, from)
    if not is_dir then
      if ln then
        pcall(vim.api.nvim_win_set_cursor, win, { ln, 0 })
      end
      return
    end

    dir = dir .. "/" .. parts[i]
    local dict = select(2, pcall(vim.api.nvim_win_get_var, win, "netrw_treedict"))
    if type(dict) ~= "table" or dict[dir] == nil then
      if not ln then
        return
      end
      vim.api.nvim_win_set_cursor(win, { ln, 0 })
      vim.api.nvim_win_call(win, function()
        vim.cmd("normal \r") -- no bang: netrw's own <CR> mapping does the expand
      end)
      ln = tree_line(win, name, i, from) -- listing re-rendered
    end
    if not ln then
      return
    end
    from = ln + 1 -- descend into this directory's subtree
  end
end

local syncing_tree = false

vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
  callback = function()
    -- Expanding re-renders the listing and fires these same events.
    if syncing_tree then
      return
    end
    -- Only real files: skip netrw itself, terminals, help, quickfix, [No Name].
    if vim.bo.buftype ~= "" or vim.bo.filetype == "netrw" then
      return
    end
    local file = vim.api.nvim_buf_get_name(0)
    if file == "" then
      return
    end
    local win = netrw_win()
    if not win then
      return
    end
    -- netrw_keepdir = 0 lets netrw move the cwd as it browses, which is wanted
    -- when *you* navigate but not as a side effect of automatic syncing.
    local cwd = vim.fn.getcwd()
    syncing_tree = true
    pcall(reveal_in_tree, win, file)
    syncing_tree = false
    if vim.fn.getcwd() ~= cwd then
      vim.cmd("cd " .. vim.fn.fnameescape(cwd))
    end
  end,
})

-- netrw's built-in `%` (create file) opens the new file in the netrw window
-- itself, ignoring netrw_browse_split, which leaves the sidebar showing a
-- buffer instead of the tree. Override it to create the file and edit it in
-- the previous window -- and to make a directory instead when the name ends
-- in "/".
vim.api.nvim_create_autocmd("FileType", {
  pattern = "netrw",
  callback = function()
    vim.keymap.set("n", "%", function()
      local fname = vim.fn.input("Enter filename: ")
      if fname == "" then
        return
      end

      local dir = vim.b.netrw_curdir or vim.fn.getcwd()
      local path = dir .. "/" .. fname

      if vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1 then
        vim.notify("Already exists: " .. fname, vim.log.levels.WARN)
        return
      end

      if fname:match("/$") then
        vim.fn.mkdir(path, "p")
        vim.cmd("edit") -- reload the listing so the new dir shows up
      else
        local f = io.open(path, "w")
        if not f then
          vim.notify("Failed to create: " .. fname, vim.log.levels.ERROR)
          return
        end
        f:close()

        local escaped = vim.fn.fnameescape(path)
        if vim.fn.winnr("#") == 0 then
          vim.cmd("edit " .. escaped)
        else
          vim.cmd("wincmd p")
          vim.cmd("edit " .. escaped)
        end
      end
    end, { buffer = true, silent = true, noremap = true, desc = "netrw: create file in previous window" })
  end,
})

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

-- Statusline: mode | git branch | repo-relative path .... diagnostics ft l:c
-- Built with %! so the whole line is re-evaluated on every redraw, which is
-- what lets the mode indicator and cursor position stay live without any
-- plugin. Colors are derived from whatever colorscheme is loaded (retrobox
-- above) rather than hardcoded, so it doesn't clash if that changes.
local pms = vim.api.nvim_get_hl(0, { name = "PmenuSel", link = false })
local dir_hl = vim.api.nvim_get_hl(0, { name = "Directory", link = false })
local vis = vim.api.nvim_get_hl(0, { name = "Visual", link = false })
local nrm = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
-- Fall back to Normal's fg: retrobox (and other schemes) define PmenuSel with
-- only a bg, and an unset fg here renders the mode text nearly black against
-- Visual's dark bg.
vim.api.nvim_set_hl(0, "StlMode", { fg = pms.fg or nrm.fg, bg = vis.bg, bold = true })
vim.api.nvim_set_hl(0, "StlGit", { fg = dir_hl.fg, bg = pms.bg })

local modes = {
  n = "NORMAL",
  i = "INSERT",
  v = "VISUAL",
  V = "V-LINE",
  ["\22"] = "V-BLOCK", -- <C-v>
  c = "COMMAND",
  t = "TERMINAL",
  R = "REPLACE",
  s = "SELECT",
  S = "S-LINE",
  ["\19"] = "S-BLOCK", -- <C-s>
}

function _G._statusline()
  local mode = modes[vim.fn.mode()] or vim.fn.mode():upper()
  local branch = vim.b.git_branch and "%#StlGit#  " .. vim.b.git_branch .. " %*" or ""
  local path = vim.b.rel_path or "%f"

  -- vim.diagnostic.count returns a severity-indexed table; 1..4 are
  -- ERROR/WARN/INFO/HINT. Only non-zero counts get a segment.
  local diag = ""
  local labels = { " ", " ", " ", " " }
  local hls = { "DiagnosticError", "DiagnosticWarn", "DiagnosticInfo", "DiagnosticHint" }
  local counts = vim.diagnostic.count(0) or {}
  for i = 1, 4 do
    if counts[i] and counts[i] > 0 then
      diag = diag .. "%#" .. hls[i] .. "#" .. labels[i] .. counts[i] .. "%* "
    end
  end

  return "%#StlMode# " .. mode .. " %*" .. branch .. " " .. path .. "%=" .. diag .. vim.bo.filetype .. " %l:%c"
end

-- Cache the branch and repo-relative path per buffer instead of computing
-- them inside _statusline(), which runs on every single redraw.
-- ponytail: two synchronous `git` spawns per BufEnter -- unnoticeable
-- locally, switch to vim.system() async if it ever stutters on a network FS.
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function()
    local root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("%s+$", "")
    if root ~= "" then
      vim.b.git_branch = vim.fn.system("git branch --show-current 2>/dev/null"):gsub("%s+$", "")
      vim.b.rel_path = vim.fn.expand("%:p"):sub(#root + 2)
    else
      vim.b.git_branch = nil
      vim.b.rel_path = vim.fn.expand("%:p:~")
    end
  end,
})

-- Diagnostics arrive asynchronously from the LSP, which isn't a redraw
-- trigger on its own -- without this the counts lag until the next keypress.
vim.api.nvim_create_autocmd("DiagnosticChanged", {
  callback = function()
    vim.cmd("redrawstatus!")
  end,
})

vim.o.statusline = "%!v:lua._statusline()"
