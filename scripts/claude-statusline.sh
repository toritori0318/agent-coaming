#!/bin/bash
# Claude Code status line for Agent Coaming.
# Writes only rate_limits (5h / 7d used percent and reset time) from the JSON Claude Code
# passes to the status line, into ~/Library/Application Support/Agent Coaming/claude-rate-limits.json.
# Everything else is dropped.
#
# settings.json:
#   "statusLine": { "type": "command", "command": "~/Library/Application\\ Support/Agent\\ Coaming/claude-statusline.sh" }
# If a status line already exists, pass that command as an argument and its display is kept:
#   "command": "~/Library/Application\\ Support/Agent\\ Coaming/claude-statusline.sh ~/.claude/statusline.sh"
# command is executed by a shell, so escape each space in the path with \ (\\ inside JSON).
set -u
input=$(cat)
dir="$HOME/Library/Application Support/Agent Coaming"
mkdir -p "$dir"
read -r -d '' extract <<'PY'
import json, os, sys, time
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
limits = data.get("rate_limits")
if not isinstance(limits, dict):
    sys.exit(0)  # Absent before the first response. Leave the previous file as it is.
kept = {}
for name in ("five_hour", "seven_day"):
    window = limits.get(name)
    if isinstance(window, dict):
        kept[name] = {k: window[k] for k in ("used_percentage", "resets_at") if k in window}
if not kept:
    sys.exit(0)  # Do not write when no window is present. Do not overwrite a valid file with an empty one.
path = sys.argv[1]
tmp = f"{path}.{os.getpid()}.tmp"  # Unique temp path so concurrent sessions do not collide.
with open(tmp, "w") as f:
    json.dump({"written_at": int(time.time()), "rate_limits": kept}, f)
os.replace(tmp, path)
PY
printf '%s' "$input" | /usr/bin/python3 -c "$extract" "$dir/claude-rate-limits.json"
if [ "$#" -gt 0 ]; then
  printf '%s' "$input" | "$@"
fi
