--- Tool implementation for updating a Gas Town bead (issue).

local schema = {
  description = "Update a Gas Town bead (issue) using bd CLI. Can change status, description, assignee, priority, or labels.",
  inputSchema = {
    type = "object",
    properties = {
      id = {
        type = "string",
        description = "Bead ID to update (e.g., 'cl-c3s').",
      },
      status = {
        type = "string",
        description = "New status: open, in_progress, done, closed.",
      },
      description = {
        type = "string",
        description = "New description text.",
      },
      assignee = {
        type = "string",
        description = "New assignee.",
      },
      priority = {
        type = "string",
        description = "New priority: P0, P1, P2, P3, P4.",
      },
      add_label = {
        type = "string",
        description = "Label to add.",
      },
      remove_label = {
        type = "string",
        description = "Label to remove.",
      },
    },
    required = { "id" },
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
  },
}

---Handles the beadsUpdate tool invocation.
---@param params table The input parameters for the tool
---@return table MCP-compliant response with update result
local function handler(params)
  if not params.id or params.id == "" then
    error({ code = -32602, message = "Invalid params", data = "Missing id parameter" })
  end

  local args = { "bd", "update", vim.fn.shellescape(params.id) }

  if params.status then
    table.insert(args, "--status")
    table.insert(args, vim.fn.shellescape(params.status))
  end

  if params.description then
    table.insert(args, "--description")
    table.insert(args, vim.fn.shellescape(params.description))
  end

  if params.assignee then
    table.insert(args, "--assignee")
    table.insert(args, vim.fn.shellescape(params.assignee))
  end

  if params.priority then
    table.insert(args, "--priority")
    table.insert(args, vim.fn.shellescape(params.priority))
  end

  if params.add_label then
    table.insert(args, "--add-label")
    table.insert(args, vim.fn.shellescape(params.add_label))
  end

  if params.remove_label then
    table.insert(args, "--remove-label")
    table.insert(args, vim.fn.shellescape(params.remove_label))
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
            id = params.id,
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
          id = params.id,
          message = output ~= "" and output or ("Updated " .. params.id),
        }),
      },
    },
  }
end

return {
  name = "beadsUpdate",
  schema = schema,
  handler = handler,
}
