---@brief WebSocket client for tmux adapter integration
---
--- Connects claudecode.nvim to the Gas Town tmux adapter for:
--- - Agent identification and presence
--- - Crew-to-crew messaging via WebSocket fast-path
--- - Agent lifecycle subscription
---
--- Uses existing server/frame.lua and server/utils.lua for RFC 6455 framing.
--- Lazy-initialized: call M.connect() explicitly or via :ClaudeCode adapter connect.

local frame = require("claudecode.server.frame")
local logger = require("claudecode.logger")
local utils = require("claudecode.server.utils")

local M = {}

-- Connection states
local STATE = {
  DISCONNECTED = "disconnected",
  CONNECTING = "connecting",
  HANDSHAKING = "handshaking",
  OPEN = "open",
  CLOSING = "closing",
}

---@class AdapterState
---@field state string Connection state
---@field tcp table|nil vim.loop TCP handle
---@field buffer string Incoming data buffer
---@field url string Adapter WebSocket URL
---@field agent_name string This agent's name for identification
---@field reconnect_timer table|nil Reconnect timer handle
---@field reconnect_delay number Current reconnect delay (ms)
---@field ping_timer table|nil Keepalive ping timer
---@field msg_id number Auto-incrementing message ID
---@field callbacks table Pending request callbacks by message ID
---@field on_message function|nil Handler for incoming messages
---@field on_agents function|nil Handler for agent lifecycle events
---@field on_connect function|nil Handler for successful connection
---@field on_disconnect function|nil Handler for disconnection

M.state = {
  state = STATE.DISCONNECTED,
  tcp = nil,
  buffer = "",
  agent_name = "",
  host = "127.0.0.1",
  port = 8080,
  auth_token = "",
  reconnect_timer = nil,
  reconnect_delay = 1000, -- Start at 1s, backoff to 30s
  ping_timer = nil,
  msg_id = 0,
  callbacks = {},
  on_message = nil,
  on_agents = nil,
  on_connect = nil,
  on_disconnect = nil,
}

-- Constants
local RECONNECT_MAX_DELAY = 30000
local PING_INTERVAL = 25000

---Generate next message ID
---@return string id
local function next_id()
  M.state.msg_id = M.state.msg_id + 1
  return tostring(M.state.msg_id)
end

---Create a masked WebSocket frame (client → server MUST be masked per RFC 6455)
---@param opcode number Frame opcode
---@param payload string Payload data
---@return string frame_data
local function create_masked_frame(opcode, payload)
  return frame.create_frame(opcode, payload, true, true)
end

---Send a JSON message over the WebSocket
---@param data table Message data
---@param callback function|nil Optional callback(response) for request/response
---@return boolean ok
---@return string|nil err
function M.send(data, callback)
  if M.state.state ~= STATE.OPEN then
    return false, "not connected (state: " .. M.state.state .. ")"
  end

  if not data.id then
    data.id = next_id()
  end

  if callback then
    M.state.callbacks[data.id] = callback
  end

  local ok_enc, json_str = pcall(vim.json.encode, data)
  if not ok_enc then
    return false, "JSON encode error: " .. tostring(json_str)
  end

  local ws_frame = create_masked_frame(frame.OPCODE.TEXT, json_str)

  local tcp = M.state.tcp
  if not tcp then
    return false, "no TCP handle"
  end

  tcp:write(ws_frame, function(err)
    if err then
      logger.error("adapter", "Write error: " .. tostring(err))
    end
  end)

  return true, nil
end

---Process incoming WebSocket frames from buffer
local function process_buffer()
  while #M.state.buffer >= 2 do
    local parsed, bytes = frame.parse_frame(M.state.buffer)
    if not parsed then
      break
    end

    M.state.buffer = M.state.buffer:sub(bytes + 1)

    if parsed.opcode == frame.OPCODE.TEXT then
      -- JSON message
      local ok_dec, msg = pcall(vim.json.decode, parsed.payload)
      if ok_dec and type(msg) == "table" then
        -- Check for pending callback
        if msg.id and M.state.callbacks[msg.id] then
          local cb = M.state.callbacks[msg.id]
          M.state.callbacks[msg.id] = nil
          vim.schedule(function()
            cb(msg)
          end)
        end

        -- Route by message type
        vim.schedule(function()
          if msg.type == "message" and M.state.on_message then
            M.state.on_message(msg)
          elseif msg.type == "agent-added" or msg.type == "agent-removed" or msg.type == "agent-updated" then
            if M.state.on_agents then
              M.state.on_agents(msg)
            end
          end
        end)
      else
        logger.debug("adapter", "Non-JSON frame: " .. parsed.payload:sub(1, 100))
      end
    elseif parsed.opcode == frame.OPCODE.PING then
      local pong = create_masked_frame(frame.OPCODE.PONG, parsed.payload)
      if M.state.tcp then
        M.state.tcp:write(pong)
      end
    elseif parsed.opcode == frame.OPCODE.CLOSE then
      logger.info("adapter", "Server sent close frame")
      M._handle_disconnect("server closed connection")
    end
  end
end

---Start the keepalive ping timer
local function start_ping_timer()
  if M.state.ping_timer then
    M.state.ping_timer:close()
  end

  M.state.ping_timer = vim.loop.new_timer()
  M.state.ping_timer:start(PING_INTERVAL, PING_INTERVAL, function()
    if M.state.state == STATE.OPEN and M.state.tcp then
      local ping = create_masked_frame(frame.OPCODE.PING, "")
      M.state.tcp:write(ping)
    end
  end)
end

---Handle disconnection and schedule reconnect
---@param reason string
function M._handle_disconnect(reason)
  local was_open = M.state.state == STATE.OPEN
  M.state.state = STATE.DISCONNECTED

  -- Cleanup TCP
  if M.state.tcp then
    pcall(function()
      M.state.tcp:read_stop()
    end)
    pcall(function()
      if not M.state.tcp:is_closing() then
        M.state.tcp:close()
      end
    end)
    M.state.tcp = nil
  end

  -- Cleanup ping timer
  if M.state.ping_timer then
    M.state.ping_timer:close()
    M.state.ping_timer = nil
  end

  -- Clear pending callbacks
  M.state.callbacks = {}
  M.state.buffer = ""

  if was_open then
    logger.warn("adapter", "Disconnected: " .. reason)
    vim.schedule(function()
      if M.state.on_disconnect then
        M.state.on_disconnect(reason)
      end
    end)
  end

  -- Schedule reconnect with backoff
  M._schedule_reconnect()
end

---Schedule a reconnect attempt with exponential backoff
function M._schedule_reconnect()
  if M.state.reconnect_timer then
    return -- Already scheduled
  end

  local delay = M.state.reconnect_delay
  logger.debug("adapter", "Reconnecting in " .. delay .. "ms")

  M.state.reconnect_timer = vim.loop.new_timer()
  M.state.reconnect_timer:start(delay, 0, function()
    M.state.reconnect_timer:close()
    M.state.reconnect_timer = nil

    -- Increase backoff for next attempt
    M.state.reconnect_delay = math.min(M.state.reconnect_delay * 2, RECONNECT_MAX_DELAY)

    vim.schedule(function()
      M._do_connect()
    end)
  end)
end

---Cancel reconnect timer
function M._cancel_reconnect()
  if M.state.reconnect_timer then
    M.state.reconnect_timer:close()
    M.state.reconnect_timer = nil
  end
end

---Perform the actual TCP connect + WebSocket handshake
function M._do_connect()
  if M.state.state ~= STATE.DISCONNECTED then
    return
  end

  local host = M.state.host
  local port = M.state.port
  local agent = M.state.agent_name
  local auth_token = M.state.auth_token

  M.state.state = STATE.CONNECTING
  M.state.buffer = ""

  local tcp = vim.loop.new_tcp()
  M.state.tcp = tcp

  tcp:connect(host, port, function(err)
    if err then
      logger.debug("adapter", "Connect failed: " .. tostring(err))
      vim.schedule(function()
        M.state.state = STATE.DISCONNECTED
        M.state.tcp = nil
        pcall(function()
          tcp:close()
        end)
        M._schedule_reconnect()
      end)
      return
    end

    -- Connected — send HTTP upgrade request
    M.state.state = STATE.HANDSHAKING

    local ws_key = utils.generate_websocket_key()
    local path = "/ws"
    if agent ~= "" then
      path = path .. "?agent=" .. agent
    end

    local request_lines = {
      "GET " .. path .. " HTTP/1.1",
      "Host: " .. host .. ":" .. port,
      "Upgrade: websocket",
      "Connection: Upgrade",
      "Sec-WebSocket-Key: " .. ws_key,
      "Sec-WebSocket-Version: 13",
    }
    if auth_token ~= "" then
      table.insert(request_lines, "Authorization: Bearer " .. auth_token)
    end
    table.insert(request_lines, "")
    table.insert(request_lines, "")
    local http_request = table.concat(request_lines, "\r\n")

    tcp:write(http_request, function(write_err)
      if write_err then
        logger.error("adapter", "Handshake write error: " .. tostring(write_err))
        vim.schedule(function()
          M._handle_disconnect("handshake write failed")
        end)
      end
    end)

    -- Start reading
    tcp:read_start(function(read_err, data)
      if read_err then
        vim.schedule(function()
          M._handle_disconnect("read error: " .. tostring(read_err))
        end)
        return
      end

      if data == nil then
        -- EOF
        vim.schedule(function()
          M._handle_disconnect("connection closed")
        end)
        return
      end

      if M.state.state == STATE.HANDSHAKING then
        M.state.buffer = M.state.buffer .. data

        -- Look for end of HTTP headers
        local header_end = M.state.buffer:find("\r\n\r\n")
        if not header_end then
          return
        end

        local response = M.state.buffer:sub(1, header_end + 3)
        local remaining = M.state.buffer:sub(header_end + 4)

        -- Validate 101 Switching Protocols
        if not response:match("^HTTP/1%.1 101") then
          local status_line = response:match("^([^\r\n]+)") or "unknown"
          logger.warn("adapter", "Handshake rejected: " .. status_line)
          vim.schedule(function()
            M._handle_disconnect("handshake rejected: " .. status_line)
          end)
          return
        end

        -- Validate Sec-WebSocket-Accept
        local server_accept = response:match("[Ss]ec%-[Ww]eb[Ss]ocket%-[Aa]ccept: ([^\r\n]+)")
        local expected_accept = utils.generate_accept_key(ws_key)
        if server_accept ~= expected_accept then
          logger.warn("adapter", "Sec-WebSocket-Accept mismatch")
          vim.schedule(function()
            M._handle_disconnect("accept key mismatch")
          end)
          return
        end

        -- Handshake complete!
        M.state.state = STATE.OPEN
        M.state.buffer = remaining
        M.state.reconnect_delay = 1000 -- Reset backoff on success

        logger.info("adapter", "Connected to tmux adapter at " .. host .. ":" .. port)

        -- Start ping timer
        start_ping_timer()

        vim.schedule(function()
          -- Send identify if we have an agent name (belt and suspenders with ?agent=)
          if agent ~= "" then
            M.send({ type = "identify", agent = agent })
          end

          -- Subscribe to agent lifecycle events
          M.send({ type = "subscribe-agents" })

          if M.state.on_connect then
            M.state.on_connect()
          end
        end)

        -- Process any remaining data
        if #M.state.buffer > 0 then
          process_buffer()
        end
      elseif M.state.state == STATE.OPEN then
        M.state.buffer = M.state.buffer .. data
        process_buffer()
      end
    end)
  end)
end

---Connect to the tmux adapter
---@param opts table|nil Options: { agent = string, url = string, on_message = fn, on_agents = fn, on_connect = fn, on_disconnect = fn }
function M.connect(opts)
  opts = opts or {}

  if M.state.state ~= STATE.DISCONNECTED then
    logger.debug("adapter", "Already connected or connecting (state: " .. M.state.state .. ")")
    return
  end

  -- Resolve agent identity from opts or environment.
  -- Prefer session-specific names (GT_SESSION, tmux session) over the generic
  -- GT_AGENT ("nvim-claude") so that the adapter mesh can route direct/broadcast
  -- messages to the correct crew member via WS instead of falling back to nudge queue.
  M.state.agent_name = opts.agent or vim.env.GT_SESSION or vim.env.GT_ROLE or vim.env.GT_AGENT or ""
  M.state.host = opts.host or "127.0.0.1"
  M.state.port = tonumber(opts.port or vim.env.GT_TMUX_ADAPTER_PORT or "8080") or 8080
  M.state.auth_token = opts.auth_token or vim.env.GT_TMUX_ADAPTER_TOKEN or ""

  -- Set handlers
  M.state.on_message = opts.on_message or M._default_on_message
  M.state.on_agents = opts.on_agents
  M.state.on_connect = opts.on_connect
  M.state.on_disconnect = opts.on_disconnect

  M._do_connect()
end

---Disconnect from the tmux adapter
function M.disconnect()
  M._cancel_reconnect()

  if M.state.state == STATE.OPEN and M.state.tcp then
    -- Send close frame
    local payload = string.char(math.floor(1000 / 256), 1000 % 256)
    local close_frame = create_masked_frame(frame.OPCODE.CLOSE, payload)
    M.state.tcp:write(close_frame)
  end

  M.state.state = STATE.DISCONNECTED

  if M.state.tcp then
    pcall(function()
      M.state.tcp:read_stop()
    end)
    pcall(function()
      if not M.state.tcp:is_closing() then
        M.state.tcp:close()
      end
    end)
    M.state.tcp = nil
  end

  if M.state.ping_timer then
    M.state.ping_timer:close()
    M.state.ping_timer = nil
  end

  M.state.callbacks = {}
  M.state.buffer = ""

  logger.info("adapter", "Disconnected from tmux adapter")
end

---Send a message to another agent via the adapter (context update mode)
---Arrives at recipient's on_message handler → MCP broadcast → Claude sees it as context
---@param to string Target agent name
---@param body string Message body
---@param callback function|nil Optional callback(response)
---@return boolean ok
---@return string|nil err
function M.send_message(to, body, callback)
  return M.send({
    type = "send-message",
    to = to,
    body = body,
  }, callback)
end

---Send a prompt directly to another agent's Claude session via the adapter
---Uses adapter's send-prompt endpoint which delivers via tmux to Claude's stdin
---This is the "nudge immediate" equivalent over WebSocket — interrupts the agent
---@param to string Target agent name
---@param prompt string The prompt text to inject
---@param callback function|nil Optional callback(response)
---@return boolean ok
---@return string|nil err
function M.send_prompt(to, prompt, callback)
  return M.send({
    type = "send-prompt",
    agent = to,
    prompt = prompt,
  }, callback)
end

---Deliver a prompt to another agent's nudge queue via the adapter (server-side queue write)
---More reliable than send_prompt (tmux send-keys) — uses the same queue as gt nudge --mode=queue
---@param to string Target agent name
---@param prompt string The prompt text
---@param priority string|nil "normal" (default) or "urgent"
---@param callback function|nil Optional callback(response)
---@return boolean ok
---@return string|nil err
function M.deliver_prompt(to, prompt, priority, callback)
  return M.send({
    type = "deliver-prompt",
    agent = to,
    prompt = prompt,
    priority = priority or "normal",
  }, callback)
end

---Subscribe to all message traffic (overseer observer mode)
---@param callback function|nil Optional callback(response)
---@return boolean ok
---@return string|nil err
function M.subscribe_messages(callback)
  return M.send({
    type = "subscribe-messages",
  }, callback)
end

---List agents via the adapter
---@param callback function|nil Optional callback(response)
---@return boolean ok
---@return string|nil err
function M.list_agents(callback)
  return M.send({
    type = "list-agents",
  }, callback)
end

---Report agent status to the adapter
---@param status string One of "idle", "mid-turn", "busy-with-overseer"
---@return boolean ok
---@return string|nil err
function M.report_status(status)
  return M.send({
    type = "report-status",
    status = status,
  })
end

---Check if connected to the adapter
---@return boolean
function M.is_connected()
  return M.state.state == STATE.OPEN
end

---Get current connection state
---@return string state
function M.get_state()
  return M.state.state
end

---Get the agent name this client identified as
---@return string
function M.get_agent_name()
  return M.state.agent_name
end

---Default on_message handler: routes by priority and writes to nudge queue
---Used when connect() is called without an on_message option
---@param msg table Incoming message with from, body, priority fields
function M._default_on_message(msg)
  local from = msg.from or "unknown"
  local body = msg.body or ""
  local priority = msg.priority or "normal"

  -- Route by priority:
  --   urgent  → vim.notify(WARN) + nudge queue
  --   normal  → vim.notify + nudge queue
  --   low     → vim.notify only (no Claude context cost)
  local prefix = priority == "urgent" and "[Gas Town URGENT] " or "[Gas Town] "
  local level = priority == "urgent" and vim.log.levels.WARN or vim.log.levels.INFO
  vim.notify(prefix .. from .. ": " .. body, level)

  if priority == "low" then
    return
  end

  -- Write to nudge queue — same format as gt nudge --mode=queue
  -- UserPromptSubmit hook (gt mail check --inject) drains automatically
  local town_root = vim.env.GT_TOWN_ROOT or vim.fn.expand("~/gt")
  local session = vim.env.GT_SESSION or vim.env.TMUX_SESSION or ""
  if session == "" then
    local handle = io.popen("tmux display-message -p '#S' 2>/dev/null")
    if handle then
      session = handle:read("*l") or ""
      handle:close()
    end
  end

  if session == "" then
    logger.warn("adapter", "Cannot determine session name for nudge queue")
    return
  end

  local safe_session = session:gsub("/", "_")
  local queue_dir = town_root .. "/.runtime/nudge_queue/" .. safe_session
  vim.fn.mkdir(queue_dir, "p")

  local timestamp_ns = tostring(vim.loop.hrtime())
  local random_hex = string.format("%08x", math.random(0, 0x7FFFFFFF))
  local filename = timestamp_ns .. "-" .. random_hex .. ".json"

  local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
  local ttl_seconds = priority == "urgent" and 7200 or 1800
  local expires = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() + ttl_seconds)

  local queue_entry = vim.json.encode({
    sender = from,
    message = body,
    priority = priority,
    timestamp = now,
    expires_at = expires,
  })

  local f = io.open(queue_dir .. "/" .. filename, "w")
  if f then
    f:write(queue_entry)
    f:close()
    logger.debug("adapter", "Queued ws message from " .. from .. " to nudge queue")
  else
    logger.warn("adapter", "Failed to write to nudge queue: " .. queue_dir)
  end
end

return M
