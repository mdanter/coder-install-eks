# Coder EKS Deployment with ALB, ForgeRock SSO, and GitHub Integration

This repository contains the configuration files needed to deploy Coder on Amazon EKS with Application Load Balancer (ALB), ForgeRock SSO integration, GitHub external authentication, and TLS termination.

## 📁 Files Overview

### 1. `values.yaml` - Helm Chart Configuration
The main Helm values file that configures Coder with:
- **ALB Integration**: Uses ClusterIP service with Ingress for ALB
- **ForgeRock OIDC SSO**: Complete OIDC configuration for enterprise authentication
- **GitHub External Auth**: Enables GitHub integration for workspace templates
- **Local User Creation**: Allows password-based authentication alongside SSO
- **Resource Limits**: 2 CPU cores and 8GB RAM per Coder instance
- **Provisioner Configuration**: 8 threads for concurrent workspace builds
- **High Availability**: 2 replicas with multi-AZ pod anti-affinity
- **TLS**: Handled by ALB with ACM certificates

### 2. `required-secrets.yaml` - Kubernetes Secrets
Defines the required Kubernetes secrets for:
- **Database Connection**: PostgreSQL connection URL
- **ForgeRock OIDC**: Client ID and secret for SSO
- **GitHub OAuth**: Client credentials for external authentication

### 3. `deployment-commands.sh` - Deployment Script
Automated deployment script that:
- Creates the namespace
- Applies secrets
- Adds Helm repository
- **Performs dry-run validation** with interactive review
- Deploys Coder
- Validates deployment status
- Provides troubleshooting helpers

### 4. `universal-workspace-template.tf` - Workspace Template
Terraform template for creating workspaces with:
- **VS Code Server**: Web-based IDE on port 13337
- **JupyterLab**: Data science environment on port 8888
- **GitHub Integration**: Automatic Git configuration with tokens
- **Configurable Resources**: CPU, memory, and storage parameters
- **Development Tools**: Docker, Git, and common utilities

## 🚀 Prerequisites

Before deploying, ensure you have:

### AWS Infrastructure
- [ ] EKS cluster running
- [ ] AWS Load Balancer Controller installed
- [ ] ACM certificate created and validated for your domain
- [ ] Proper IAM permissions for ALB controller
- [ ] PostgreSQL database (RDS recommended)

### Authentication Setup
- [ ] ForgeRock OIDC application configured
- [ ] GitHub OAuth application created
- [ ] DNS records pointing to your domain

### Local Tools
- [ ] `kubectl` configured for your EKS cluster
- [ ] `helm` v3.x installed
- [ ] Access to create secrets in the target namespace

## 📝 Configuration Steps

### Step 1: Configure Secrets

1. **Update `required-secrets.yaml`** with your actual values:

```bash
# Database connection (base64 encoded)
echo -n 'postgres://username:password@host:5432/coder?sslmode=require' | base64

# ForgeRock credentials (base64 encoded)
echo -n 'your-forgerock-client-id' | base64
echo -n 'your-forgerock-client-secret' | base64

# GitHub credentials (base64 encoded)
echo -n 'your-github-client-id' | base64
echo -n 'your-github-client-secret' | base64
```

2. **Replace placeholders** in `required-secrets.yaml` with the base64 values above

### Step 2: Configure Helm Values

1. **Update `values.yaml`** with your specific values:

```yaml
# Update these values:
CODER_ACCESS_URL: "https://your-domain.com"
CODER_WILDCARD_ACCESS_URL: "*.your-domain.com"
CODER_OIDC_ISSUER_URL: "https://your-forgerock.com/oauth2"
CODER_OIDC_EMAIL_DOMAIN: "your-company.com"

# Update ALB certificate ARN:
alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:region:account:certificate/your-cert-id"

# Update ingress hosts:
host: "your-domain.com"
wildcardHost: "*.your-domain.com"
```

### Step 3: Deploy Coder

1. **Make the script executable**:
```bash
chmod +x deployment-commands.sh
```

2. **Run the deployment**:
```bash
./deployment-commands.sh
```

3. **Review the dry-run output** carefully before proceeding

4. **Press Enter** to continue with deployment or **Ctrl+C** to abort

## 🔧 Validation & Troubleshooting

### Check Deployment Status
```bash
# Check pods
kubectl get pods -n coder

# Check ingress
kubectl get ingress -n coder

# Check logs
kubectl logs -n coder -l app.kubernetes.io/name=coder -f
```

### Verify ALB Configuration
1. **Check AWS Console**: Go to EC2 → Load Balancers
2. **Verify Target Groups**: Ensure targets are healthy
3. **Test DNS**: `nslookup your-domain.com`
4. **Test Connectivity**: `curl -I https://your-domain.com/healthz`

### Common Issues

**Pods not starting:**
- Check resource limits vs node capacity
- Verify secrets are created correctly
- Check image pull permissions

**ALB not routing traffic:**
- Verify certificate ARN is correct
- Check security groups allow traffic
- Ensure DNS points to ALB hostname

**Authentication issues:**
- Verify ForgeRock/GitHub redirect URIs
- Check client credentials in secrets
- Review OIDC issuer URL format

## 🏗️ Workspace Template Usage

### Deploy the Template
1. **Login to Coder** as an admin
2. **Go to Templates** → Create Template
3. **Upload `universal-workspace-template.tf`**
4. **Configure parameters**:
   - CPU: 1-16 cores
   - Memory: 2-64 GB
   - Storage: 10-1000 GB
   - Image: Select from available options

### Template Features
- **VS Code**: Access at `https://*.your-domain.com` (workspace URL)
- **JupyterLab**: Available on port 8888
- **GitHub Integration**: Automatic Git configuration
- **Docker Support**: Container runtime included
- **Resource Monitoring**: CPU, memory, and disk usage

## 📊 Monitoring & Metrics

Coder includes Prometheus metrics on port 2112:

```bash
# Port-forward to access metrics
kubectl port-forward -n coder svc/coder 2112:2112

# View metrics
curl http://localhost:2112/metrics
```

## 🔒 Security Considerations

- **Secrets Management**: Consider using AWS Secrets Manager or External Secrets Operator
- **Network Policies**: Implement Kubernetes network policies
- **RBAC**: Review and restrict ServiceAccount permissions
- **Image Security**: Scan container images for vulnerabilities
- **WAF**: Consider enabling AWS WAF on the ALB

## 🔄 Updating Coder

```bash
# Update Helm repository
helm repo update

# Check available versions
helm search repo coder-v2/coder

# Upgrade with dry-run first
helm upgrade coder coder-v2/coder \
  --namespace coder \
  --values values.yaml \
  --dry-run --debug

# Apply upgrade
helm upgrade coder coder-v2/coder \
  --namespace coder \
  --values values.yaml
```

## 📚 Additional Resources

- [Coder Documentation](https://coder.com/docs)
- [Kubernetes Templates Guide](https://coder.com/docs/templates/kubernetes)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [ForgeRock OIDC Configuration](https://backstage.forgerock.com/docs/am/7/oidc1-guide/)

## 🆘 Support

For issues:
1. Check the troubleshooting section above
2. Review Coder logs: `kubectl logs -n coder -l app.kubernetes.io/name=coder`
3. Check AWS ALB target group health
4. Verify DNS and certificate configuration
5. Contact your platform team or Coder support

---

**Note**: This configuration is production-ready but should be customized for your specific security and compliance requirements.
