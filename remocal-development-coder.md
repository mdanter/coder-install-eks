# Remocal Microservice Development with Coder, vCluster, and mirrord

> **A reference architecture for hybrid remote/local Kubernetes development**
>
> Run one service locally in your Coder workspace with full debugging — while
> the rest of your microservices run in a per-developer vCluster on the same
> host cluster. Zero-latency, fully isolated, fully FOSS.

---

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Architecture Overview](#architecture-overview)
3. [Component Summary](#component-summary)
4. [Why mirrord over Telepresence?](#why-mirrord-over-telepresence)
5. [Architecture Diagram](#architecture-diagram)
6. [Coder Terraform Template](#coder-terraform-template)
7. [Workspace Container Image](#workspace-container-image)
8. [Developer Workflow](#developer-workflow)
9. [Shared vCluster Variant](#shared-vcluster-variant)
10. [Design Decisions & Tradeoffs](#design-decisions--tradeoffs)
11. [Security Considerations](#security-considerations)
12. [Cost & Resource Optimization](#cost--resource-optimization)
13. [References](#references)

---

## Problem Statement

Large microservice applications (20+ services) create a fundamental tension for
developers:

- **Running everything locally** is impractical — laptops can't handle 20+
  services, databases, queues, and caches simultaneously.
- **Running everything remotely** slows the inner dev loop — every code change
  requires build → push → deploy → wait.
- **Mocking/stubbing dependencies** drifts from reality and misses integration
  bugs.

The ideal workflow is **"single service local, all others remote"** — run the
one service you're changing with a local debugger and hot-reload, while every
dependency runs in a realistic Kubernetes environment.

---

## Architecture Overview

This architecture combines three open-source tools:

1. **Coder** provisions a remote workspace (a pod on K8s) that acts as the
   developer's "local machine" — with IDE access, tooling, and cluster
   network connectivity.

2. **vCluster** creates a per-developer virtual Kubernetes cluster in an
   adjacent namespace. All N microservices are deployed here. Each developer
   gets full isolation without the cost of a real cluster.

3. **mirrord** connects the process running in the workspace to the vCluster,
   mirroring or intercepting traffic for the target service. The developer's
   local process receives the remote pod's network traffic, environment
   variables, and file system — transparently.

Because the Coder workspace pod and the vCluster pods share the **same host
cluster network**, there is near-zero latency between them. The workspace
effectively acts as a bastion host with kubectl access to the vCluster.

---

## Component Summary

| Component | Role | License | Key Property |
|-----------|------|---------|--------------|
| [Coder](https://coder.com) | Remote dev environment provisioning | AGPL-3.0 | Terraform-defined workspaces on K8s |
| [vCluster](https://vcluster.com) | Per-developer virtual K8s clusters | Apache-2.0 | Full K8s API isolation, shared compute |
| [mirrord](https://mirrord.dev) | Service-level traffic interception | MIT | Process-level, no root, no cluster daemon |

---

## Why mirrord over Telepresence?

| Dimension | mirrord | Telepresence |
|-----------|---------|--------------|
| **License** | MIT | Apache-2.0 (CLI), but enterprise features gated; Ambassador account required |
| **Root privileges** | Not required | Required (system-wide VPN / tun device) |
| **Cluster-side install** | None — spawns temporary agent pod on demand | Requires persistent Traffic Manager deployment |
| **Scope** | Process-level (LD_PRELOAD) | System-wide (VPN / tun device) |
| **Concurrency** | Multiple devs mirror same service simultaneously | Intercept conflicts without filtered intercepts |
| **Default mode** | Mirror (non-disruptive) — traffic is duplicated | Intercept (disruptive) — traffic is rerouted |
| **IDE integration** | VS Code + JetBrains plugins (first-class) | CLI-first, IDE support secondary |
| **Env vars & files** | Automatically injected from target pod | Requires `--env-file` flag or manual mount |
| **Complexity** | Single binary, no daemon | Client daemon + cluster Traffic Manager |

mirrord operates at the process level by injecting itself into the local binary
(via `LD_PRELOAD` on Linux), overriding libc function calls, and proxying them
to a temporary agent in the cluster. This covers network access, file access,
and environment variables uniformly — without modifying the host's networking
or requiring elevated privileges.

**For a workspace-as-bastion architecture, mirrord is ideal** because:
- No root in the workspace container (security best practice)
- No persistent cluster components to maintain in the vCluster
- Multiple developers can mirror the same service without conflict
- Just `mirrord exec` — one command, no setup

---

## Architecture Diagram

```
┌─ Host Kubernetes Cluster ───────────────────────────────────────────────────┐
│                                                                              │
│  ┌─ namespace: coder-ws-alice ──────────┐                                   │
│  │                                       │                                   │
│  │  Coder Workspace Pod                  │                                   │
│  │  ┌─────────────────────────────────┐  │                                   │
│  │  │  IDE (VS Code / JetBrains)      │  │                                   │
│  │  │  mirrord CLI                    │  │                                   │
│  │  │  kubectl → vCluster kubeconfig  │  │                                   │
│  │  │                                 │  │                                   │
│  │  │  ┌───────────────────────────┐  │  │    ┌─ namespace: vc-alice ──────┐│
│  │  │  │  YOUR SERVICE             │  │  │    │                            ││
│  │  │  │  (running locally with    │──┼──┼───►│  vCluster (alice-dev)      ││
│  │  │  │   hot-reload & debugger)  │  │  │    │                            ││
│  │  │  │                           │◄─┼──┼────│  ┌──────────────────────┐  ││
│  │  │  │  mirrord hooks syscalls   │  │  │    │  │ api-gateway    :8080 │  ││
│  │  │  │  to mirror/steal traffic  │  │  │    │  │ auth-service   :8081 │  ││
│  │  │  │  from the target pod      │  │  │    │  │ user-service   :8082 │  ││
│  │  │  └───────────────────────────┘  │  │    │  │ order-service  :8083 │◄─┤│
│  │  │                                 │  │    │  │   └─ mirrord agent  │  ││
│  │  └─────────────────────────────────┘  │    │  │ payment-service:8084 │  ││
│  └───────────────────────────────────────┘    │  │ postgres       :5432 │  ││
│                                               │  │ redis          :6379 │  ││
│                                               │  │ rabbitmq       :5672 │  ││
│                                               │  └──────────────────────┘  ││
│                                               └────────────────────────────┘│
│                                                                              │
│  Same cluster network — near-zero latency between workspace and vCluster    │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Traffic flow:**

```
1. Developer edits code in workspace IDE
2. Runs: mirrord exec --target deploy/order-service -- npm run dev
3. mirrord spawns a temporary agent pod in the vCluster
4. Agent mirrors/steals incoming traffic to order-service
5. Traffic is forwarded to the local process in the workspace
6. Local process responds; mirrord routes response back through agent
7. Outgoing calls from local process (e.g., to postgres) are sent
   from the agent pod — same network policy, same DNS, same credentials
```

---

## Coder Terraform Template

This template provisions both the workspace pod and the vCluster, wires
kubeconfig, deploys your microservices, and pre-installs mirrord.

```hcl
# ============================================================================
# remocal-workspace/main.tf
# Coder template: workspace + vCluster + mirrord
# ============================================================================

terraform {
  required_providers {
    coder      = { source = "coder/coder" }
    kubernetes = { source = "hashicorp/kubernetes" }
    helm       = { source = "hashicorp/helm" }
  }
}

# ── Coder data sources ─────────────────────────────────────────────

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# ── Variables ──────────────────────────────────────────────────────

variable "host_namespace" {
  description = "Namespace for workspace pods on the host cluster"
  default     = "coder-workspaces"
}

variable "app_chart_repo" {
  description = "Helm chart repository for your microservices"
  default     = "https://charts.your-org.dev"
}

variable "app_chart_name" {
  description = "Helm chart name for your microservices"
  default     = "my-platform"
}

variable "app_chart_version" {
  description = "Helm chart version"
  default     = "1.0.0"
}

# ── Locals ─────────────────────────────────────────────────────────

locals {
  workspace_name = data.coder_workspace.me.name
  owner          = data.coder_workspace_owner.me.name
  vc_name        = "${local.workspace_name}-dev"
  vc_namespace   = "vc-${local.owner}-${local.workspace_name}"
  ws_pod_name    = "coder-${local.owner}-${local.workspace_name}"
}

# ── 1. vCluster — per-developer virtual Kubernetes cluster ─────────

resource "kubernetes_namespace" "vcluster" {
  metadata {
    name = local.vc_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "coder"
      "coder.owner"                  = local.owner
      "coder.workspace"              = local.workspace_name
    }
  }
}

resource "helm_release" "vcluster" {
  name       = local.vc_name
  namespace  = local.vc_namespace
  repository = "https://charts.loft.sh"
  chart      = "vcluster"
  version    = "0.27.0"

  depends_on = [kubernetes_namespace.vcluster]

  values = [yamlencode({
    vcluster = {
      image = "rancher/k3s:v1.30.2-k3s1"
    }
    sync = {
      toHost = {
        services      = { enabled = true }
        configmaps    = { enabled = true }
        secrets       = { enabled = true }
        pods          = { enabled = true }
      }
    }
    syncer = {
      extraArgs = ["--tls-san=${local.vc_name}.${local.vc_namespace}.svc.cluster.local"]
    }
  })]
}

# ── 2. Coder agent ─────────────────────────────────────────────────

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  dir  = "/home/coder"

  display_apps {
    vscode     = true
    ssh_helper = true
    web_terminal = true
  }

  startup_script = <<-EOF
    #!/bin/bash
    set -euo pipefail

    echo ">>> Waiting for vCluster to be ready..."
    until kubectl get pods -n ${local.vc_namespace} -l app=${local.vc_name} \
      --field-selector=status.phase=Running -o name 2>/dev/null | grep -q pod; do
      sleep 2
    done

    echo ">>> Generating vCluster kubeconfig..."
    vcluster connect ${local.vc_name} \
      --namespace ${local.vc_namespace} \
      --server=https://${local.vc_name}.${local.vc_namespace}.svc.cluster.local \
      --update-current=false \
      --kube-config /home/coder/.kube/vcluster.yaml

    export KUBECONFIG=/home/coder/.kube/vcluster.yaml

    echo ">>> Deploying microservices into vCluster..."
    helm upgrade --install my-app ${var.app_chart_repo}/${var.app_chart_name} \
      --version ${var.app_chart_version} \
      --kubeconfig /home/coder/.kube/vcluster.yaml \
      --namespace default \
      --wait --timeout 5m

    echo ">>> Ready! Use 'mirrord exec' to start developing."
    echo ">>> Example:"
    echo ">>>   export KUBECONFIG=/home/coder/.kube/vcluster.yaml"
    echo ">>>   mirrord exec --target deploy/order-service -- npm run dev"
  EOF

  env = {
    KUBECONFIG = "/home/coder/.kube/vcluster.yaml"
  }
}

# ── 3. Workspace pod ──────────────────────────────────────────────

resource "kubernetes_service_account" "workspace" {
  metadata {
    name      = local.ws_pod_name
    namespace = var.host_namespace
  }
}

# RBAC: workspace SA needs access to the vCluster namespace
resource "kubernetes_role_binding" "vcluster_access" {
  metadata {
    name      = "${local.ws_pod_name}-vc-access"
    namespace = local.vc_namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.ws_pod_name
    namespace = var.host_namespace
  }
}

resource "kubernetes_pod" "workspace" {
  metadata {
    name      = local.ws_pod_name
    namespace = var.host_namespace
    labels = {
      "coder.owner"     = local.owner
      "coder.workspace" = local.workspace_name
    }
  }

  spec {
    service_account_name = kubernetes_service_account.workspace.metadata[0].name

    container {
      name  = "dev"
      image = "ghcr.io/your-org/remocal-workspace:latest"

      command = ["sh", "-c", coder_agent.main.init_script]

      resources {
        requests = {
          cpu    = "2"
          memory = "4Gi"
        }
        limits = {
          cpu    = "4"
          memory = "8Gi"
        }
      }

      volume_mount {
        name       = "home"
        mount_path = "/home/coder"
      }
    }

    volume {
      name = "home"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.home.metadata[0].name
      }
    }
  }

  depends_on = [helm_release.vcluster]
}

resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "${local.ws_pod_name}-home"
    namespace = var.host_namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }
}

# ── 4. Coder apps (optional UI shortcuts) ─────────────────────────

resource "coder_app" "vcluster_dashboard" {
  agent_id     = coder_agent.main.id
  slug         = "k8s"
  display_name = "vCluster Services"
  command      = "kubectl get svc --kubeconfig /home/coder/.kube/vcluster.yaml -w"
  icon         = "/icon/k8s.png"
}
```

---

## Workspace Container Image

Pre-bake all tooling into the workspace image for fast startup.

```dockerfile
# ============================================================================
# Dockerfile — remocal workspace image
# ============================================================================

FROM ubuntu:22.04

ARG MIRRORD_VERSION=3.120.0
ARG VCLUSTER_VERSION=0.27.0
ARG KUBECTL_VERSION=1.30.2
ARG HELM_VERSION=3.15.3

ENV DEBIAN_FRONTEND=noninteractive

# ── Base packages ──────────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    curl wget git build-essential ca-certificates \
    jq unzip sudo openssh-client \
    && rm -rf /var/lib/apt/lists/*

# ── kubectl ────────────────────────────────────────────────────────
RUN curl -LO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && install kubectl /usr/local/bin/ && rm kubectl

# ── Helm ───────────────────────────────────────────────────────────
RUN curl -fsSL https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz \
    | tar xzf - --strip-components=1 -C /usr/local/bin linux-amd64/helm

# ── vCluster CLI ───────────────────────────────────────────────────
RUN curl -L -o vcluster \
    "https://github.com/loft-sh/vcluster/releases/download/v${VCLUSTER_VERSION}/vcluster-linux-amd64" \
    && install vcluster /usr/local/bin/ && rm vcluster

# ── mirrord CLI ────────────────────────────────────────────────────
RUN curl -fsSL https://raw.githubusercontent.com/metalbear-co/mirrord/main/scripts/install.sh | bash

# ── k9s (optional, nice TUI for K8s) ──────────────────────────────
RUN curl -fsSL https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz \
    | tar xzf - -C /usr/local/bin k9s

# ── Non-root user ─────────────────────────────────────────────────
RUN useradd -m -s /bin/bash -u 1000 coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder

USER coder
WORKDIR /home/coder

# ── Add your language runtimes below ───────────────────────────────
# Examples:
#   Node.js:  RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash && apt-get install -y nodejs
#   Go:       RUN curl -fsSL https://go.dev/dl/go1.22.5.linux-amd64.tar.gz | tar xzf - -C /usr/local
#   Python:   RUN apt-get install -y python3 python3-pip python3-venv
#   Rust:     RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
#   Java:     RUN apt-get install -y openjdk-21-jdk maven
```

---

## Developer Workflow

### First-time setup (automated by Coder template)

When the workspace starts, the startup script:
1. Waits for the vCluster to become healthy
2. Generates a kubeconfig pointing at the vCluster's API server
3. Deploys all microservices into the vCluster via Helm
4. Sets `KUBECONFIG` to the vCluster config

The developer opens their IDE and is ready to go.

### Daily workflow

```bash
# ── 1. Check what's running in your personal vCluster ──
kubectl get pods
# NAME                              READY   STATUS    RESTARTS   AGE
# api-gateway-5d4f6c7b8-xk2j9      1/1     Running   0          5m
# auth-service-7f8d9e0a1-lm3n4     1/1     Running   0          5m
# order-service-2b3c4d5e6-fg7h8    1/1     Running   0          5m
# payment-service-9i0j1k2l3-mn4o5  1/1     Running   0          5m
# postgres-0                        1/1     Running   0          5m
# redis-0                           1/1     Running   0          5m

# ── 2. Navigate to your service's source code ──
cd ~/src/order-service

# ── 3. Run your service with mirrord (mirror mode — non-disruptive) ──
mirrord exec --target deploy/order-service -- npm run dev

# mirrord will:
#   - Spawn a temporary agent pod next to order-service
#   - Inject env vars from the target pod into your process
#   - Mirror incoming traffic to your local process
#   - Route outgoing connections through the agent (same network as the pod)
#   - Your process can reach postgres, redis, auth-service, etc. by DNS name

# ── 4. Or use steal mode to fully intercept traffic ──
mirrord exec --target deploy/order-service -f steal -- npm run dev

# ── 5. Or run with a debugger via IDE ──
# VS Code:  Install mirrord extension → click "mirrord" in status bar → select target
# JetBrains: Install mirrord plugin → Run/Debug configuration → enable mirrord
```

### mirrord configuration file (optional)

For repeatable setups, create `.mirrord/mirrord.json` in your project:

```json
{
  "target": {
    "path": "deploy/order-service",
    "namespace": "default"
  },
  "feature": {
    "network": {
      "incoming": "steal",
      "outgoing": true,
      "dns": true
    },
    "fs": "read",
    "env": true
  },
  "kubeconfig": "/home/coder/.kube/vcluster.yaml"
}
```

Then simply run:

```bash
mirrord exec -- npm run dev
# or in VS Code, mirrord picks up the config automatically
```

### Verifying connectivity

```bash
# From your mirrord-wrapped process, these just work:
curl http://auth-service:8081/health
curl http://postgres:5432  # TCP connectivity
curl http://redis:6379     # same

# Environment variables from the target pod are injected:
echo $DATABASE_URL      # postgres://user:pass@postgres:5432/orders
echo $REDIS_URL         # redis://redis:6379
echo $AUTH_SERVICE_URL   # http://auth-service:8081
```

---

## Shared vCluster Variant

For smaller teams or cost optimization, multiple developers can share a single
vCluster. mirrord's default **mirror mode** makes this safe:

```
┌─ Host Cluster ─────────────────────────────────────────────────┐
│                                                                 │
│  ┌─ alice's workspace ──┐  ┌─ bob's workspace ──┐              │
│  │  mirrord exec         │  │  mirrord exec       │             │
│  │  --target order-svc   │  │  --target user-svc   │            │
│  │  (mirror mode)        │  │  (mirror mode)        │           │
│  └──────────┬────────────┘  └──────────┬────────────┘           │
│             │                          │                         │
│             ▼                          ▼                         │
│  ┌─ shared vCluster (team-dev) ────────────────────────────────┐│
│  │  order-service ──── mirrord agent (alice)                   ││
│  │  user-service  ──── mirrord agent (bob)                     ││
│  │  api-gateway, auth-service, payment-service, postgres, etc. ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

In **mirror mode** (the default), mirrord duplicates traffic — the original
requests are handled by the remote service, so people accessing it are
completely unaware that you're debugging it. Multiple developers can mirror
the same service simultaneously without conflict.

When you need to **intercept** (steal) traffic exclusively, mirrord supports
HTTP header filtering:

```bash
mirrord exec --target deploy/order-service \
  -f steal \
  --http-header-filter "X-Dev-User=alice" \
  -- npm run dev
```

---

## Design Decisions & Tradeoffs

### Why vCluster instead of namespaces?

| | vCluster | Namespace-per-developer |
|---|---|---|
| **API isolation** | Own API server, CRDs, RBAC | Shared API server |
| **CRD conflicts** | None — each vCluster has its own | CRDs are cluster-scoped |
| **Resource quotas** | Per-vCluster | Requires namespace-level quotas |
| **Service mesh** | Can run its own | Shared mesh, potential conflicts |
| **Cleanup** | Delete namespace = delete everything | Labeling discipline required |
| **Cost** | Minimal overhead (~128MB for k3s) | Slightly less overhead |

### Why mirrord instead of kubectl port-forward?

`kubectl port-forward` only gives you **one-way access** to remote services.
mirrord gives you **bidirectional context**: incoming traffic, outgoing
connections, environment variables, and file system — all transparently
injected into your process.

### Why the workspace as bastion?

- **No K8s credentials on developer laptops** — the workspace has a
  ServiceAccount; developers connect via Coder's encrypted tunnel.
- **Consistent tooling** — every developer gets the same image with the
  same versions of kubectl, mirrord, helm, etc.
- **Network locality** — workspace pod and vCluster pods are on the same
  cluster network. No VPN, no NAT traversal, no internet hops.

---

## Security Considerations

1. **No root required** — mirrord doesn't need root access on your machine.
   All it does is override the functions of a running process; the rest of
   your machine remains untouched.

2. **No cluster-wide components** — mirrord spawns a temporary agent pod
   that is scoped to the target deployment. It is cleaned up automatically.

3. **vCluster RBAC** — the workspace ServiceAccount has admin access only
   to its own vCluster namespace. It cannot reach other developers'
   environments.

4. **Coder access controls** — workspace access is gated by Coder's
   authentication. No direct SSH to the host cluster.

5. **Network policies** — apply host-cluster NetworkPolicies to restrict
   vCluster namespaces from reaching production workloads.

6. **Only use in development** — a misconfigured setup can expose sensitive
   information like service account tokens. Only use mirrord intercepts in
   development environments.

---

## Cost & Resource Optimization

| Strategy | Impact |
|----------|--------|
| **Coder auto-stop** | Idle workspaces shut down after configurable timeout |
| **vCluster sleep mode** | Inactive vClusters pause, consuming zero compute |
| **Shared host nodes** | vCluster pods share node pools — no dedicated VMs |
| **Shared vCluster option** | Teams share one vCluster instead of one-per-dev |
| **Persistent volumes** | Home dirs persist across workspace restarts |
| **Image caching** | Pre-pull workspace + service images to node cache |

**Rough cost per developer** (on AWS, approximate):
- Workspace pod: ~2 CPU / 4GB RAM
- vCluster overhead: ~0.25 CPU / 256MB RAM (k3s control plane)
- Microservice pods: depends on your app (shared node pool)
- Total: comparable to a single `m5.xlarge` when active, near-zero when idle

---

## References

- **Coder** — https://coder.com/docs — Self-hosted cloud development
  environments defined in Terraform.
- **vCluster** — https://www.vcluster.com/docs — Virtual Kubernetes clusters.
  Apache-2.0 licensed. Creates fully functional virtual Kubernetes clusters
  that run inside namespaces of a host cluster.
- **mirrord** — https://mirrord.dev/docs — Process-level K8s traffic
  mirroring/interception. MIT licensed. No root, no cluster daemon, IDE
  plugins for VS Code and JetBrains.
- **Kubernetes blog: Comparing local K8s dev tools** —
  https://kubernetes.io/blog/2023/09/12/local-k8s-development-tools/ —
  Official comparison of Telepresence, Gefyra, and mirrord.
- **Coder templates (Kubernetes)** —
  https://github.com/coder/coder/blob/main/examples/templates/kubernetes/main.tf

---

## Alternative FOSS Tools (also considered)

| Tool | License | Notes |
|------|---------|-------|
| [Gefyra](https://gefyra.dev) | Apache-2.0 | Docker-container-based bridge. Simpler than Telepresence, but less feature-rich than mirrord. No env var/file injection. |
| [kt-connect](https://github.com/alibaba/kt-connect) | Apache-2.0 | Alibaba's K8s dev tunnel. Less active community. |
| [kubefwd](https://github.com/txn2/kubefwd) | Apache-2.0 | Bulk port-forward with DNS. Simple but one-way only. |

---

*Generated from an architectural discussion about remocal microservice
development with Coder. All tools referenced are open source.*
