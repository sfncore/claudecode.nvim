--- Tool implementation for listing Gas Town formulas.

local schema = {
  description = "List available Gas Town formulas (workflow templates) using gt CLI.",
  inputSchema = {
    type = "object",
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
  },
}

---Handles the formulaList tool invocation.
---@param params table The input parameters for the tool
---@return table MCP-compliant response with formula list
local function handler(_params)
  local cmd = "gt formula list --json"
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
            error = "Failed to parse gt formula list output: " .. tostring(data),
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
          formulas = data,
          count = #data,
        }),
      },
    },
  }
end

return {
  name = "formulaList",
  schema = schema,
  handler = handler,
}
