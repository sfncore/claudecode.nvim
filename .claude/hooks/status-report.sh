#!/usr/bin/env bash
# Claude Code Hook: Report agent status to the crew mesh via tmux adapter.
#
# Called by PreToolUse, PostToolUse, UserPromptSubmit, SessionStart, and Stop hooks.
# Must complete in <100ms to avoid slowing Claude down.
#
# Environment variables from Claude Code:
#   CLAUDE_HOOK_EVENT    — Which hook fired (PreToolUse, PostToolUse, etc.)
#   CLAUDE_TOOL_NAME     — Tool name (PreToolUse/PostToolUse only)
#
# Uses the tmux adapter REST API for speed (no WS handshake overhead).

ADAPTER_URL="${GT_TMUX_ADAPTER_URL:-http://127.0.0.1:${GT_TMUX_ADAPTER_PORT:-8080}}"
AGENT_NAME="${GT_SESSION:-${GT_ROLE:-unknown}}"

# Derive status from hook event
case "${CLAUDE_HOOK_EVENT:-$1}" in
  PreToolUse)
    STATUS="busy-with-tool"
    ;;
  PostToolUse)
    STATUS="idle"
    ;;
  UserPromptSubmit)
    STATUS="busy-with-overseer"
    ;;
  SessionStart)
    STATUS="idle"
    ;;
  Stop)
    STATUS="offline"
    ;;
  *)
    # Called directly with status as argument
    STATUS="${1:-idle}"
    ;;
esac

# Resolve agent name to adapter format (claudecode/crew/cc -> cc-crew-cc)
ADAPTER_AGENT=$(echo "${AGENT_NAME}" | sed 's|/|-|g; s|^claudecode|cc|; s|^tmux_adapter|ta|; s|^context_mode|cm|; s|^sfgastown|st|; s|^nvimconfig|nv|; s|^gt_toolkit|gtk|; s|^graphene_frontend_v2|gf|')

# Fire-and-forget via adapter REST API (background curl, no wait)
curl -sf --max-time 1 -X POST "${ADAPTER_URL}/api/agents/${ADAPTER_AGENT}/status" \
  -H "Content-Type: application/json" \
  -d "{\"status\":\"${STATUS}\"}" \
  >/dev/null 2>&1 &

exit 0
