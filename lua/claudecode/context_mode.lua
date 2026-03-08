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
---@field stats_dir string|nil
---@field format string

local STATS_DIR = vim.fn.expand("~/.claude/context-mode")
local STALE_THRESHOLD_MS = 600000 -- 10 minutes

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

---Find the terminal window ID and buffer by scanning for the terminal buffer
---@return number|nil win_id
---@return number|nil bufnr
function M.get_terminal_win_and_buf()
  local terminal_ok, terminal = pcall(require, "claudecode.terminal")
  if not terminal_ok then
    return nil, nil
  end

  local bufnr = terminal.get_active_terminal_bufnr and terminal.get_active_terminal_bufnr()
  if not bufnr then
    return nil, nil
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      return win, bufnr
    end
  end

  return nil, bufnr
end

---Find the terminal window ID (backward compat)
---@return number|nil win_id
function M.get_terminal_win_id()
  local win_id, _ = M.get_terminal_win_and_buf()
  return win_id
end

---Get the parent PID of a process by reading /proc/{pid}/stat
---@param pid number
---@return number|nil ppid
local function get_ppid(pid)
  local f = io.open("/proc/" .. pid .. "/stat", "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  -- /proc/pid/stat format: pid (comm) state ppid ...
  -- comm can contain spaces/parens, so match after the last ')'
  local after_comm = content:match("^.*%)%s+%S+%s+(%d+)")
  return after_comm and tonumber(after_comm)
end

---Check if candidate_pid is a descendant of ancestor_pid
---@param candidate_pid number
---@param ancestor_pid number
---@param max_depth number|nil Maximum depth to walk (default 10)
---@return boolean
local function is_descendant(candidate_pid, ancestor_pid, max_depth)
  max_depth = max_depth or 10
  local pid = candidate_pid
  for _ = 1, max_depth do
    if pid == ancestor_pid then
      return true
    end
    if pid <= 1 then
      return false
    end
    local ppid = get_ppid(pid)
    if not ppid or ppid == pid then
      return false
    end
    pid = ppid
  end
  return false
end

---Get the job PID of the terminal buffer
---@param bufnr number
---@return number|nil
local function get_terminal_job_pid(bufnr)
  local ok, job_id = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
  if not ok or not job_id then
    return nil
  end
  local pid_ok, pid = pcall(vim.fn.jobpid, job_id)
  if not pid_ok then
    return nil
  end
  return pid
end

---Scan stats directory for per-PID stats files
---@return table[] Array of {path=string, stats=table}
local function scan_stats_files()
  local results = {}
  local dir = config and config.stats_dir or STATS_DIR
  -- Handle both legacy stats.json and per-PID stats-{pid}.json
  local handle = vim.loop.fs_scandir(dir)
  if not handle then
    return results
  end
  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end
    if type == "file" and (name:match("^stats%-%d+%.json$") or name == "stats.json") then
      local path = dir .. "/" .. name
      local stats = M.read_stats(path)
      if stats then
        table.insert(results, { path = path, stats = stats })
      end
    end
  end
  return results
end

---Check if stats are stale based on updated_at timestamp
---@param stats table
---@return boolean
local function is_stale(stats)
  if not stats or not stats.updated_at then
    return true
  end
  local now_epoch = os.time() * 1000
  return (now_epoch - stats.updated_at) > STALE_THRESHOLD_MS
end

---Find the best matching stats file for the current terminal
---@param terminal_bufnr number|nil
---@return table|nil stats
local function find_matching_stats(terminal_bufnr)
  local entries = scan_stats_files()
  if #entries == 0 then
    return nil
  end

  -- If we have a terminal buffer, try process tree matching
  if terminal_bufnr then
    local job_pid = get_terminal_job_pid(terminal_bufnr)
    if job_pid then
      for _, entry in ipairs(entries) do
        if entry.stats.pid and not is_stale(entry.stats) then
          if is_descendant(entry.stats.pid, job_pid) then
            return entry.stats
          end
        end
      end
    end
  end

  -- Fallback: pick the most recently updated non-stale entry
  local best = nil
  for _, entry in ipairs(entries) do
    if not is_stale(entry.stats) then
      if not best or (entry.stats.updated_at or 0) > (best.updated_at or 0) then
        best = entry.stats
      end
    end
  end
  return best
end

---Update the winbar on the terminal window
local function update_winbar()
  if not config then
    return
  end

  local win_id, bufnr = M.get_terminal_win_and_buf()
  local stats = find_matching_stats(bufnr)

  if not win_id then
    last_stats = stats
    return
  end

  if not stats then
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
