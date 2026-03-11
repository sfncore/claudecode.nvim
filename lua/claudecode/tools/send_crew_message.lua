--- Tool implementation for sending messages to crew members via the WebSocket mesh.

local schema = {
  description = "Send a message to another crew member via the WebSocket mesh. Uses the adapter's existing connection instead of opening new WebSocket connections.",
  inputSchema = {
    type = "object",
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
    required = { "to", "body" },
    properties = {
      to = {
        type = "string",
        description = "Target agent name (e.g., 'ta-crew-timmy', 'cm-crew-charlie')",
      },
      body = {
        type = "string",
        description = "Message text to send",
      },
      priority = {
        type = "string",
        enum = { "urgent", "normal", "low" },
        description = "Message priority (default: normal)",
      },
    },
  },
}

---@param params table { to: string, body: string, priority?: string }
---@return table MCP-compliant response
local function handler(params)
  local to = params.to
  local body = params.body
  local priority = params.priority or "normal"

  if not to or to == "" then
    error({ code = -32602, message = "Missing required parameter: to" })
  end

  if not body or body == "" then
    error({ code = -32602, message = "Missing required parameter: body" })
  end

  local adapter = require("claudecode.adapter")

  if not adapter.is_connected() then
    return {
      content = {
        {
          type = "text",
          text = vim.json.encode({
            success = false,
            error = "Not connected to the crew mesh. Adapter is disconnected.",
          }),
        },
      },
    }
  end

  -- Update status to busy-with-agent while sending
  local status_ok, status_mod = pcall(require, "claudecode.status")
  if status_ok then
    status_mod.busy_with_agent(to)
  end

  local ok, err = adapter.send({
    type = "send-message",
    to = to,
    body = body,
    priority = priority,
  })

  -- Restore idle status after sending
  if status_ok then
    status_mod.idle()
  end

  if not ok then
    return {
      content = {
        {
          type = "text",
          text = vim.json.encode({
            success = false,
            error = "Failed to send message: " .. tostring(err),
          }),
        },
      },
    }
  end

  return {
    content = {
      {
        type = "text",
        text = vim.json.encode({
          success = true,
          to = to,
          priority = priority,
          message = "Message sent to " .. to,
        }),
      },
    },
  }
end

return {
  name = "sendCrewMessage",
  schema = schema,
  handler = handler,
}
