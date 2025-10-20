# Coder Universal Docker Template - Amazon Linux 2

A Coder workspace template designed for AWS EKS clusters running Amazon Linux 2 nodes. This template provides a full development environment with Docker support via envbox.

## Features

- **Node Selection**: Automatically schedules workspaces on Amazon Linux 2 nodes only
- **Docker Support**: Full Docker-in-Docker capabilities via envbox
- **Pre-installed Tools**:
  - Java (OpenJDK 17) with Maven and Gradle
  - Node.js (via nvm) with pnpm and Angular CLI
  - Python (via uv) with FastAPI and database drivers
  - JupyterLab for data science workflows
- **IDEs**:
  - VS Code Web with GitHub Copilot
  - JetBrains (PyCharm and IntelliJ IDEA)
  - JupyterLab
- **Resource Monitoring**: Built-in CPU, RAM, disk, and Docker health metrics
- **Persistent Storage**: Home directory persisted across workspace restarts
- **Auto-cleanup**: Automatic Docker cleanup when disk usage exceeds 80%

## Prerequisites

### EKS Cluster Requirements

1. **Amazon Linux 2 Node Groups**: Your EKS cluster must have node groups running Amazon Linux 2
2. **Node Labels**: Managed node groups automatically receive the `eks.amazonaws.com/nodegroup-image=amazon-linux-2` label
3. **Kernel Modules**: Nodes must have `/usr/src` and `/lib/modules` directories accessible (standard on Amazon Linux 2)

### Coder Requirements

- Coder v2.0 or later
- Kubernetes namespace (default: `coder`) must exist
- Appropriate RBAC permissions for creating pods and PVCs

## Configuration

### Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `use_kubeconfig` | bool | `false` | Use host kubeconfig file. Set to `true` if Coder is outside the cluster |
| `namespace` | string | `coder` | Kubernetes namespace for workspaces |
| `create_tun` | bool | `false` | Add a TUN device to the workspace |
| `create_fuse` | bool | `false` | Add a FUSE device to the workspace |

### Workspace Parameters

Users can customize their workspace at creation time:

- **CPU**: 2, 4, 6, or 8 cores (default: 4)
- **Memory**: 4, 8, 16, or 32 GB (default: 8 GB)
- **Disk Size**: 20, 50, or 100 GB (default: 50 GB) - immutable after creation

## Node Selector Configuration

This template uses the following node selectors:

```hcl
node_selector = {
  "kubernetes.io/os" = "linux"
  "eks.amazonaws.com/nodegroup-image" = "amazon-linux-2"
}
```

### Custom Node Labels

If your nodes use different labels, modify the `node_selector` block in `main.tf`:

```hcl
# For custom labels
node_selector = {
  "node.kubernetes.io/instance-type" = "m5.2xlarge"  # Specific instance type
  "environment" = "development"                       # Custom label
}

# For Amazon Linux 2023
node_selector = {
  "eks.amazonaws.com/nodegroup-image" = "amazon-linux-2023"
}
```

### Verifying Node Labels

Check your nodes have the correct labels:

```bash
kubectl get nodes --show-labels | grep amazon-linux
```

Or describe a specific node:

```bash
kubectl describe node <node-name> | grep Labels -A 10
```

## Installation

1. **Clone or download** this template:
   ```bash
   git clone <repository-url>
   cd amazon-linux-template
   ```

2. **Create the template** in Coder:
   ```bash
   coder templates create amazon-linux-docker
   ```

3. **Create a workspace** from the template:
   ```bash
   coder create my-workspace --template amazon-linux-docker
   ```

## Usage

### First-Time Setup

The workspace automatically installs all development tools on first startup. This takes a few minutes and creates a `~/.setup_complete` marker file.

To reinstall tools:
```bash
rm ~/.setup_complete
# Restart the workspace
```

### Docker Usage

Docker is available via envbox:

```bash
# Check Docker status
docker --version
docker ps

# Run containers
docker run -it ubuntu bash

# Build images
docker build -t myapp .
```

### Python Development

Python environment is automatically activated:

```bash
# Virtual environment is at /home/coder/.venv
python --version
uv pip install <package>
```

### Node.js Development

```bash
# NVM is installed
nvm list
nvm use --lts

# pnpm is available
pnpm install
pnpm dev
```

### Java Development

```bash
# OpenJDK 17 is installed
java --version
mvn --version
gradle --version
```

## Resource Management

### CPU and Memory Limits

- **Requests**: As specified in workspace parameters
- **Limits**: 
  - CPU: 2x the requested cores (allows bursting)
  - Memory: 1.5x the requested memory (headroom)

### Disk Management

The template monitors disk usage and automatically runs `docker system prune` when usage exceeds 80%.

Manual cleanup:
```bash
docker system prune -af --volumes
```

### Monitoring

The workspace exposes metrics visible in the Coder dashboard:
- CPU usage (updated every 10s)
- RAM usage (updated every 10s)
- Disk usage (updated every 60s)
- Docker health (updated every 30s)

## Troubleshooting

### Workspace Stuck in "Pending"

**Cause**: No Amazon Linux 2 nodes available in the cluster.

**Solution**:
1. Check node labels: `kubectl get nodes --show-labels`
2. Verify node groups are running Amazon Linux 2
3. Check node group has capacity

### Docker Commands Fail

**Cause**: Envbox may not have started properly.

**Solution**:
1. Check Docker status in workspace metrics
2. Restart the workspace
3. Check pod logs: `kubectl logs -n coder <pod-name>`

### Out of Disk Space

**Cause**: Docker images/containers consuming storage.

**Solution**:
```bash
# Manual cleanup
docker system prune -af --volumes

# Or remove setup and reinstall
rm ~/.setup_complete
# Restart workspace
```

### Tools Not Installed

**Cause**: First-time setup incomplete or failed.

**Solution**:
```bash
# Force reinstall
rm ~/.setup_complete
# Restart workspace or run manually
bash -c "$(cat /path/to/startup_script.sh)"
```

## Customization

### Add More Tools

Edit the `startup_script` in `main.tf`:

```hcl
startup_script = <<-EOT
  #!/bin/bash
  set -e
  
  if [ ! -f ~/.setup_complete ]; then
    # Add your installation commands here
    sudo apt-get install -y your-package
    
    touch ~/.setup_complete
  fi
EOT
```

### Change Inner Image

Modify the `CODER_INNER_IMAGE` environment variable:

```hcl
env {
  name  = "CODER_INNER_IMAGE"
  value = "index.docker.io/your-custom-image:tag"
}
```

### Add VS Code Extensions

Edit the `vscode-web` module:

```hcl
module "vscode-web" {
  extensions = [
    "github.copilot",
    "ms-python.python",
    "your.extension-id"
  ]
}
```

## Architecture

```
┌─────────────────────────────────────────┐
│         Kubernetes Pod (privileged)     │
│  ┌───────────────────────────────────┐  │
│  │   Envbox Container                │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │  Inner Container (Ubuntu)   │  │  │
│  │  │  - Coder Agent              │  │  │
│  │  │  - Development Tools        │  │  │
│  │  │  - User Environment         │  │  │
│  │  └─────────────────────────────┘  │  │
│  │   Docker-in-Docker via Envbox     │  │
│  └───────────────────────────────────┘  │
│                                         │
│  Persistent Volume: /home/coder         │
│  Host Mounts: /usr/src, /lib/modules    │
└─────────────────────────────────────────┘
         ↓ Scheduled on ↓
┌─────────────────────────────────────────┐
│   Amazon Linux 2 Node (EKS)             │
│   Label: eks.amazonaws.com/             │
│          nodegroup-image=amazon-linux-2 │
└─────────────────────────────────────────┘
```

## Security Considerations

- **Privileged Containers**: This template uses privileged containers for Docker-in-Docker support
- **Host Path Mounts**: Mounts `/usr/src` and `/lib/modules` from the host
- **Network Access**: Workspaces have full network access
- **Resource Limits**: Configure appropriate CPU/memory limits for your use case

## License

Based on the [Coder Universal Docker template](https://github.com/mdanter/coder-install-eks/blob/main/universal-docker/main.tf).

## Support

For issues and questions:
- Coder Documentation: https://coder.com/docs
- Coder Community: https://github.com/coder/coder/discussions
- EKS Documentation: https://docs.aws.amazon.com/eks/
```
