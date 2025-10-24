# ForgeRock SSO Integration with Coder

This guide walks through configuring ForgeRock Access Management as an OIDC provider for Coder.

## Prerequisites

- ForgeRock Access Management (AM) instance running
- Coder deployed on Kubernetes with Helm
- Admin access to both ForgeRock and Coder

## Step 1: Configure ForgeRock OAuth 2.0 Client

1. Log into your **ForgeRock Access Management console**

2. Navigate to **Applications → OAuth 2.0** (select your realm, e.g., `/alpha` or `/`)

3. Click **Add Client** or **Create OAuth 2.0 Client** and configure:

   | Field | Value |
   |-------|-------|
   | **Client ID** | `coder-client` (or your preferred ID) |
   | **Client Secret** | Generate a secure secret (save this!) |
   | **Redirect URIs** | `https://coder.yourdomain.com/api/v2/users/oidc/callback` |
   | **Scopes** | `openid profile email offline_access` |
   | **Grant Types** | `authorization_code` and `refresh_token` |
   | **Token Endpoint Auth Method** | `client_secret_post` or `client_secret_basic` |

4. **Configure Claims Mapping** (if needed):
   - Ensure ForgeRock returns these claims in the ID token:
     - `email` (required)
     - `email_verified` (recommended)
     - `preferred_username` or `username` (recommended)
     - `groups` (optional, for group sync)

5. **Save** the client configuration

## Step 2: Get ForgeRock Issuer URL

Your ForgeRock issuer URL format:

https://forgerock.yourdomain.com/am/oauth2


Or for a specific realm:


https://forgerock.yourdomain.com/am/oauth2/realms/root/realms/{realm-name}


Verify by accessing the discovery endpoint:


https://forgerock.yourdomain.com/am/oauth2/.well-known/openid-configuration


## Step 3: Create Kubernetes Secret

Store the ForgeRock client secret securely:

```bash
kubectl create secret generic coder-oidc-secret \
  --from-literal=client-secret='YOUR_FORGEROCK_CLIENT_SECRET' \
  --namespace=coder
```
Or use a YAML file:
```
apiVersion: v1
kind: Secret
metadata:
  name: coder-oidc-secret
  namespace: coder
type: Opaque
stringData:
  client-secret: "YOUR_FORGEROCK_CLIENT_SECRET"
```
Apply:
```
kubectl apply -f coder-oidc-secret.yaml
```
## Step 4: Configure Coder Helm Values
Create or update your values.yaml:
```
coder:
  env:
    # Required: Access URL for your Coder deployment
    - name: CODER_ACCESS_URL
      value: "https://coder.yourdomain.com"
    
    # Required: ForgeRock OIDC Configuration
    - name: CODER_OIDC_ISSUER_URL
      value: "https://forgerock.yourdomain.com/am/oauth2"
    
    - name: CODER_OIDC_CLIENT_ID
      value: "coder-client"
    
    - name: CODER_OIDC_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: coder-oidc-secret
          key: client-secret
    
    # Required: Email domains allowed to authenticate
    - name: CODER_OIDC_EMAIL_DOMAIN
      value: "yourdomain.com"  # Comma-separated for multiple domains
    
    # Recommended: Enable refresh tokens for persistent sessions
    - name: CODER_OIDC_SCOPES
      value: "openid,profile,email,offline_access"
    
    # Optional: Customize the login button
    - name: CODER_OIDC_SIGN_IN_TEXT
      value: "Sign in with ForgeRock"
    
    - name: CODER_OIDC_ICON_URL
      value: "https://www.forgerock.com/themes/custom/forgerock/logo.svg"
    
    # Optional: If ForgeRock uses different claim names
    # - name: CODER_OIDC_EMAIL_FIELD
    #   value: "mail"  # Default is "email"
    
    # - name: CODER_OIDC_USERNAME_FIELD
    #   value: "preferred_username"  # Default is "preferred_username"
    
    # Optional: If email verification is not supported by ForgeRock
    # - name: CODER_OIDC_IGNORE_EMAIL_VERIFIED
    #   value: "true"
    
    # Optional: Disable password authentication (recommended for SSO-only)
    # - name: CODER_DISABLE_PASSWORD_AUTH
    #   value: "true"

  # Optional: Group sync (Premium feature)
  # Uncomment if you want to sync ForgeRock groups to Coder
  #   - name: CODER_OIDC_GROUP_FIELD
  #     value: "groups"
  #   - name: CODER_OIDC_GROUPS_AUTO_CREATE
  #     value: "true"
```
## Step 5: Deploy Coder
Deploy or upgrade Coder with the new configuration:

```bash
helm upgrade --install coder coder-v2/coder \
  --namespace coder \
  --values values.yaml \
  --wait
```
## Step 6: Verify Configuration
Check Coder logs:
```bash
kubectl logs -n coder -l app.kubernetes.io/name=coder --tail=100
```
Navigate to your Coder URL: https://coder.yourdomain.com

Look for the ForgeRock sign-in button on the login page

Test login with a ForgeRock user account

Troubleshooting
Enable Detailed OIDC Logging
If login fails, add these environment variables:
```
coder:
  env:
    # ... existing config ...
    - name: CODER_LOG_FILTER
      value: ".*got oidc claims.*"
    - name: CODER_VERBOSE
      value: "true"
```
Then check logs:
```bash
kubectl logs -n coder -l app.kubernetes.io/name=coder -f
```
Look for messages containing got oidc claims to see what claims ForgeRock is returning.

Common Issues
- Email domain mismatch: Ensure CODER_OIDC_EMAIL_DOMAIN matches your users' email domains
- Redirect URI mismatch: Verify the redirect URI in ForgeRock exactly matches https://coder.yourdomain.com/api/v2/users/oidc/callback
- Missing claims: Check that ForgeRock returns email and preferred_username claims
- Certificate errors: If ForgeRock uses self-signed certificates, you may need to configure Coder to trust them
## Complete Example
Here's a full values.yaml example:
```
coder:
  image:
    tag: "latest"  # Or specific version like "2.x.x"
  
  replicaCount: 1
  
  env:
    - name: CODER_ACCESS_URL
      value: "https://coder.yourdomain.com"
    
    - name: CODER_OIDC_ISSUER_URL
      value: "https://forgerock.yourdomain.com/am/oauth2"
    
    - name: CODER_OIDC_CLIENT_ID
      value: "coder-client"
    
    - name: CODER_OIDC_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: coder-oidc-secret
          key: client-secret
    
    - name: CODER_OIDC_EMAIL_DOMAIN
      value: "yourdomain.com"
    
    - name: CODER_OIDC_SCOPES
      value: "openid,profile,email,offline_access"
    
    - name: CODER_OIDC_SIGN_IN_TEXT
      value: "Sign in with ForgeRock"
    
    - name: CODER_OIDC_ICON_URL
      value: "https://www.forgerock.com/themes/custom/forgerock/logo.svg"
    
    # Optional: Uncomment after testing SSO works
    # - name: CODER_DISABLE_PASSWORD_AUTH
    #   value: "true"

  service:
    type: LoadBalancer  # Or ClusterIP if using Ingress
    
  ingress:
    enable: true
    host: "coder.yourdomain.com"
    tls:
      enable: true
      secretName: coder-tls
```
Additional Features
Refresh Tokens
The configuration above includes offline_access scope to enable refresh tokens. This allows users to stay logged in even after their access token expires (typically 1 hour).

Group Sync (Premium)
To sync ForgeRock groups to Coder roles/groups:

Configure ForgeRock to include a groups claim in the ID token

Add to your values.yaml:
```
- name: CODER_OIDC_GROUP_FIELD
  value: "groups"
- name: CODER_OIDC_GROUPS_AUTO_CREATE
  value: "true"
```
See Coder Group Sync docs for more details

SCIM (Premium)
For automated user provisioning/deprovisioning, configure SCIM:
```
- name: CODER_SCIM_AUTH_HEADER
  valueFrom:
    secretKeyRef:
      name: coder-scim-secret
      key: auth-header
```
