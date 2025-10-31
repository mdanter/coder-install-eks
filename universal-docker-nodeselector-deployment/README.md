# Universal Docker Workspace Template (Deployment-based)

A Coder template for provisioning development workspaces on Kubernetes using Deployments with Docker-in-Docker capabilities via envbox.

## Features

- **Docker-in-Docker**: Full Docker support using [envbox](https://github.com/coder/envbox)
- **Persistent Storage**: User home directory persisted across workspace restarts
- **Resource Flexibility**: Configurable CPU, memory, and disk size
- **Multi-Language Support**: Pre-configured for Java, Node.js, Python, and more
- **IDE Integration**: Built-in support for JetBrains IDEs, VS Code Web, and JupyterLab
- **Automatic Monitoring**: CPU, RAM, disk usage, and Docker health metrics
- **Node Selection**: Targets specific EKS node groups using labels

## Prerequisites

- Coder deployment (v2.0+)
- Kubernetes cluster with:
  - Nodes labeled with `kubernetes.io/os=linux` and `eks.amazonaws.com/nodegroup-image=amazon-linux-2`
  - Support for privileged containers
  - A StorageClass for dynamic PVC provisioning
- `coder` namespace created in Kubernetes (or customize via variables)

## Template Parameters

### User-Configurable (at workspace creation)

| Parameter | Description | Options | Default |
|-----------|-------------|---------|------------|
| `cpu` | Number of CPU cores | 2, 4, 6, 8 | 4 |
| `memory` | RAM in GB | 4, 8, 16, 32 | 8 |
| `disk_size` | Persistent disk size in GB | 20, 50, 100 | 50 |

### Template Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `use_kubeconfig` | Use host kubeconfig (true) or in-cluster auth (false) | `false` |
| `namespace` | Kubernetes namespace for workspaces | `coder` |
| `create_tun` | Add TUN device to workspace | `false` |
| `create_fuse` | Add FUSE device to workspace | `false` |

## Pre-installed Development Tools

The workspace automatically installs on first startup:

- **Java**: OpenJDK 17, Maven, Gradle
- **Node.js**: Latest LTS via nvm, pnpm, Angular CLI
- **Python**: uv package manager, FastAPI, uvicorn, database drivers (psycopg2, cassandra-driver)
- **Docker**: Available via envbox

Tools are only installed once (tracked by `~/.setup_complete` marker file).

## Resource Allocation

Resource requests and limits:

- **CPU**: Request = selected cores, Limit = 2x selected cores
- **Memory**: Request = selected GB, Limit = 1.5x selected GB
- **Disk**: Persistent volume claim of selected size

## Deployment vs Pod Architecture

This template uses a Kubernetes Deployment instead of a bare Pod:

### Benefits

- **Automatic Recovery**: Failed pods are automatically recreated
- **Consistent State Management**: Deployment controller ensures desired state
- **Rolling Updates**: Supports controlled workspace updates (though typically not needed)
- **Better Observability**: Standard Kubernetes deployment tooling works out of the box

### Deployment Configuration

- **Replicas**: 1 (single pod per workspace)
- **Strategy**: `Recreate` (required for ReadWriteOnce PVCs)
- **Selector**: Matches on workspace-specific labels

## Node Selector Configuration

The template targets nodes with these labels:

```hcl
node_selector = {
  "kubernetes.io/os" = "linux"
  "eks.amazonaws.com/nodegroup-image" = "amazon-linux-2"
}
```

**To customize**: Edit the `node_selector` block in `main.tf` to match your node labels. View available labels:

```bash
kubectl describe node | grep Labels -A 10
```

## Volume Mounts

| Mount Path | Source | Purpose |
|------------|--------|------------|
| `/home/coder` | PVC subPath: `home` | User home directory |
| `/var/lib/coder/docker` | PVC subPath: `cache/docker` | Docker build cache |
| `/var/lib/coder/containers` | PVC subPath: `cache/containers` | Container cache |
| `/var/lib/sysbox` | emptyDir | Sysbox runtime |
| `/var/lib/containers` | PVC subPath: `envbox/containers` | Envbox containers |
| `/var/lib/docker` | PVC subPath: `envbox/docker` | Envbox Docker storage |
| `/usr/src` | hostPath | Kernel headers |
| `/lib/modules` | hostPath | Kernel modules |

## Usage

### 1. Push Template to Coder

```bash
coder templates push eks-universal-docker
```

### 2. Create Workspace

```bash
coder create my-workspace --template eks-universal-docker
```

Or use the Coder web UI.

### 3. Connect to Workspace

```bash
coder ssh my-workspace
```

Or connect via VS Code, JetBrains Gateway, or the web terminal.

## Monitoring & Metrics

The workspace reports these metrics to Coder:

- **CPU Usage**: Updated every 10 seconds
- **RAM Usage**: Updated every 10 seconds  
- **Disk Usage**: Updated every 60 seconds
- **Docker Health**: Updated every 30 seconds

## Automatic Maintenance

### Disk Cleanup

If disk usage exceeds 80%, Docker artifacts are automatically pruned:

```bash
docker system prune -af --volumes
```

### Shutdown Script

On workspace stop, all Docker containers are gracefully stopped (30s timeout).

## Troubleshooting

### Reinstall Development Tools

```bash
rm ~/.setup_complete
# Stop and start the workspace to trigger reinstall
```

### Check Docker Status

```bash
docker info
```

### View Setup Logs

The startup script output is available in the Coder agent logs.

### Pod Not Scheduling

Check node labels match the template's `node_selector`:

```bash
kubectl get nodes --show-labels
```

Verify the namespace exists:

```bash
kubectl get namespace coder
```

### Deployment Not Creating Pods

Check deployment status:

```bash
kubectl -n coder get deployment coder-<username>-<workspace>
kubectl -n coder describe deployment coder-<username>-<workspace>
```

Check events:

```bash
kubectl -n coder get events --sort-by='.lastTimestamp'
```

## Security Considerations

- **Privileged Containers**: Required for Docker-in-Docker via envbox
- **Host Mounts**: Kernel modules and sources mounted read-only
- **Network**: Pods have full network access by default

## Customization

### Change Inner Container Image

Edit the `CODER_INNER_IMAGE` environment variable:

```hcl
env {
  name  = "CODER_INNER_IMAGE"
  value = "your-registry.com/your-image:tag"
}
```

### Add Additional IDE Modules

Add more module blocks (e.g., for additional JetBrains IDEs):

```hcl
module "goland" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.1.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
  default  = ["GO"]
}
```

### Modify Startup Script

Edit the `startup_script` in the `coder_agent` resource to add or remove tools.

## License

This template is provided as-is for use with Coder workspaces.
