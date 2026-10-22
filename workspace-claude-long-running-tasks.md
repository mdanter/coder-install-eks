Coder decides a workspace is idle based on connections. A Claude CLI left running in the background doesn't count as activity, which is why the workspace can stop underneath it. You can fix that with a small keepalive that runs while Claude is working.

What counts as activity today (docs)
- Open VS Code, JetBrains, web terminal or SSH sessions. A session that's just sitting open still counts..
- An agent reporting a working status to Coder. This is how Coder's built-in agent integrations keep workspaces alive..
- Not counted: background processes, including the Claude CLI once you disconnect..

Each activity signal pushes the stop time out to now + the template's activity bump (default 1 hour). So all you need is something that signals regularly while Claude is busy and stops when it's done.

Recommended: a status loop inside the workspace, controlled by a flag file
This needs no user token and keeps working after your laptop sleeps or disconnects.


1. Add an app and a startup script to the template. The app gives the status reports something to attach to, and gives users a one-click Claude terminal:.
```
resource "coder_app" "claude" {
  agent_id     = coder_agent.main.id
  slug         = "claude"
  display_name = "Claude Code"
  command      = "claude"
}

resource "coder_script" "keepalive" {
  agent_id     = coder_agent.main.id
  display_name = "Claude keepalive"
  run_on_start = true
  script       = "nohup bash ${path.module}/keepalive.sh >/tmp/keepalive.log 2>&1 &"
}
```
Keep the nohup ... &. Without it, a script that loops forever leaves the workspace stuck in "starting".


2. keepalive.sh reports working every 5 minutes while the flag file exists and Claude is running:.
```
#!/usr/bin/env bash
FLAG="$HOME/.coder-keepalive"
URL="${CODER_AGENT_URL%/}/api/v2/workspaceagents/me/app-status"
report() {
  curl -fsS -X PATCH "$URL" \
    -H "Coder-Session-Token: $CODER_AGENT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"app_slug\":\"claude\",\"state\":\"$1\",\"message\":\"$2\"}" >/dev/null
}
busy=0
while true; do
  if [ -f "$FLAG" ] && pgrep -f claude >/dev/null; then
    report working "Claude is running"; busy=1
  elif [ "$busy" = 1 ]; then
    rm -f "$FLAG"; report idle "Claude finished"; busy=0
  fi
  sleep 300
done
```
The pgrep check stops a crashed Claude from keeping the workspace alive forever. The final idle report gives one last bump, so you have time to come back and review the results.


3. Let Claude create and remove the flag itself, using hooks in ~/.claude/settings.json:.
```
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "touch ~/.coder-keepalive" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "rm -f ~/.coder-keepalive" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "rm -f ~/.coder-keepalive" }] }]
  }
}
```
For headless claude -p runs, a wrapper does the same job: touch ~/.coder-keepalive; claude -p "..."; rm -f ~/.coder-keepalive

Things to keep in mind
- The template's activity bump must be above 0, and the loop interval (5 minutes here) should be well under it..
- A workspace can never run past its max lifetime or the template's autostop requirement. Both ignore activity on purpose..
- The status updates also show on the workspace in the Coder dashboard..
- If one user runs several Claude sessions at once, the first one to finish removes the shared flag. You can avoid that with one flag file per session: the hooks receive a session_id on stdin..
- Try it on a test workspace first. Confirm that CODER_AGENT_URL and CODER_AGENT_TOKEN are set in the script's environment, and that pgrep -f claude matches how Claude shows up in your process list..
