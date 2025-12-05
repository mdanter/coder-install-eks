### SSH Config Tweaks for Improved Reliability

Coder's default SSH config only sets minimal options:
```
ConnectTimeout=0
StrictHostKeyChecking=no
UserKnownHostsFile=/dev/null
LogLevel ERROR
```

#### Add Keep-Alive Settings

```bash
# Regenerate SSH config with reliability options:
coder config-ssh \
  -o "ServerAliveInterval=15" \
  -o "ServerAliveCountMax=4" \
  -o "TCPKeepAlive=yes"
```

Or manually edit `~/.ssh/config` within the Coder section:

```ssh-config
Host coder.* *.coder
    # Existing Coder options...
    
    # Send keep-alive every 15 seconds
    ServerAliveInterval 15
    
    # Disconnect after 4 missed keep-alives (~60s unresponsive)
    ServerAliveCountMax 4
    
    # Enable TCP-level keepalives
    TCPKeepAlive yes
    
    # Optional: faster initial connection timeout
    ConnectTimeout 30
```

#### What These Options Do

| Option | Purpose |
|--------|---------|
| `ServerAliveInterval 15` | Detects dead connections faster by sending keep-alive packets every 15s |
| `ServerAliveCountMax 4` | Terminates after 4 missed responses, allowing reconnection instead of hanging |
| `TCPKeepAlive yes` | OS-level keepalives to detect network failures |
| `ConnectTimeout 30` | Fail faster on initial connection if workspace is unreachable |

---

### Additional Recommendations

1. **Upgrade Coder to v2.26.2+** - Fixes the agent crash bug

2. **Update JetBrains Gateway Coder Plugin** to v1.2.5+
   ```
   registry.coder.com/modules/coder/jetbrains-gateway v1.2.5
   ```

3. **Consider JetBrains Toolbox** over Gateway if not air-gapped:
   ```
   registry.coder.com/modules/coder/jetbrains
   ```

4. **Check Network Stability**:
   ```bash
   coder netcheck
   ```
   Look for DERP relay latency and whether P2P connections establish.

5. **Activity Detection Note**: Keep-alive traffic counts as workspace activity, helping prevent unexpected auto-stop due to silent connection drops.
