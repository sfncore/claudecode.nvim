--- Tool implementation for viewing Gas Town triage (ready work) in a buffer.

local schema = {
  description = "View Gas Town triage — open issues ready to be worked (no blockers) — displayed in a Neovim buffer.",
  inputSchema = {
    type = "object",
    properties = {
      rig = {
        type = "string",
        description = "Filter by rig name (e.g., 'claudecode', 'gastown'). Omit for all rigs.",
      },
      assignee = {
        type = "string",
        description = "Filter by assignee.",
      },
    },
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
  },
}

---Handles the triageView tool invocation.
---Fetches ready work and opens it in a Neovim scratch buffer.
---@param params table The input parameters for the tool
---@return table MCP-compliant response
local function handler(params)
  local args = { "gt", "ready", "--json" }

  if params.rig then
    table.insert(args, "--rig=" .. params.rig)
  end

  local cmd = table.concat(args, " ")
  local output = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  -- gt ready --json returns { sources: [{name, issues: [...]}, ...], summary: ..., town_root: ... }
  local items = {}
  if exit_code == 0 then
    local ok, data = pcall(vim.json.decode, output)
    if ok and type(data) == "table" then
      if data.sources then
        -- Flatten issues from all sources
        for _, source in ipairs(data.sources) do
          if source.issues then
            for _, issue in ipairs(source.issues) do
              issue.rig = source.name
              table.insert(items, issue)
            end
          end
        end
      elseif #data > 0 then
        -- Fallback: flat array format
        items = data
      end
    end
  end

  -- Also get bd ready for local rig
  local bd_args = { "bd", "ready", "--json" }
  if params.assignee then
    table.insert(bd_args, "--assignee")
    table.insert(bd_args, params.assignee)
  end

  local bd_output = vim.fn.system(table.concat(bd_args, " "))
  local bd_items = {}
  if vim.v.shell_error == 0 then
    local ok, data = pcall(vim.json.decode, bd_output)
    if ok and type(data) == "table" then
      bd_items = data
    end
  end

  -- Build display lines
  local lines = { "# Gas Town Triage — Ready Work", "" }

  if #items > 0 then
    table.insert(lines, "## Town-wide Ready")
    for _, item in ipairs(items) do
      local line = string.format("  [%s] %s — %s", item.id or "?", item.title or "?", item.rig or "?")
      table.insert(lines, line)
    end
    table.insert(lines, "")
  end

  if #bd_items > 0 then
    table.insert(lines, "## Local Rig Ready")
    for _, item in ipairs(bd_items) do
      local line = string.format("  [%s] %s", item.id or "?", item.title or "?")
      if item.assignee then
        line = line .. " (@" .. item.assignee .. ")"
      end
      table.insert(lines, line)
    end
    table.insert(lines, "")
  end

  if #items == 0 and #bd_items == 0 then
    table.insert(lines, "No ready work found.")
  end

  -- Open a scratch buffer with the triage view
  vim.schedule(function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    vim.api.nvim_buf_set_name(bufnr, "GasTown Triage")

    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, bufnr)
  end)

  return {
    content = {
      {
        type = "text",
        text = vim.json.encode({
          success = true,
          town_items = #items,
          local_items = #bd_items,
          total = #items + #bd_items,
          message = "Triage view opened in buffer",
        }),
      },
    },
  }
end

return {
  name = "triageView",
  schema = schema,
  handler = handler,
}
