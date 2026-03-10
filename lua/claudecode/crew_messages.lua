---@brief [[
--- In-memory message store for crew mesh messages received via the adapter WS.
--- Messages are accumulated here and exposed to MCP clients (e.g., prism.nvim)
--- via a resource read, enabling direct context injection without the nudge queue.
---@brief ]]
---@module 'claudecode.crew_messages'

local M = {}

---@class CrewMessage
---@field from string Sender agent name
---@field body string Message content
---@field priority string "urgent"|"normal"|"low"
---@field timestamp string ISO 8601 timestamp
---@field read boolean Whether the message has been consumed by an MCP read

---@type CrewMessage[]
local messages = {}

---@type number Maximum messages to retain
local MAX_MESSAGES = 100

---Store a new message from the adapter WS
---@param msg table { from=string, body=string, priority=string }
function M.push(msg)
  table.insert(messages, {
    from = msg.from or "unknown",
    body = msg.body or "",
    priority = msg.priority or "normal",
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    read = false,
  })

  -- Trim old messages
  while #messages > MAX_MESSAGES do
    table.remove(messages, 1)
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

---Format messages for MCP resource response
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
