-- Warm built-in colorscheme, deliberately distinct from the cool blue/purple
-- Ghostty theme so it's obvious at a glance when you're inside nvim.
vim.cmd.colorscheme("retrobox")

-- Show line numbers. Set relativenumber too for relative numbering.
vim.opt.number = true
-- vim.opt.relativenumber = true

-- Show diagnostic messages inline at the end of the line.
vim.diagnostic.config({ virtual_text = true })

-- Fuzzy-match native completion (Neovim 0.11+) so typing e.g. "wrst" can
-- still surface "WriteString" instead of only matching by strict prefix.
vim.opt.completeopt = { "menuone", "noselect", "popup", "fuzzy" }

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

-- nvim-lspconfig is installed as an "opt" package, so load it explicitly.
vim.cmd("packadd nvim-lspconfig")

-- Enable the gopls server. nvim-lspconfig ships lsp/gopls.lua, which sets
-- the command, filetypes (go, gomod, gowork, gotmpl) and root detection.
vim.lsp.enable("gopls")

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

    vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
  end,
})

-- render-markdown.nvim renders markdown (headers, bold/italic, checkboxes,
-- tables, code blocks) inline in the buffer for viewing, not raw text.
-- It relies on nvim-treesitter for the markdown/markdown_inline parsers.
vim.cmd("packadd nvim-treesitter")
vim.cmd("packadd render-markdown.nvim")
require("render-markdown").setup({})

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
