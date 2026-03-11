describe("claudecode.status", function()
  local status

  before_each(function()
    package.loaded["claudecode.status"] = nil
    package.loaded["claudecode.adapter"] = nil
    package.loaded["claudecode.logger"] = nil

    -- Mock logger
    package.loaded["claudecode.logger"] = {
      debug = function() end,
      info = function() end,
      warn = function() end,
      error = function() end,
    }

    -- Mock adapter (not connected by default)
    package.loaded["claudecode.adapter"] = {
      is_connected = function()
        return false
      end,
      report_status = function() end,
    }

    status = require("claudecode.status")
  end)

  describe("initial state", function()
    it("starts as offline", function()
      local s, detail, changed_at = status.get()
      assert.equals("offline", s)
      assert.is_nil(detail)
      assert.is_nil(changed_at)
    end)
  end)

  describe("set()", function()
    it("accepts valid statuses", function()
      local ok, err = status.set("idle")
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals("idle", status.get())
    end)

    it("rejects invalid statuses", function()
      local ok, err = status.set("dancing")
      assert.is_false(ok)
      assert.matches("invalid status", err)
      assert.equals("offline", status.get())
    end)

    it("stores detail", function()
      status.set("busy-with-tool", "Bash")
      local s, detail = status.get()
      assert.equals("busy-with-tool", s)
      assert.equals("Bash", detail)
    end)

    it("records changed_at timestamp", function()
      status.set("idle")
      local _, _, changed_at = status.get()
      assert.is_not_nil(changed_at)
      assert.is_number(changed_at)
    end)

    it("skips duplicate status+detail", function()
      local callback_count = 0
      status.on_change(function()
        callback_count = callback_count + 1
      end)

      status.set("idle", "test")
      status.set("idle", "test") -- same, should skip
      assert.equals(1, callback_count)
    end)

    it("does not skip same status with different detail", function()
      local callback_count = 0
      status.on_change(function()
        callback_count = callback_count + 1
      end)

      status.set("busy-with-tool", "Bash")
      status.set("busy-with-tool", "Read")
      assert.equals(2, callback_count)
    end)
  end)

  describe("convenience setters", function()
    it("idle()", function()
      status.idle("test")
      assert.equals("idle", status.get())
    end)

    it("busy_with_overseer()", function()
      status.busy_with_overseer()
      assert.equals("busy-with-overseer", status.get())
    end)

    it("busy_with_tool()", function()
      status.busy_with_tool("Edit")
      local s, detail = status.get()
      assert.equals("busy-with-tool", s)
      assert.equals("Edit", detail)
    end)

    it("busy_with_agent()", function()
      status.busy_with_agent("ta-crew-timmy")
      local s, detail = status.get()
      assert.equals("busy-with-agent", s)
      assert.equals("ta-crew-timmy", detail)
    end)

    it("offline()", function()
      status.idle()
      status.offline()
      assert.equals("offline", status.get())
    end)
  end)

  describe("on_change callback", function()
    it("fires with old and new status", function()
      local captured = {}
      status.on_change(function(new_s, old_s, detail)
        captured = { new = new_s, old = old_s, detail = detail }
      end)

      status.set("idle")
      assert.equals("idle", captured.new)
      assert.equals("offline", captured.old)

      status.set("busy-with-tool", "Bash")
      assert.equals("busy-with-tool", captured.new)
      assert.equals("idle", captured.old)
      assert.equals("Bash", captured.detail)
    end)

    it("handles callback errors gracefully", function()
      status.on_change(function()
        error("callback boom")
      end)

      -- Should not propagate the error
      local ok, err = status.set("idle")
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals("idle", status.get())
    end)
  end)

  describe("summary()", function()
    it("returns status table", function()
      status.set("busy-with-overseer", "typing")
      local s = status.summary()
      assert.equals("busy-with-overseer", s.status)
      assert.equals("typing", s.detail)
      assert.is_not_nil(s.changed_at)
    end)
  end)

  describe("mesh broadcast", function()
    it("calls adapter.report_status when connected", function()
      local reported = nil
      package.loaded["claudecode.adapter"] = {
        is_connected = function()
          return true
        end,
        report_status = function(s)
          reported = s
        end,
      }

      -- Reload status to pick up new adapter mock
      package.loaded["claudecode.status"] = nil
      status = require("claudecode.status")

      status.set("idle")
      assert.equals("idle", reported)
    end)

    it("does not crash when adapter disconnected", function()
      status.set("idle") -- adapter mock returns is_connected=false
      assert.equals("idle", status.get())
    end)
  end)
end)
