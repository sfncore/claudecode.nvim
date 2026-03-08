-- luacheck: globals expect
require("tests.busted_setup")

describe("Context Mode Winbar", function()
  local context_mode

  local function setup()
    package.loaded["claudecode.context_mode"] = nil
    package.loaded["claudecode.terminal"] = nil
    context_mode = require("claudecode.context_mode")
  end

  setup()

  describe("format_winbar", function()
    local sample_stats = {
      pid = 12345,
      session_minutes = 58.4,
      total_calls = 23,
      bytes_processed = 572800,
      bytes_saved = 323100,
      tokens_consumed = 63936,
      tokens_saved = 82706,
      savings_ratio = 2.3,
      reduction_pct = 56,
      updated_at = os.time() * 1000,
    }

    it("should format compact winbar", function()
      local result = context_mode.format_winbar(sample_stats, "compact")
      expect(result).to_be_string()
      expect(result).to_match("ctx:")
      expect(result).to_match("23 calls")
      expect(result).to_match("83k tok")
      expect(result).to_match("2.3x")
    end)

    it("should format full winbar", function()
      local result = context_mode.format_winbar(sample_stats, "full")
      expect(result).to_be_string()
      expect(result).to_match("ctx:")
      expect(result).to_match("23 calls")
      expect(result).to_match("559KB") -- 572800 bytes
      expect(result).to_match("316KB") -- 323100 bytes
      expect(result).to_match("83k tok")
      expect(result).to_match("2.3x")
      expect(result).to_match("56%%")
    end)

    it("should return empty string for nil stats", function()
      local result = context_mode.format_winbar(nil, "compact")
      expect(result).to_be("")
    end)

    it("should return empty string for stats without total_calls", function()
      local result = context_mode.format_winbar({}, "compact")
      expect(result).to_be("")
    end)

    it("should handle zero savings ratio", function()
      local stats = {
        total_calls = 1,
        tokens_saved = 0,
        savings_ratio = 0,
      }
      local result = context_mode.format_winbar(stats, "compact")
      expect(result).to_be_string()
      expect(result).to_match("1 calls")
      expect(result).to_match("0 tok")
    end)

    it("should handle large token counts", function()
      local stats = {
        total_calls = 100,
        tokens_saved = 1500000,
        savings_ratio = 5.2,
      }
      local result = context_mode.format_winbar(stats, "compact")
      expect(result).to_match("1.5m tok")
    end)
  end)

  describe("read_stats", function()
    local test_file = "/tmp/claudecode_test_stats.json"

    after_each(function()
      os.remove(test_file)
    end)

    it("should read valid JSON stats file", function()
      local f = io.open(test_file, "w")
      f:write('{"total_calls":5,"tokens_saved":1000,"savings_ratio":1.5,"updated_at":' .. (os.time() * 1000) .. "}\n")
      f:close()

      local stats = context_mode.read_stats(test_file)
      expect(stats).to_be_table()
      expect(stats.total_calls).to_be(5)
      expect(stats.tokens_saved).to_be(1000)
      expect(stats.savings_ratio).to_be(1.5)
    end)

    it("should return nil for missing file", function()
      local stats = context_mode.read_stats("/tmp/nonexistent_stats_file.json")
      expect(stats).to_be_nil()
    end)

    it("should return nil for empty file", function()
      local f = io.open(test_file, "w")
      f:write("")
      f:close()

      local stats = context_mode.read_stats(test_file)
      expect(stats).to_be_nil()
    end)

    it("should return nil for malformed JSON", function()
      local f = io.open(test_file, "w")
      f:write("not valid json{{{")
      f:close()

      local stats = context_mode.read_stats(test_file)
      expect(stats).to_be_nil()
    end)
  end)

  describe("get_terminal_win_id", function()
    it("should return nil when terminal module not available", function()
      -- With mock vim, terminal module won't have a real bufnr
      local win_id = context_mode.get_terminal_win_id()
      expect(win_id).to_be_nil()
    end)
  end)

  describe("lifecycle", function()
    it("should setup with disabled config without starting timer", function()
      context_mode.setup({ enabled = false, poll_interval_ms = 3000, format = "compact" })
      -- Should not error
      context_mode.stop()
    end)

    it("should setup and stop with enabled config", function()
      context_mode.setup({ enabled = true, poll_interval_ms = 3000, format = "compact" })
      -- Timer should be running
      context_mode.stop()
      -- Timer should be stopped, no errors
    end)

    it("should handle double stop gracefully", function()
      context_mode.setup({ enabled = true, poll_interval_ms = 3000, format = "compact" })
      context_mode.stop()
      context_mode.stop() -- Should not error
    end)

    it("should expose get_stats", function()
      expect(context_mode.get_stats).to_be_function()
      -- Before any polling, stats should be nil
      local stats = context_mode.get_stats()
      expect(stats).to_be_nil()
    end)
  end)
end)
