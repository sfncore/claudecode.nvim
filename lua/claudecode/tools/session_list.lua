--- Tool implementation for listing Gas Town polecat sessions.

local schema = {
  description = "List running Gas Town polecat sessions using gt CLI.",
  inputSchema = {
    type = "object",
    properties = {
      rig = {
        type = "string",
        description = "Filter by rig name (e.g., 'claudecode', 'gastown'). Omit for all rigs.",
      },
    },
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
  },
}

---Handles the sessionList tool invocation.
---@param params table The input parameters for the tool
---@return table MCP-compliant response with session list
local function handler(params)
  local args = { "gt", "session", "list", "--json" }

  if params.rig then
    table.insert(args, "--rig")
    table.insert(args, params.rig)
  end

  local cmd = table.concat(args, " ")
  local output = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    return {
      content = {
        {
          type = "text",
          text = vim.json.encode({
            success = false,
            error = output,
            exit_code = exit_code,
          }),
        },
      },
    }
  end

  local ok, data = pcall(vim.json.decode, output)
  if not ok then
    return {
      content = {
        {
          type = "text",
          text = vim.json.encode({
            success = false,
            error = "Failed to parse gt session list output: " .. tostring(data),
            raw = output,
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
          sessions = data,
          count = #data,
        }),
      },
    },
  }
end

return {
  name = "sessionList",
  schema = schema,
  handler = handler,
}
