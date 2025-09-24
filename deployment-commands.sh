#!/bin/bash
# Deployment commands for Coder on EKS with ALB

# Prerequisites:
# 1. AWS Load Balancer Controller must be installed in your EKS cluster
# 2. ACM certificate must be created and validated for your domain
# 3. Proper IAM permissions for ALB controller

# 1. Create namespace
kubectl create namespace coder

# 2. Create secrets (after updating values in required-secrets.yaml)
kubectl apply -f required-secrets.yaml

# 3. Add Coder Helm repository
helm repo add coder-v2 https://helm.coder.com/v2
helm repo update

# 4. DRY RUN - Generate and validate Kubernetes manifests without applying
echo "=== HELM DRY RUN - Validating configuration ==="
helm install coder coder-v2/coder \
  --namespace coder \
  --values values.yaml \
  --dry-run --debug

echo ""
echo "=== DRY RUN COMPLETED - Review output above ==="
echo "Press Enter to continue with actual deployment, or Ctrl+C to abort"
read -r

# 5. Install Coder with ALB configuration
echo "=== DEPLOYING CODER ==="
helm install coder coder-v2/coder \
  --namespace coder \
  --values values.yaml \
  --wait

# 6. Check deployment status
echo "=== CHECKING DEPLOYMENT STATUS ==="
kubectl get pods -n coder
kubectl get svc -n coder
kubectl get ingress -n coder

# 7. Get ALB DNS name
echo ""
echo "=== ALB INFORMATION ==="
echo "ALB DNS Name:"
kubectl get ingress coder -n coder -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo ""

# 8. Verify configuration
echo ""
echo "=== CONFIGURATION VERIFICATION ==="
echo "Coder pods:"
kubectl get pods -n coder -l app.kubernetes.io/name=coder

echo ""
echo "Ingress details:"
kubectl describe ingress coder -n coder

# 9. Check ALB target groups
echo ""
echo "=== NEXT STEPS ==="
echo "1. Check ALB target groups in AWS Console for health status"
echo "2. Verify DNS points to ALB hostname"
echo "3. Test connectivity at: https://coder.example.com"
echo "4. Check logs if issues occur: kubectl logs -n coder -l app.kubernetes.io/name=coder -f"

# 10. Optional: Show generated manifests for review
echo ""
echo "=== OPTIONAL: Show generated manifests (y/n)? ==="
read -r show_manifests
if [[ $show_manifests == "y" || $show_manifests == "Y" ]]; then
    echo "Generated manifests:"
    helm get manifest coder -n coder
fi

# 11. Test connectivity helper
echo ""
echo "=== CONNECTIVITY TEST HELPER ==="
echo "Run this to test your deployment:"
echo "curl -I https://coder.example.com/healthz"
echo ""
echo "Expected response: HTTP/2 200"
