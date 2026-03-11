---@brief [[
--- Agent status state machine for the crew mesh.
---
--- Tracks the current agent status and broadcasts transitions to the
--- tmux adapter WebSocket mesh. Hook scripts and internal modules set
--- status via M.set(), which validates transitions and notifies the mesh.
---
--- States:
---   idle              — Waiting for input (prompt visible)
---   busy-with-overseer — Human is interacting (prompt submitted)
---   busy-with-tool     — Executing a tool call
---   busy-with-agent    — Processing agent communication
---   offline            — Session ended or not yet started
---@brief ]]
---@module 'claudecode.status'

local logger = require("claudecode.logger")

local M = {}

---@alias AgentStatus
---| "idle"
---| "busy-with-overseer"
---| "busy-with-tool"
---| "busy-with-agent"
---| "offline"

---@type AgentStatus
local current_status = "offline"

---@type string|nil Extra context (e.g., tool name when busy-with-tool)
local status_detail = nil

---@type number|nil Timestamp of last status change (os.clock())
local last_changed_at = nil

---@type table<string, boolean> Valid status values
local VALID_STATUSES = {
  ["idle"] = true,
  ["busy-with-overseer"] = true,
  ["busy-with-tool"] = true,
  ["busy-with-agent"] = true,
  ["offline"] = true,
}

---@type function|nil Callback fired on every status change: fn(new_status, old_status, detail)
local on_change_callback = nil

---Broadcast current status to the mesh via the adapter
---@param status string
local function broadcast(status)
  local ok, adapter = pcall(require, "claudecode.adapter")
  if ok and adapter.is_connected() then
    adapter.report_status(status)
  end
end

---Set the agent status, validate, broadcast, and fire callbacks.
---@param new_status AgentStatus The new status
---@param detail string|nil Optional context (e.g., tool name)
---@return boolean ok Whether the status was changed
---@return string|nil err Error message if invalid
function M.set(new_status, detail)
  if not VALID_STATUSES[new_status] then
    return false, "invalid status: " .. tostring(new_status)
  end

  local old_status = current_status

  -- Skip if already in this state (with same detail)
  if new_status == old_status and detail == status_detail then
    return true, nil
  end

  current_status = new_status
  status_detail = detail
  last_changed_at = os.clock()

  logger.debug("status", old_status .. " -> " .. new_status .. (detail and (" (" .. detail .. ")") or ""))

  broadcast(new_status)

  if on_change_callback then
    local ok_cb, cb_err = pcall(on_change_callback, new_status, old_status, detail)
    if not ok_cb then
      logger.warn("status", "on_change callback error: " .. tostring(cb_err))
    end
  end

  return true, nil
end

---Get the current status
---@return AgentStatus status
---@return string|nil detail
---@return number|nil changed_at
function M.get()
  return current_status, status_detail, last_changed_at
end

---Convenience setters for common transitions

---@param detail string|nil Optional context
function M.idle(detail)
  M.set("idle", detail)
end

---@param detail string|nil Optional context
function M.busy_with_overseer(detail)
  M.set("busy-with-overseer", detail)
end

---@param tool_name string|nil Name of the tool being executed
function M.busy_with_tool(tool_name)
  M.set("busy-with-tool", tool_name)
end

---@param agent_name string|nil Name of the agent being communicated with
function M.busy_with_agent(agent_name)
  M.set("busy-with-agent", agent_name)
end

function M.offline()
  M.set("offline", nil)
end

---Register a callback for status changes
---@param fn function|nil fn(new_status, old_status, detail)
function M.on_change(fn)
  on_change_callback = fn
end

---Get a summary table (useful for MCP tools and debugging)
---@return table
function M.summary()
  return {
    status = current_status,
    detail = status_detail,
    changed_at = last_changed_at,
  }
end

return M
