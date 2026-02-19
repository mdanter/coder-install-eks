## Upgrade Path: v2.23.1 → v2.26.6 → v2.30.1 (Helm/EKS + RDS)

---

### Phase 1: Preparation

**1. Record your current state**

```bash
# Get current Coder version
helm list -n <coder-namespace>

# Note your current helm values
helm get values coder -n <coder-namespace> -o yaml > coder-values-backup.yaml
```

**2. Get your RDS connection string**

You'll need this for `pg_dump`. Grab the host/port/db/user from your existing helm values or AWS console.

```bash
export PGHOST=<your-rds-endpoint>
export PGPORT=5432
export PGDATABASE=<coder-db-name>
export PGUSER=<coder-db-user>
export PGPASSWORD=<coder-db-password>
```

---

### Phase 2: Upgrade to v2.26.6

**3. Take RDS snapshot (pre-2.26.6)**

```bash
# Option A: RDS console snapshot (recommended)
aws rds create-db-snapshot \
  --db-instance-identifier <your-rds-instance-id> \
  --db-snapshot-identifier coder-pre-2-26-6-$(date +%Y%m%d%H%M%S)

# Option B: pg_dump
pg_dump -Fc -f coder-pre-2.26.6-$(date +%Y%m%d%H%M%S).dump
```

Wait for the snapshot to complete:

```bash
aws rds wait db-snapshot-available \
  --db-snapshot-identifier <snapshot-id-from-above>
```

**4. Review v2.26.6 release notes**

No breaking changes between v2.23.1 and v2.26.6 that require config changes, but skim the releases for anything relevant to features you use:
- https://github.com/coder/coder/releases/tag/v2.24.0
- https://github.com/coder/coder/releases/tag/v2.25.0
- https://github.com/coder/coder/releases/tag/v2.26.0

**5. Upgrade to v2.26.6**

```bash
helm repo update

helm upgrade coder coder-v2/coder \
  -n <coder-namespace> \
  -f coder-values-backup.yaml \
  --version 2.26.6
```

**6. Verify the upgrade**

```bash
# Check pods are healthy
kubectl get pods -n <coder-namespace>

# Check version
kubectl exec -n <coder-namespace> deployment/coder -- coder version

# Check logs for dbpurge activity
kubectl logs -n <coder-namespace> deployment/coder --since=10m | grep -i "purge"
```

**7. Wait several days (3–7 days recommended)**

This is the critical step. The `dbpurge` background job runs every 10 minutes and deletes up to 10,000 expired API keys per run (~1.5M/day max). You need to let it drain the table.

Monitor progress:

```bash
# Check dbpurge logs periodically
kubectl logs -n <coder-namespace> deployment/coder --since=1h | grep "purged old database entries"
```

You'll see log lines like:
```
purged old database entries  expired_api_keys=10000 duration=2.3s
```

When `expired_api_keys` drops to `0` consistently, the cleanup is done.

If you have Prometheus configured, you can also monitor the `coderd_dbpurge_records_purged_total{record_type="expired_api_keys"}` metric.

**Optionally, check the table size directly:**

```bash
psql -c "SELECT COUNT(*) FROM api_keys WHERE expires_at < NOW();"
```

When the count is low (hundreds, not hundreds of thousands), you're safe to proceed.

---

### Phase 3: Upgrade to v2.30.1

**8. Take RDS snapshot (pre-2.30.1)**

```bash
aws rds create-db-snapshot \
  --db-instance-identifier <your-rds-instance-id> \
  --db-snapshot-identifier coder-pre-2-30-1-$(date +%Y%m%d%H%M%S)

aws rds wait db-snapshot-available \
  --db-snapshot-identifier <snapshot-id-from-above>
```

**9. Review breaking changes**

There are breaking changes in v2.29.0 and v2.30.0 you must review:

**v2.29.0** (https://github.com/coder/coder/releases/tag/v2.29.0):
- `CODER_AIBRIDGE_INJECT_CODER_MCP_TOOLS` must now be explicitly set to `true` if you use MCP tools
- CLI session tokens now default to OS keyring on macOS/Windows (opt out with `--use-keyring=false`)
- `task_app_id` removed from `WorkspaceBuild` API responses

**v2.30.0** (https://github.com/coder/coder/releases/tag/v2.30.0):
- Terraform modules now cached per template version (behavior change for module updates)
- Experimental AI Bridge API routes moved from `/api/experimental/aibridge/*` to `/api/v2/aibridge/*`
- PKCE enabled by default for unknown external OAuth providers — if your external auth provider doesn't support PKCE, set `CODER_EXTERNAL_AUTH_<N>_PKCE_METHODS=none`
- SFTP/SCP now respects custom agent `dir` setting (previously always used `$HOME`)

**10. Update helm values if needed**

Based on the breaking changes above, update your `coder-values-backup.yaml` if any apply to your deployment. For example, if you use external auth with a provider that doesn't support PKCE:

```yaml
env:
  - name: CODER_EXTERNAL_AUTH_0_PKCE_METHODS
    value: "none"
```

**11. Upgrade to v2.30.1**

```bash
helm repo update

helm upgrade coder coder-v2/coder \
  -n <coder-namespace> \
  -f coder-values-backup.yaml \
  --version 2.30.1
```

**12. Monitor the upgrade**

The v2.27+ migration on `api_keys` should now run quickly since the table was cleaned up. Watch the pods:

```bash
# Watch rollout
kubectl rollout status deployment/coder -n <coder-namespace> --timeout=10m

# Check pods
kubectl get pods -n <coder-namespace>

# Check logs for migration issues
kubectl logs -n <coder-namespace> deployment/coder --since=5m | grep -iE "migration|error|panic"

# Verify version
kubectl exec -n <coder-namespace> deployment/coder -- coder version
```

---

### Rollback (if needed)

If anything goes wrong at either upgrade step:

```bash
# Restore from RDS snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier <new-instance-name> \
  --db-snapshot-identifier <snapshot-id>

# Roll back helm
helm rollback coder -n <coder-namespace>
```

Coder does not support database rollbacks without a snapshot restore — this is why we snapshot before each step.
