---@brief [[
--- Context-mode stats winbar for Claude Code terminal.
--- Polls a JSON stats file written by context-mode and displays
--- session statistics on the terminal window's winbar.
---@brief ]]
---@module 'claudecode.context_mode'

local logger = require("claudecode.logger")

local M = {}

---@class ContextModeConfig
---@field enabled boolean
---@field poll_interval_ms number
---@field stats_file string|nil
---@field format string

local DEFAULT_STATS_FILE = vim.fn.expand("~/.claude/context-mode/stats.json")
local STALE_THRESHOLD_MS = 60000

---@type vim.loop.Timer|nil
local poll_timer = nil

---@type ContextModeConfig|nil
local config = nil

---@type table|nil
local last_stats = nil

---Format bytes into human-readable string
---@param bytes number
---@return string
local function format_bytes(bytes)
  if bytes >= 1048576 then
    return string.format("%.1fMB", bytes / 1048576)
  elseif bytes >= 1024 then
    return string.format("%.0fKB", bytes / 1024)
  else
    return string.format("%dB", bytes)
  end
end

---Format token count into compact string
---@param tokens number
---@return string
local function format_tokens(tokens)
  if tokens >= 1000000 then
    return string.format("%.1fm", tokens / 1000000)
  elseif tokens >= 1000 then
    return string.format("%.0fk", tokens / 1000)
  else
    return tostring(tokens)
  end
end

---Format stats into a winbar string
---@param stats table The parsed stats JSON
---@param fmt string "compact" or "full"
---@return string
function M.format_winbar(stats, fmt)
  if not stats or not stats.total_calls then
    return ""
  end

  local tokens_saved = format_tokens(stats.tokens_saved or 0)
  local ratio = string.format("%.1fx", stats.savings_ratio or 0)

  if fmt == "full" then
    local processed = format_bytes(stats.bytes_processed or 0)
    local saved = format_bytes(stats.bytes_saved or 0)
    local pct = stats.reduction_pct or 0
    return string.format(
      " ctx: %d calls | %s proc | %s saved | ~%s tok saved (%s, %d%%)",
      stats.total_calls,
      processed,
      saved,
      tokens_saved,
      ratio,
      pct
    )
  end

  -- compact (default)
  return string.format(" ctx: %d calls | saved %s tok (%s)", stats.total_calls, tokens_saved, ratio)
end

---Read and parse the stats file
---@param file_path string
---@return table|nil stats Parsed stats or nil
function M.read_stats(file_path)
  local f = io.open(file_path, "r")
  if not f then
    return nil
  end

  local content = f:read("*a")
  f:close()

  if not content or content == "" then
    return nil
  end

  local ok, stats = pcall(vim.json.decode, content)
  if not ok or type(stats) ~= "table" then
    return nil
  end

  return stats
end

---Find the terminal window ID by scanning for the terminal buffer
---@return number|nil win_id
function M.get_terminal_win_id()
  local terminal_ok, terminal = pcall(require, "claudecode.terminal")
  if not terminal_ok then
    return nil
  end

  local bufnr = terminal.get_active_terminal_bufnr and terminal.get_active_terminal_bufnr()
  if not bufnr then
    return nil
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end

  return nil
end

---Check if stats are stale based on updated_at timestamp
---@param stats table
---@return boolean
local function is_stale(stats)
  if not stats or not stats.updated_at then
    return true
  end
  local now_ms = vim.loop.now()
  -- updated_at is epoch ms, vim.loop.now() is ms since process start
  -- Use os.time() * 1000 for epoch comparison
  local now_epoch = os.time() * 1000
  return (now_epoch - stats.updated_at) > STALE_THRESHOLD_MS
end

---Update the winbar on the terminal window
local function update_winbar()
  if not config then
    return
  end

  local stats_file = config.stats_file or DEFAULT_STATS_FILE
  local stats = M.read_stats(stats_file)
  local win_id = M.get_terminal_win_id()

  if not win_id then
    last_stats = stats
    return
  end

  if not stats or is_stale(stats) then
    -- Clear winbar if no stats or stale
    pcall(vim.api.nvim_set_option_value, "winbar", "", { win = win_id })
    last_stats = nil
    return
  end

  last_stats = stats
  local winbar_text = M.format_winbar(stats, config.format or "compact")
  pcall(vim.api.nvim_set_option_value, "winbar", winbar_text, { win = win_id })
end

---Start polling for context-mode stats
---@param cfg ContextModeConfig
function M.setup(cfg)
  config = cfg

  if not cfg.enabled then
    return
  end

  M.start()
  logger.debug("context_mode", "Context-mode winbar enabled, polling every " .. cfg.poll_interval_ms .. "ms")
end

---Start the polling timer
function M.start()
  if poll_timer then
    return
  end

  local interval = (config and config.poll_interval_ms) or 3000
  interval = math.max(500, interval) -- minimum 500ms

  poll_timer = vim.loop.new_timer()
  poll_timer:start(
    1000, -- initial delay: 1s
    interval,
    vim.schedule_wrap(function()
      update_winbar()
    end)
  )
end

---Stop the polling timer and clear winbar
function M.stop()
  if poll_timer then
    poll_timer:stop()
    poll_timer:close()
    poll_timer = nil
  end

  -- Clear winbar on the terminal window
  local win_id = M.get_terminal_win_id()
  if win_id then
    pcall(vim.api.nvim_set_option_value, "winbar", "", { win = win_id })
  end

  last_stats = nil
  config = nil
end

---Get the last read stats (for external consumers like statusline)
---@return table|nil
function M.get_stats()
  return last_stats
end

return M
