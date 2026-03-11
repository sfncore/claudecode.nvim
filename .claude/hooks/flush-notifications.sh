#!/usr/bin/env bash
# Claude Code Hook: Flush mesh event notifications as system-reminder output.
#
# Called on UserPromptSubmit to inject agent lifecycle events into Claude's context.
# Reads from notification spool written by adapter's _default_on_agents handler.
#
# Spool file: /tmp/crew-notifications-${GT_SESSION_ID:-cc}.spool

SPOOL="/tmp/crew-notifications-${GT_SESSION_ID:-cc}.spool"

# Nothing to do if spool doesn't exist or is empty
if [ ! -s "$SPOOL" ]; then
  exit 0
fi

# Atomically read and clear the spool
NOTIFICATIONS=$(cat "$SPOOL" 2>/dev/null)
: > "$SPOOL"

if [ -z "$NOTIFICATIONS" ]; then
  exit 0
fi

# Count and summarize (don't dump raw JSON)
ADDED=$(echo "$NOTIFICATIONS" | grep -c '"event":"agent-added"' || echo 0)
REMOVED=$(echo "$NOTIFICATIONS" | grep -c '"event":"agent-removed"' || echo 0)
UPDATED=$(echo "$NOTIFICATIONS" | grep -c '"event":"agent-updated"' || echo 0)

OUTPUT="Mesh events since last turn:"
[ "$ADDED" -gt 0 ] 2>/dev/null && OUTPUT="$OUTPUT $ADDED agent(s) joined."
[ "$REMOVED" -gt 0 ] 2>/dev/null && OUTPUT="$OUTPUT $REMOVED agent(s) left."
[ "$UPDATED" -gt 0 ] 2>/dev/null && OUTPUT="$OUTPUT $UPDATED status update(s)."

# Show recent status changes (last 5)
RECENT=$(echo "$NOTIFICATIONS" | grep '"event":"agent-updated"' | tail -5 | while read -r line; do
  AGENT=$(echo "$line" | python3 -c "import sys,json; m=json.loads(sys.stdin.read()); print(m.get('agent','?'))" 2>/dev/null)
  STATUS=$(echo "$line" | python3 -c "import sys,json; m=json.loads(sys.stdin.read()); print(m.get('status','?'))" 2>/dev/null)
  echo "  $AGENT -> $STATUS"
done)

if [ -n "$RECENT" ]; then
  OUTPUT="$OUTPUT
$RECENT"
fi

echo "$OUTPUT"
exit 0
