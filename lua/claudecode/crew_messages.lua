---@brief [[
--- Priority-aware message queue for crew mesh messages received via the adapter WS.
---
--- Messages are accumulated here with priority levels (urgent/normal/low),
--- deduplication of rapid status updates, and batch flush at turn boundaries.
--- Exposed to MCP clients (e.g., prism.nvim) via resource reads and to
--- Claude Code via system-reminder injection on UserPromptSubmit hooks.
---@brief ]]
---@module 'claudecode.crew_messages'

local M = {}

---@class CrewMessage
---@field from string Sender agent name
---@field body string Message content
---@field priority string "urgent"|"normal"|"low"
---@field timestamp string ISO 8601 timestamp
---@field read boolean Whether the message has been consumed by an MCP read
---@field msg_type string|nil Optional message type for dedup (e.g., "status-update")

---@type CrewMessage[]
local messages = {}

---@type number Maximum messages to retain
local MAX_MESSAGES = 100

---@type number Priority weights for sorting (lower = higher priority)
local PRIORITY_WEIGHT = {
  urgent = 1,
  normal = 2,
  low = 3,
}

---Store a new message from the adapter WS
---@param msg table { from=string, body=string, priority=string, msg_type=string|nil }
function M.push(msg)
  local priority = msg.priority or "normal"
  local msg_type = msg.msg_type or nil
  local from = msg.from or "unknown"

  -- Dedup: if this is a status-update from the same sender, replace the previous one
  if msg_type == "status-update" then
    for i = #messages, 1, -1 do
      if messages[i].from == from and messages[i].msg_type == "status-update" and not messages[i].read then
        table.remove(messages, i)
        break
      end
    end
  end

  table.insert(messages, {
    from = from,
    body = msg.body or "",
    priority = priority,
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    read = false,
    msg_type = msg_type,
  })

  -- Trim old messages (remove lowest priority first)
  while #messages > MAX_MESSAGES do
    -- Find lowest priority unread message to evict
    local evict_idx = 1
    local evict_weight = 0
    for i, m in ipairs(messages) do
      local w = PRIORITY_WEIGHT[m.priority] or 2
      if w > evict_weight then
        evict_weight = w
        evict_idx = i
      end
    end
    table.remove(messages, evict_idx)
  end

  -- Notify prism MCP clients that resources changed
  local prism_ok, prism_mcp = pcall(require, "prism.mcp")
  if prism_ok and prism_mcp.broadcast then
    prism_mcp.broadcast("notifications/resources/list_changed", {})
  end
end

---Read all unread messages and mark them as read
---@return CrewMessage[]
function M.read_unread()
  local unread = {}
  for _, msg in ipairs(messages) do
    if not msg.read then
      msg.read = true
      table.insert(unread, msg)
    end
  end
  return unread
end

---Read all messages (including already-read ones)
---@return CrewMessage[]
function M.read_all()
  return messages
end

---Get count of unread messages
---@return number
function M.unread_count()
  local count = 0
  for _, msg in ipairs(messages) do
    if not msg.read then
      count = count + 1
    end
  end
  return count
end

---Clear all messages
function M.clear()
  messages = {}
end

---Flush unread messages sorted by priority, mark as read, return formatted batch.
---Designed to be called by UserPromptSubmit hooks for system-reminder injection.
---@return string formatted Formatted message batch (empty string if no messages)
---@return number count Number of messages flushed
function M.flush()
  local unread = {}
  for _, msg in ipairs(messages) do
    if not msg.read then
      table.insert(unread, msg)
    end
  end

  if #unread == 0 then
    return "", 0
  end

  -- Sort by priority (urgent first, then normal, then low)
  table.sort(unread, function(a, b)
    local wa = PRIORITY_WEIGHT[a.priority] or 2
    local wb = PRIORITY_WEIGHT[b.priority] or 2
    if wa ~= wb then
      return wa < wb
    end
    return a.timestamp < b.timestamp
  end)

  -- Mark all as read
  for _, msg in ipairs(unread) do
    msg.read = true
  end

  -- Format as batch
  return M.format_for_resource(unread), #unread
end

---Format messages for MCP resource response or system-reminder injection
---@param msgs CrewMessage[]
---@return string
function M.format_for_resource(msgs)
  if #msgs == 0 then
    return "No new crew messages."
  end

  local lines = {}
  for _, msg in ipairs(msgs) do
    local prefix = msg.priority == "urgent" and "[URGENT] " or ""
    table.insert(lines, string.format("%s[from %s] %s", prefix, msg.from, msg.body))
  end
  return table.concat(lines, "\n")
end

return M
