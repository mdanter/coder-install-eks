## Switching from GitHub OAuth to Okta OIDC in Coder

This is tricky because Coder **strictly enforces login type per user**. When a user exists with `login_type=github` and tries to log in via OIDC, Coder rejects it with:

> "Incorrect login type, attempting to use `oidc` but user is of login type `github`"

The built-in convert-login-type flow (`/users/{user}/convert-login`) only works for `password` → `oidc` or `password` → `github`. There's no native UI/API path for `github` → `oidc` directly.

### Option 1: Database Migration (Recommended for Bulk)

This is the cleanest approach for a company-wide switch. You're updating every GitHub-auth user to OIDC in one shot.

**1. Take a database snapshot first.**

```bash
aws rds create-db-snapshot \
  --db-instance-identifier <your-rds-instance> \
  --db-snapshot-identifier coder-pre-oidc-migration-$(date +%Y%m%d)
```

**2. Configure Okta OIDC on the Coder server** (but don't remove GitHub yet).

```env
CODER_OIDC_ISSUER_URL=https://your-org.okta.com/oauth2/default
CODER_OIDC_CLIENT_ID=<okta-client-id>
CODER_OIDC_CLIENT_SECRET=<okta-client-secret>
CODER_OIDC_EMAIL_DOMAIN=yourcompany.com
CODER_OIDC_ALLOW_SIGNUPS=false       # prevent accidental new accounts
CODER_OIDC_SCOPES=openid,profile,email
```

**3. Deploy the new config** so Coder has OIDC configured.

**4. Run the database migration** to switch all GitHub users to OIDC:

```sql
BEGIN;

-- Switch user login type from github to oidc
UPDATE users
SET login_type = 'oidc'
WHERE login_type = 'github'
  AND deleted = false;

-- Delete the old GitHub user_links so OIDC can create fresh ones
-- on first login. Coder will match by email and create a new link.
DELETE FROM user_links
WHERE login_type = 'github';

COMMIT;
```

What this does:
- `users.login_type` is changed to `oidc`, so Coder will accept OIDC logins for these users
- Old `user_links` (GitHub OAuth tokens) are removed. On first Okta login, Coder's `findLinkedUser` function will match the user by email and create a new `user_link` with the OIDC tokens

**5. Verify a test user can log in via Okta.**

**6. Remove GitHub OAuth config** from your helm values once confirmed.

**7. Optionally re-enable signups:**

```env
CODER_OIDC_ALLOW_SIGNUPS=true
```

### Option 2: Per-User via API (Small User Count)

If you have a small number of users and want to avoid direct DB changes:

**1. Reset each user to password auth first** (admin API):

```bash
# As an admin, set a temporary password for the user
curl -X PUT \
  -H "Authorization: Bearer $CODER_SESSION_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"password": "<temp-password>", "old_password": ""}' \
  "$CODER_URL/api/v2/users/<user-id>/password"
```

Note: this requires the user to currently have `login_type=password`. Since they're `github`, you'd still need the DB update for this path — making it effectively the same as Option 1 but more manual.

### Key Things to Know

| Concern | Detail |
|---|---|
| **User matching** | Coder matches existing users by email on OIDC login. As long as Okta sends the same email addresses, users map to their existing accounts. |
| **Workspaces** | Unaffected. Workspaces are tied to user IDs, not login type. |
| **API tokens** | Existing session tokens/API keys will be invalidated when login type changes. Users need to re-authenticate. |
| **Groups/Roles** | If you're using OIDC group sync, you'll need to reconfigure the claim mappings for Okta's group claims (often `groups` instead of GitHub's org/team structure). |
| **`linked_id`** | GitHub uses the GitHub user ID. OIDC uses `issuer\|\|subject`. These will be different, which is why we delete old `user_links` — Coder falls back to email matching when no `linked_id` match is found. |
| **Username** | Usernames are preserved. Coder doesn't change usernames on login. |

### The Email Requirement

The critical requirement is that **Okta must send the same email addresses** that users had under GitHub auth. Coder's `findLinkedUser` function first tries to match by `linked_id` (which won't match across providers), then falls back to matching by email. If the emails match, the user is found and the new OIDC link is created.
