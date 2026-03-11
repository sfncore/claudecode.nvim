#!/usr/bin/env bash
# Claude Code Hook: Flush queued crew mesh messages as system-reminder output.
#
# Called on UserPromptSubmit to inject pending mesh messages into Claude's context.
# Reads from a file-based spool that the adapter's on_message handler writes to.
# Messages are printed to stdout (which Claude Code captures as hook output).
#
# Spool file: /tmp/crew-messages-${GT_SESSION_ID:-cc}.spool
# Format: one JSON message per line: {"from":"...","body":"...","priority":"...","ts":"..."}

SPOOL="/tmp/crew-messages-${GT_SESSION_ID:-cc}.spool"

# Nothing to do if spool doesn't exist or is empty
if [ ! -s "$SPOOL" ]; then
  exit 0
fi

# Atomically read and clear the spool
MESSAGES=$(cat "$SPOOL" 2>/dev/null)
: > "$SPOOL"

if [ -z "$MESSAGES" ]; then
  exit 0
fi

# Format messages for system-reminder injection
# Sort urgent first (simple grep reorder)
URGENT=$(echo "$MESSAGES" | grep '"priority":"urgent"' || true)
NORMAL=$(echo "$MESSAGES" | grep -v '"priority":"urgent"' | grep -v '"priority":"low"' || true)
LOW=$(echo "$MESSAGES" | grep '"priority":"low"' || true)

OUTPUT=""
for line in $URGENT $NORMAL $LOW; do
  if [ -n "$line" ]; then
    FROM=$(echo "$line" | python3 -c "import sys,json; m=json.loads(sys.stdin.read()); print(m.get('from','unknown'))" 2>/dev/null || echo "unknown")
    BODY=$(echo "$line" | python3 -c "import sys,json; m=json.loads(sys.stdin.read()); print(m.get('body',''))" 2>/dev/null || echo "")
    PRIO=$(echo "$line" | python3 -c "import sys,json; m=json.loads(sys.stdin.read()); print(m.get('priority','normal'))" 2>/dev/null || echo "normal")
    PREFIX=""
    [ "$PRIO" = "urgent" ] && PREFIX="[URGENT] "
    OUTPUT="${OUTPUT}${PREFIX}[from ${FROM}] ${BODY}\n"
  fi
done

if [ -n "$OUTPUT" ]; then
  echo -e "$OUTPUT"
fi

exit 0
