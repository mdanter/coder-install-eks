# Coder TLS Limitations

## Running Coder Without TLS

Without TLS, Coder and workspaces would have several critical limitations:

### Authentication & Session Security

- Browser session cookies can't use the `Secure` flag, making them vulnerable to interception
- OAuth/OIDC integration with external providers (GitHub, GitLab, Okta, etc.) would fail or be severely limited - most providers require HTTPS redirect URLs
- Session tokens transmitted over unencrypted HTTP are vulnerable to man-in-the-middle attacks

### Workspace Apps & Access

- Wildcard subdomain apps wouldn't work properly - browsers enforce strict security policies for cookies across subdomains without HTTPS
- Path-based apps would need to stay enabled (less secure, vulnerable to XSS attacks)
- Web terminal and IDE access would transmit all keystrokes and code in plaintext

### Data Exposure

- All workspace traffic (code, credentials, API keys) transmitted between users and workspaces would be unencrypted
- Git operations over HTTPS wouldn't work securely
- Template parameters and provisioner data would be exposed in transit

### Compliance & Best Practices

- Violates security best practices outlined in the docs
- Fails most enterprise security requirements
- Can't enable Strict Transport Security headers

**Note:** Coder _can_ technically run without TLS (useful for local dev/testing), but it's not production-ready. The security docs strongly recommend placing Coder behind a TLS-terminating reverse proxy at minimum.

## Running Coder Without Wildcard Certificates

If you run Coder with TLS but without a wildcard certificate configured for workspace applications, you'll face these tradeoffs:

### Port Forwarding & Application Access

- **No dashboard-based port forwarding**: Users cannot access workspace ports through the Coder web UI
- **CLI-only port forwarding**: Teams must rely on `coder port-forward` command or SSH tunneling, which requires CLI installation and knowledge
- **No visual application icons**: `coder_app` resources with `subdomain = true` won't be accessible through the dashboard
- **Limited sharing capabilities**: Cannot share workspace applications with other users via URLs (authenticated or public sharing)

### Development Workflow Impact

- **Modern framework incompatibility**: Tools that require subdomain access will not work properly:
  - Vite dev server (HMR and asset serving issues)
  - React dev server (hot reloading problems)
  - Next.js development server (routing conflicts)
  - JupyterLab (requires complex workarounds)
  - RStudio (requires complex workarounds)
- **Path-based apps required**: Must keep path-based apps enabled, which:
  - Shares the same origin as the Coder API
  - Increases XSS attack surface
  - Allows malicious workspaces to potentially access the Coder API or other workspaces owned by the same user

### Security Considerations

- **Cannot disable path-based apps**: The security best practice of disabling path-based apps becomes unavailable
- **Reduced security isolation**: Applications don't run in isolated subdomains with separate browser security contexts
- **Limited malicious workspace protection**: Mitigations against malicious workspace code accessing other resources are weakened

### User Experience

- **Steeper learning curve**: Users must learn CLI tools for basic port forwarding
- **No browser-based previews**: Cannot quickly preview web applications without additional setup
- **Limited collaboration**: Cannot easily share running applications with teammates for review or debugging
- **Compatibility issues**: Many applications expect root-path hosting and may not work correctly when served from a subpath

### When This Might Be Acceptable

 Running without wildcard certificates may be acceptable if:

- You're only using SSH-based workflows (no web applications)
- Your team is comfortable with CLI tools and port forwarding commands
- You don't need to run modern frontend frameworks in workspaces
- Users don't need to share application previews with others
- Security policies prevent wildcard certificate issuance

### Recommended Setup

For production deployments, it's highly recommended to:

1. Configure a wildcard access URL (e.g., `*.coder.example.com`)
2. Obtain a wildcard TLS certificate (via Let's Encrypt or your CA)
3. Configure DNS to point wildcard subdomains to Coder
4. Disable path-based apps after wildcard setup

See the [Wildcard Access URL documentation](https://github.com/coder/coder/blob/main/docs/admin/networking/wildcard-access-url.md) for setup instructions.