--- Tool implementation for querying the crew mesh agent status.

local schema = {
  description = "Get the current status of all agents on the crew mesh, or filter by specific agent or rig.",
  inputSchema = {
    type = "object",
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
    properties = {
      agent = {
        type = "string",
        description = "Filter to a specific agent name (e.g., 'ta-crew-timmy')",
      },
      rig = {
        type = "string",
        description = "Filter to agents in a specific rig (e.g., 'tmux_adapter', 'claudecode')",
      },
    },
  },
}

---@param params table { agent?: string, rig?: string }
---@return table MCP-compliant response
local function handler(params)
  params = params or {}
  local filter_agent = params.agent
  local filter_rig = params.rig

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

  -- Use a coroutine-based blocking call to get the agent list
  -- Since list_agents uses a callback, we need to handle this synchronously
  local result = nil
  local done = false

  adapter.list_agents(function(response)
    result = response
    done = true
  end)

  -- Wait for callback (with timeout)
  local start = vim.loop.now()
  while not done and (vim.loop.now() - start) < 3000 do
    vim.wait(50, function()
      return done
    end)
  end

  if not done then
    return {
      content = {
        {
          type = "text",
          text = vim.json.encode({
            success = false,
            error = "Timeout waiting for agent list from mesh",
          }),
        },
      },
    }
  end

  local agents = result and result.agents or {}

  -- Apply filters
  if filter_agent then
    local filtered = {}
    for _, agent in ipairs(agents) do
      if agent.name == filter_agent then
        table.insert(filtered, agent)
      end
    end
    agents = filtered
  elseif filter_rig then
    local filtered = {}
    for _, agent in ipairs(agents) do
      if agent.rig == filter_rig then
        table.insert(filtered, agent)
      end
    end
    agents = filtered
  end

  -- Include own status
  local self_status = nil
  local status_ok, status_mod = pcall(require, "claudecode.status")
  if status_ok then
    self_status = status_mod.summary()
  end

  return {
    content = {
      {
        type = "text",
        text = vim.json.encode({
          success = true,
          agents = agents,
          self_status = self_status,
          connected = true,
          agent_count = #agents,
        }, { indent = 2 }),
      },
    },
  }
end

return {
  name = "getMeshStatus",
  schema = schema,
  handler = handler,
}
