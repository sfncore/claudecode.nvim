-- Minimal repro config for claudecode.nvim issues.
--
-- This fixture intentionally avoids a plugin manager so it's easy to run and reason about.
--
-- Usage (from repo root):
--   source fixtures/nvim-aliases.sh
--   repro
--
-- To edit this config:
--   vve repro

-- Ensure this repo is on the runtimepath so `plugin/claudecode.lua` is loaded.
local config_dir = vim.fn.stdpath("config")
local repo_root = vim.fn.fnamemodify(config_dir, ":h:h")

vim.opt.rtp:prepend(repo_root)

-- Basic editor settings
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

local ok, claudecode = pcall(require, "claudecode")
assert(ok, "Failed to load claudecode.nvim from repo root: " .. tostring(claudecode))

claudecode.setup({
  log_level = "debug",
  terminal = {
    provider = "native",
    auto_close = false,
  },
  diff_opts = {
    layout = "vertical",
    open_in_new_tab = false,
    keep_terminal_focus = false,
  },
})

-- Keymaps (kept small on purpose)
vim.keymap.set("n", "<leader>ac", "<cmd>ClaudeCode<cr>", { desc = "Toggle Claude" })
vim.keymap.set("n", "<leader>af", "<cmd>ClaudeCodeFocus<cr>", { desc = "Focus Claude" })

vim.keymap.set("n", "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", { desc = "Accept diff" })
vim.keymap.set("n", "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", { desc = "Deny diff" })

vim.keymap.set("n", "<leader>aw", function()
  vim.notify(("windows in tab: %d"):format(vim.fn.winnr("$")))
end, { desc = "Claude: show window count" })
