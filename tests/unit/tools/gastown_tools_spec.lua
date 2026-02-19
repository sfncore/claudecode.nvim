require("tests.busted_setup") -- Ensure test helpers are loaded

-- Shared mock helpers
local function setup_vim_mocks(system_output, shell_error)
  _G.vim = _G.vim or {}
  _G.vim.fn = _G.vim.fn or {}
  _G.vim.json = _G.vim.json or {}
  _G.vim.v = _G.vim.v or {}
  _G.vim.api = _G.vim.api or {}
  _G.vim.schedule = _G.vim.schedule or function(fn)
    fn()
  end

  _G.vim.v.shell_error = shell_error or 0

  _G.vim.fn.system = spy.new(function(_cmd)
    return system_output or ""
  end)

  _G.vim.fn.shellescape = spy.new(function(s)
    return "'" .. s .. "'"
  end)

  _G.vim.fn.getcwd = spy.new(function()
    return "/mock/project"
  end)

  _G.vim.fn.expand = spy.new(function(s)
    return s:gsub("~", "/home/mock")
  end)

  _G.vim.fn.filereadable = spy.new(function(_path)
    return 0
  end)

  _G.vim.fn.readfile = spy.new(function(_path)
    return { "name = 'test-formula'", "description = 'A test formula'" }
  end)

  _G.vim.fn.getenv = spy.new(function(_name)
    return ""
  end)

  _G.vim.api.nvim_create_buf = spy.new(function(_listed, _scratch)
    return 1
  end)

  _G.vim.api.nvim_buf_set_lines = spy.new(function(_bufnr, _start, _end, _strict, _lines) end)

  _G.vim.api.nvim_buf_set_option = spy.new(function(_bufnr, _name, _value) end)

  _G.vim.api.nvim_buf_set_name = spy.new(function(_bufnr, _name) end)

  _G.vim.api.nvim_get_current_win = spy.new(function()
    return 1
  end)

  _G.vim.api.nvim_win_set_buf = spy.new(function(_win, _bufnr) end)

  _G.vim.split = _G.vim.split
    or spy.new(function(str, sep)
      local result = {}
      for s in str:gmatch("[^" .. sep .. "]+") do
        table.insert(result, s)
      end
      return result
    end)

  _G.vim.json.encode = spy.new(function(data, _opts)
    return require("tests.busted_setup").json_encode(data)
  end)

  _G.vim.json.decode = spy.new(function(str)
    return require("tests.busted_setup").json_decode(str)
  end)
end

local function teardown_tools(tool_names)
  for _, name in ipairs(tool_names) do
    package.loaded["claudecode.tools." .. name] = nil
  end
  _G.vim = nil
end

-- ============================================================
-- beadsList
-- ============================================================
describe("Tool: beadsList", function()
  local handler

  before_each(function()
    package.loaded["claudecode.tools.beads_list"] = nil
    local sample_json = require("tests.busted_setup").json_encode({
      { id = "cl-001", title = "First issue", status = "open" },
      { id = "cl-002", title = "Second issue", status = "in_progress" },
    })
    setup_vim_mocks(sample_json, 0)
    handler = require("claudecode.tools.beads_list").handler
  end)

  after_each(function()
    teardown_tools({ "beads_list" })
  end)

  it("should return a list of beads on success", function()
    local success, result = pcall(handler, {})
    expect(success).to_be_true()
    expect(result).to_be_table()
    expect(result.content).to_be_table()
    expect(result.content[1].type).to_be("text")

    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_true()
    expect(parsed.count).to_be(2)
  end)

  it("should pass --assignee flag when provided", function()
    local success, result = pcall(handler, { assignee = "claudecode/polecats/rust" })
    expect(success).to_be_true()
    assert.spy(_G.vim.fn.system).was_called()
    local cmd = _G.vim.fn.system.calls[1].refs[1]
    assert_contains(cmd, "--assignee")
  end)

  it("should pass --all when status is closed", function()
    local success, result = pcall(handler, { status = "closed" })
    expect(success).to_be_true()
    local cmd = _G.vim.fn.system.calls[1].refs[1]
    assert_contains(cmd, "--all")
  end)

  it("should return error info on non-zero exit code", function()
    _G.vim.v.shell_error = 1
    _G.vim.fn.system = spy.new(function(_cmd)
      return "bd: connection error"
    end)
    local success, result = pcall(handler, {})
    expect(success).to_be_true()
    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_false()
  end)
end)

-- ============================================================
-- beadsShow
-- ============================================================
describe("Tool: beadsShow", function()
  local handler

  before_each(function()
    package.loaded["claudecode.tools.beads_show"] = nil
    local sample_json = require("tests.busted_setup").json_encode({
      { id = "cl-001", title = "First issue", status = "open", description = "Some description" },
    })
    setup_vim_mocks(sample_json, 0)
    handler = require("claudecode.tools.beads_show").handler
  end)

  after_each(function()
    teardown_tools({ "beads_show" })
  end)

  it("should return bead details for a valid id", function()
    local success, result = pcall(handler, { id = "cl-001" })
    expect(success).to_be_true()
    expect(result.content[1].type).to_be("text")
    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_true()
    expect(parsed.bead).to_be_table()
    expect(parsed.bead.id).to_be("cl-001")
  end)

  it("should error when id is missing", function()
    local success, err = pcall(handler, {})
    expect(success).to_be_false()
  end)

  it("should error when id is empty string", function()
    local success, err = pcall(handler, { id = "" })
    expect(success).to_be_false()
  end)

  it("should return error info on non-zero exit code", function()
    _G.vim.v.shell_error = 1
    _G.vim.fn.system = spy.new(function(_cmd)
      return "not found"
    end)
    local success, result = pcall(handler, { id = "cl-999" })
    expect(success).to_be_true()
    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_false()
  end)
end)

-- ============================================================
-- beadsUpdate
-- ============================================================
describe("Tool: beadsUpdate", function()
  local handler

  before_each(function()
    package.loaded["claudecode.tools.beads_update"] = nil
    setup_vim_mocks("Updated cl-001", 0)
    handler = require("claudecode.tools.beads_update").handler
  end)

  after_each(function()
    teardown_tools({ "beads_update" })
  end)

  it("should succeed with only id provided", function()
    local success, result = pcall(handler, { id = "cl-001" })
    expect(success).to_be_true()
    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_true()
    expect(parsed.id).to_be("cl-001")
  end)

  it("should include --status flag when provided", function()
    local success, result = pcall(handler, { id = "cl-001", status = "done" })
    expect(success).to_be_true()
    local cmd = _G.vim.fn.system.calls[1].refs[1]
    assert_contains(cmd, "--status")
  end)

  it("should include --description flag when provided", function()
    local success, result = pcall(handler, { id = "cl-001", description = "New description" })
    expect(success).to_be_true()
    local cmd = _G.vim.fn.system.calls[1].refs[1]
    assert_contains(cmd, "--description")
  end)

  it("should error when id is missing", function()
    local success, err = pcall(handler, {})
    expect(success).to_be_false()
  end)

  it("should return error info on non-zero exit code", function()
    _G.vim.v.shell_error = 1
    _G.vim.fn.system = spy.new(function(_cmd)
      return "update failed"
    end)
    local success, result = pcall(handler, { id = "cl-001", status = "done" })
    expect(success).to_be_true()
    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_false()
  end)
end)

-- ============================================================
-- formulaList
-- ============================================================
describe("Tool: formulaList", function()
  local handler

  before_each(function()
    package.loaded["claudecode.tools.formula_list"] = nil
    local sample_json = require("tests.busted_setup").json_encode({
      { name = "agent-validation", type = "workflow", steps = 7 },
      { name = "mol-deacon-patrol", type = "workflow", steps = 5 },
    })
    setup_vim_mocks(sample_json, 0)
    handler = require("claudecode.tools.formula_list").handler
  end)

  after_each(function()
    teardown_tools({ "formula_list" })
  end)

  it("should return list of formulas on success", function()
    local success, result = pcall(handler, {})
    expect(success).to_be_true()
    expect(result.content[1].type).to_be("text")
    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_true()
    expect(parsed.count).to_be(2)
  end)

  it("should call gt formula list --json", function()
    local success, result = pcall(handler, {})
    expect(success).to_be_true()
    local cmd = _G.vim.fn.system.calls[1].refs[1]
    assert_contains(cmd, "gt formula list")
    assert_contains(cmd, "--json")
  end)

  it("should return error info on non-zero exit code", function()
    _G.vim.v.shell_error = 1
    _G.vim.fn.system = spy.new(function(_cmd)
      return "Dolt server unreachable"
    end)
    local success, result = pcall(handler, {})
    expect(success).to_be_true()
    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_false()
  end)
end)

-- ============================================================
-- formulaRead
-- ============================================================
describe("Tool: formulaRead", function()
  local handler

  before_each(function()
    package.loaded["claudecode.tools.formula_read"] = nil
    setup_vim_mocks("", 0)
    handler = require("claudecode.tools.formula_read").handler
  end)

  after_each(function()
    teardown_tools({ "formula_read" })
  end)

  it("should return formula content when file is found", function()
    -- Make filereadable return 1 for the expected path
    _G.vim.fn.filereadable = spy.new(function(_path)
      if _path:find("agent-validation") then
        return 1
      end
      return 0
    end)

    local success, result = pcall(handler, { name = "agent-validation" })
    expect(success).to_be_true()
    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_true()
    expect(parsed.name).to_be("agent-validation")
    expect(parsed.content).to_be_string()
  end)

  it("should return not-found when formula does not exist", function()
    _G.vim.fn.filereadable = spy.new(function(_path)
      return 0
    end)
    local success, result = pcall(handler, { name = "nonexistent-formula" })
    expect(success).to_be_true()
    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_false()
    assert_contains(parsed.error, "not found")
  end)

  it("should error when name is missing", function()
    local success, err = pcall(handler, {})
    expect(success).to_be_false()
  end)
end)

-- ============================================================
-- triageView
-- ============================================================
describe("Tool: triageView", function()
  local handler

  before_each(function()
    package.loaded["claudecode.tools.triage_view"] = nil
    -- gt ready --json returns {sources: [{name, issues: [...]}, ...], summary: ..., town_root: ...}
    local sample_json = require("tests.busted_setup").json_encode({
      sources = {
        {
          name = "gastown",
          issues = {
            { id = "hq-001", title = "Ready town work" },
          },
        },
      },
      summary = { total = 1 },
      town_root = "/mock/gt",
    })
    setup_vim_mocks(sample_json, 0)
    handler = require("claudecode.tools.triage_view").handler
  end)

  after_each(function()
    teardown_tools({ "triage_view" })
  end)

  it("should return success and open a buffer", function()
    local success, result = pcall(handler, {})
    expect(success).to_be_true()
    expect(result.content[1].type).to_be("text")
    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_true()
    expect(parsed.message).to_be_string()
  end)

  it("should pass --rig flag when provided", function()
    local success, result = pcall(handler, { rig = "claudecode" })
    expect(success).to_be_true()
    -- gt ready is called first
    local cmd = _G.vim.fn.system.calls[1].refs[1]
    assert_contains(cmd, "--rig=claudecode")
  end)

  it("should handle empty triage gracefully", function()
    _G.vim.fn.system = spy.new(function(_cmd)
      return require("tests.busted_setup").json_encode({ sources = {}, summary = {}, town_root = "" })
    end)
    local success, result = pcall(handler, {})
    expect(success).to_be_true()
    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_true()
  end)
end)

-- ============================================================
-- sessionList
-- ============================================================
describe("Tool: sessionList", function()
  local handler

  before_each(function()
    package.loaded["claudecode.tools.session_list"] = nil
    local sample_json = require("tests.busted_setup").json_encode({
      { rig = "claudecode", polecat = "rust", session_id = "cl-rust", running = true },
      { rig = "claudecode", polecat = "witness", session_id = "cl-witness", running = true },
    })
    setup_vim_mocks(sample_json, 0)
    handler = require("claudecode.tools.session_list").handler
  end)

  after_each(function()
    teardown_tools({ "session_list" })
  end)

  it("should return session list on success", function()
    local success, result = pcall(handler, {})
    expect(success).to_be_true()
    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_true()
    expect(parsed.count).to_be(2)
  end)

  it("should pass --rig flag when provided", function()
    local success, result = pcall(handler, { rig = "claudecode" })
    expect(success).to_be_true()
    local cmd = _G.vim.fn.system.calls[1].refs[1]
    assert_contains(cmd, "--rig")
    assert_contains(cmd, "claudecode")
  end)

  it("should return error info on non-zero exit code", function()
    _G.vim.v.shell_error = 1
    _G.vim.fn.system = spy.new(function(_cmd)
      return "no sessions found"
    end)
    local success, result = pcall(handler, {})
    expect(success).to_be_true()
    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_false()
  end)
end)

-- ============================================================
-- sessionRead
-- ============================================================
describe("Tool: sessionRead", function()
  local handler

  before_each(function()
    package.loaded["claudecode.tools.session_read"] = nil
    setup_vim_mocks("session output line 1\nsession output line 2\n", 0)
    handler = require("claudecode.tools.session_read").handler
  end)

  after_each(function()
    teardown_tools({ "session_read" })
  end)

  it("should return session output on success", function()
    local success, result = pcall(handler, { session = "cl-rust" })
    expect(success).to_be_true()
    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_true()
    expect(parsed.session).to_be("cl-rust")
    expect(parsed.output).to_be_string()
  end)

  it("should pass -n flag when lines is provided", function()
    local success, result = pcall(handler, { session = "cl-rust", lines = 50 })
    expect(success).to_be_true()
    local cmd = _G.vim.fn.system.calls[1].refs[1]
    assert_contains(cmd, "-n")
    assert_contains(cmd, "50")
  end)

  it("should error when session is missing", function()
    local success, err = pcall(handler, {})
    expect(success).to_be_false()
  end)

  it("should error when session is empty string", function()
    local success, err = pcall(handler, { session = "" })
    expect(success).to_be_false()
  end)

  it("should return error info on non-zero exit code", function()
    _G.vim.v.shell_error = 1
    _G.vim.fn.system = spy.new(function(_cmd)
      return "session not found"
    end)
    local success, result = pcall(handler, { session = "cl-nonexistent" })
    expect(success).to_be_true()
    local parsed = require("tests.busted_setup").json_decode(result.content[1].text)
    expect(parsed.success).to_be_false()
  end)
end)

-- ============================================================
-- Tool registration in init.lua
-- ============================================================
describe("Gas Town tool registration", function()
  local tools_module

  before_each(function()
    package.loaded["claudecode.tools"] = nil
    package.loaded["claudecode.tools.beads_list"] = nil
    package.loaded["claudecode.tools.beads_show"] = nil
    package.loaded["claudecode.tools.beads_update"] = nil
    package.loaded["claudecode.tools.formula_list"] = nil
    package.loaded["claudecode.tools.formula_read"] = nil
    package.loaded["claudecode.tools.triage_view"] = nil
    package.loaded["claudecode.tools.session_list"] = nil
    package.loaded["claudecode.tools.session_read"] = nil

    -- Also clear all other tool dependencies
    local other_tools = {
      "open_file",
      "get_current_selection",
      "get_open_editors",
      "open_diff",
      "get_latest_selection",
      "close_all_diff_tabs",
      "get_diagnostics",
      "get_workspace_folders",
      "check_document_dirty",
      "save_document",
      "close_tab",
    }
    for _, t in ipairs(other_tools) do
      package.loaded["claudecode.tools." .. t] = nil
    end
    package.loaded["claudecode.logger"] = nil

    setup_vim_mocks("", 0)

    -- Mock logger
    package.loaded["claudecode.logger"] = {
      debug = function() end,
      info = function() end,
      warn = function() end,
      error = function() end,
    }

    -- Mock all standard tools with minimal structure
    local make_mock_tool = function(name)
      return { name = name, handler = function() end, schema = { description = name } }
    end
    local mock_tools = {
      "open_file",
      "get_current_selection",
      "get_open_editors",
      "open_diff",
      "get_latest_selection",
      "close_all_diff_tabs",
      "get_diagnostics",
      "get_workspace_folders",
      "check_document_dirty",
      "save_document",
    }
    for _, t in ipairs(mock_tools) do
      package.loaded["claudecode.tools." .. t] = make_mock_tool(t)
    end
    -- close_tab has no schema (internal tool)
    package.loaded["claudecode.tools.close_tab"] = { name = "close_tab", handler = function() end }
  end)

  after_each(function()
    _G.vim = nil
    package.loaded["claudecode.tools"] = nil
    package.loaded["claudecode.logger"] = nil
  end)

  it("should register all Gas Town wizard tools", function()
    tools_module = require("claudecode.tools")
    tools_module.register_all()

    local gt_tools = {
      "beadsList",
      "beadsShow",
      "beadsUpdate",
      "formulaList",
      "formulaRead",
      "triageView",
      "sessionList",
      "sessionRead",
    }

    for _, name in ipairs(gt_tools) do
      assert.is_not_nil(tools_module.tools[name], "Expected tool '" .. name .. "' to be registered")
    end
  end)

  it("should expose Gas Town tools via get_tool_list", function()
    tools_module = require("claudecode.tools")
    tools_module.register_all()

    local tool_list = tools_module.get_tool_list()
    local tool_names = {}
    for _, t in ipairs(tool_list) do
      tool_names[t.name] = true
    end

    local gt_tools = {
      "beadsList",
      "beadsShow",
      "beadsUpdate",
      "formulaList",
      "formulaRead",
      "triageView",
      "sessionList",
      "sessionRead",
    }

    for _, name in ipairs(gt_tools) do
      assert.is_true(tool_names[name] == true, "Expected tool '" .. name .. "' in MCP tool list")
    end
  end)
end)
