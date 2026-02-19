--- Tool implementation for reading a Gas Town formula's content.

local schema = {
  description = "Read the content of a Gas Town formula (TOML file) by name.",
  inputSchema = {
    type = "object",
    properties = {
      name = {
        type = "string",
        description = "Formula name (e.g., 'agent-validation', 'mol-deacon-patrol').",
      },
    },
    required = { "name" },
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
  },
}

---Search formula directories for a formula file by name.
---@param name string The formula name (without extension)
---@return string|nil The file path if found
local function find_formula_path(name)
  local search_dirs = {
    vim.fn.getcwd() .. "/.beads/formulas",
    vim.fn.expand("~/.beads/formulas"),
  }

  -- Also try GT_ROOT if set
  local gt_root = vim.fn.getenv("GT_ROOT")
  if gt_root and gt_root ~= "" then
    table.insert(search_dirs, gt_root .. "/.beads/formulas")
  end

  local extensions = { ".formula.toml", ".formula.json" }

  for _, dir in ipairs(search_dirs) do
    for _, ext in ipairs(extensions) do
      local path = dir .. "/" .. name .. ext
      if vim.fn.filereadable(path) == 1 then
        return path
      end
    end
  end

  return nil
end

---Handles the formulaRead tool invocation.
---@param params table The input parameters for the tool
---@return table MCP-compliant response with formula content
local function handler(params)
  if not params.name or params.name == "" then
    error({ code = -32602, message = "Invalid params", data = "Missing name parameter" })
  end

  local path = find_formula_path(params.name)

  if not path then
    return {
      content = {
        {
          type = "text",
          text = vim.json.encode({
            success = false,
            error = "Formula not found: " .. params.name,
            name = params.name,
          }),
        },
      },
    }
  end

  local lines = vim.fn.readfile(path)
  local content = table.concat(lines, "\n")

  return {
    content = {
      {
        type = "text",
        text = vim.json.encode({
          success = true,
          name = params.name,
          path = path,
          content = content,
        }),
      },
    },
  }
end

return {
  name = "formulaRead",
  schema = schema,
  handler = handler,
}
