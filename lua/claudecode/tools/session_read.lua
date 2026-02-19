--- Tool implementation for reading Gas Town polecat session output.

local schema = {
  description = "Read recent output from a Gas Town polecat session using gt session capture.",
  inputSchema = {
    type = "object",
    properties = {
      session = {
        type = "string",
        description = "Session ID or rig/polecat path (e.g., 'cl-rust', 'claudecode/polecats/rust').",
      },
      lines = {
        type = "number",
        description = "Number of recent lines to capture (default 100).",
      },
    },
    required = { "session" },
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
  },
}

---Handles the sessionRead tool invocation.
---@param params table The input parameters for the tool
---@return table MCP-compliant response with session output
local function handler(params)
  if not params.session or params.session == "" then
    error({ code = -32602, message = "Invalid params", data = "Missing session parameter" })
  end

  local args = { "gt", "session", "capture", vim.fn.shellescape(params.session) }

  if params.lines then
    table.insert(args, "-n")
    table.insert(args, tostring(math.floor(params.lines)))
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
            session = params.session,
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
          session = params.session,
          output = output,
          lines_captured = #vim.split(output, "\n"),
        }),
      },
    },
  }
end

return {
  name = "sessionRead",
  schema = schema,
  handler = handler,
}
