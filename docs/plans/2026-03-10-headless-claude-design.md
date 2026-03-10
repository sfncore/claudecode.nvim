# Headless Claude: Native Neovim Renderer

**Date:** 2026-03-10
**Status:** Draft
**Scope:** claudecode.nvim

## Problem

Claude Code's TUI (React-based terminal UI) consumes significant resources. In
multi-agent Gas Town setups with 7+ agents, each running a full TUI in a terminal
buffer, the overhead adds up. The TUI rendering is wasted work when no human is
watching most of those terminals.

## Solution

Add a `"headless"` terminal provider to claudecode.nvim that runs Claude CLI
without the TUI. Instead of `vim.fn.termopen` rendering a terminal buffer, use
`vim.fn.jobstart` with `--output-format stream-json` to get structured JSON
output, then render the conversation natively in a Neovim buffer.

## Design

### 1. Process Model

The headless provider launches Claude CLI via `vim.fn.jobstart`:

```
claude --print --output-format stream-json --verbose --input-format text
```

- No terminal buffer — Claude runs as a background job
- stdout delivers NDJSON (newline-delimited JSON), parsed by Lua
- stdin accepts plain text prompts via `vim.fn.chansend()`
- stderr captured for error reporting
- The existing MCP WebSocket server still starts — Claude CLI discovers it via
  lockfile and connects back for tool execution (openFile, getSelection, etc.)

The process lifecycle is identical to the current terminal provider: starts on
open, stays alive for multi-turn conversation, closes on close.

### 2. Stream-JSON Parser

Module: `lua/claudecode/headless/parser.lua`

The stdout callback receives raw lines. Each line is a JSON object with a `type`
field:

| Type | Subtype | Content |
|------|---------|---------|
| `system` | `init` | Session metadata: model, tools, MCP servers, skills |
| `assistant` | `text` | Assistant message content |
| `assistant` | `thinking` | Thinking/reasoning blocks |
| `tool_use` | — | Tool name, parameters, tool_use_id |
| `tool_result` | — | Tool output, tool_use_id reference |
| `hook_started` | — | Hook name, hook_id |
| `hook_response` | — | Hook result, hook_id |
| `result` | — | Final message on session completion |

The parser does one thing: `vim.json.decode` each line and emit a structured
event to the renderer. No rendering logic in the parser.

For partial messages (`--include-partial-messages`), the parser tracks message
IDs and emits `update` events so the renderer can replace content in-place.

Malformed lines that fail decode are logged at WARN and skipped. A `[parse error]`
indicator appears in the buffer.

### 3. Buffer Renderer

Module: `lua/claudecode/headless/renderer.lua`

A regular Neovim buffer (not a terminal buffer) displays the conversation:

```
── Assistant ──────────────────────────
The rendered markdown text with syntax
highlighting via treesitter markdown.

── Thinking ─────────────────────────── (foldable)
Internal reasoning shown in dimmed highlight...

── Tool: Bash ─────────────────────────  (foldable)
Command: git status
─ Result ─
On branch main...
```

**Buffer properties:**
- `buftype=nofile`, `modifiable=false` (set modifiable only during writes)
- `filetype=claudecode` for custom syntax/highlight rules

**Rendering mechanics:**
- Each block tracked by extmarks (stable as content shifts)
- Thinking blocks and tool call/result pairs are foldable
- Streaming partial messages update the last extmark region in-place via
  `nvim_buf_set_lines` on the tracked range (no flicker)
- Assistant text gets markdown treesitter highlighting
- Code in tool results gets language-specific highlighting where detectable

**Scrolling behavior:**
- Auto-scroll to bottom as new content arrives
- If user scrolls up to review, stop auto-scrolling until they return to bottom
  (detected via `WinScrolled` autocmd)

**Window management:**
- Opens in the same split position as current terminal (respects `split_side`,
  `split_width_percentage` config)
- Toggle show/hide works identically to current terminal toggle

### 4. Integration

**Provider registration:** `"headless"` added as a valid `terminal.provider`
option in `config.lua`. The `"auto"` selection order remains snacks → native.
Headless is explicit opt-in only until proven stable.

**MCP WebSocket server:** Unchanged. Starts on `setup()`. The headless Claude
process discovers it via lockfile and connects back. All existing tools work
without modification.

**Adapter WebSocket client:** Works independently of terminal provider. Status
mapping:
- `idle` — job running, no partial messages streaming
- `mid-turn` — partial messages actively streaming
- `busy-with-overseer` — user has the output buffer focused

**Selection tracking, diff, diagnostics:** Unchanged — these are MCP tool
handlers triggered by Claude CLI via WebSocket.

**Configuration:**

```lua
require("claudecode").setup({
  terminal = {
    provider = "headless",  -- opt-in (default remains "auto")
    split_side = "right",
    split_width_percentage = 0.4,
  },
})
```

### 5. What's NOT In Scope

- **Input handling changes** — prompts go via stdin, MCP WebSocket handles tool
  registration. No new input mechanism needed.
- **Approval prompts** — headless mode targets agent use with skip-permissions.
- **Hook rendering** — hooks are pre-session setup noise, not displayed.
- **Replacing existing providers** — terminal mode stays as the default and
  fallback until headless is proven.

## Open Questions

1. **Session resume:** Does `--resume <session-id>` work with `--print` mode?
   If so, we can reconnect to prior conversations after process restart.
2. **Partial messages flag:** Should `--include-partial-messages` be on by
   default for streaming UX, or configurable?
3. **Resource savings measurement:** Need to benchmark actual memory/CPU
   difference between TUI and headless to validate the premise.

## Prior Research

Research conducted 2026-03-09 (session f4545477):
- Confirmed `--print --output-format stream-json --verbose` produces NDJSON
- Captured 34KB sample output showing full session lifecycle
- `--setting-sources ""` bypasses hooks in headless, but may not be needed for
  long-lived sessions
- `CLAUDECODE` env var blocks nested sessions (not an issue here — this is
  primary, not nested)
- Native terminal provider (`terminal/native.lua`) provides the interface
  pattern to follow
