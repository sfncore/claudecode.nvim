--- Tool implementation for showing Gas Town bead (issue) details.

local schema = {
  description = "Show details of a Gas Town bead (issue) using bd CLI.",
  inputSchema = {
    type = "object",
    properties = {
      id = {
        type = "string",
        description = "Bead ID to show (e.g., 'cl-c3s', 'cl-wisp-9xhq').",
      },
    },
    required = { "id" },
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
  },
}

---Handles the beadsShow tool invocation.
---@param params table The input parameters for the tool
---@return table MCP-compliant response with bead details
local function handler(params)
  if not params.id or params.id == "" then
    error({ code = -32602, message = "Invalid params", data = "Missing id parameter" })
  end

  local cmd = "bd show " .. vim.fn.shellescape(params.id) .. " --json"
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
            id = params.id,
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
            error = "Failed to parse bd output: " .. tostring(data),
            raw = output,
          }),
        },
      },
    }
  end

  -- bd show --json returns an array; unwrap single item
  local bead = (type(data) == "table" and data[1]) or data

  return {
    content = {
      {
        type = "text",
        text = vim.json.encode({
          success = true,
          bead = bead,
        }),
      },
    },
  }
end

return {
  name = "beadsShow",
  schema = schema,
  handler = handler,
}
