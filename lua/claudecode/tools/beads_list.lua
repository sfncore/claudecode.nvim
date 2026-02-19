--- Tool implementation for listing Gas Town beads (issues).

local schema = {
  description = "List Gas Town beads (issues) using bd CLI. Returns JSON array of issues.",
  inputSchema = {
    type = "object",
    properties = {
      status = {
        type = "string",
        description = "Filter by status: open, in_progress, done, closed. Omit for all open.",
      },
      assignee = {
        type = "string",
        description = "Filter by assignee (e.g., 'claudecode/polecats/rust').",
      },
      label = {
        type = "string",
        description = "Filter by label.",
      },
      limit = {
        type = "number",
        description = "Maximum number of results (default 50).",
      },
    },
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
  },
}

---Handles the beadsList tool invocation.
---@param params table The input parameters for the tool
---@return table MCP-compliant response with beads list
local function handler(params)
  local args = { "bd", "list", "--json", "--no-pager" }

  if params.status then
    if params.status == "closed" or params.status == "done" then
      table.insert(args, "--all")
    end
  end

  if params.assignee then
    table.insert(args, "--assignee")
    table.insert(args, params.assignee)
  end

  if params.label then
    table.insert(args, "--label")
    table.insert(args, params.label)
  end

  if params.limit then
    table.insert(args, "--limit")
    table.insert(args, tostring(params.limit))
  end

  local cmd = table.concat(args, " ")
  local output = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    -- Return error info as text (non-fatal - bd may have warnings)
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

  -- Parse JSON output from bd
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

  return {
    content = {
      {
        type = "text",
        text = vim.json.encode({
          success = true,
          beads = data,
          count = #data,
        }),
      },
    },
  }
end

return {
  name = "beadsList",
  schema = schema,
  handler = handler,
}
