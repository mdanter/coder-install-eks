# Coder Template: Universal Development Environment with Docker-in-Docker (Envbox)

This Coder template provides a comprehensive development environment with full Docker-in-Docker capabilities using [envbox](https://github.com/coder/envbox). It supports Java, Node.js, Python development with JetBrains IDEs, VS Code, and JupyterLab.

## Features

### Development Tools
- **Java**: OpenJDK 17, Maven, Gradle
- **Node.js**: NVM for version management, pnpm package manager, Angular CLI
- **Python**: uv for fast package management, FastAPI, database drivers (PostgreSQL, Cassandra)

### IDEs & Editors
- **VS Code Web**: Browser-based VS Code with Copilot, Python, and Jupyter extensions
- **JetBrains**: PyCharm and IntelliJ IDEA support
- **JupyterLab**: Interactive notebook environment

### Docker Support
- **Full Docker-in-Docker**: Run Docker commands and containers within your workspace
- **Envbox**: No privileged access required on Kubernetes nodes
- **Isolated environments**: Each workspace has its own Docker daemon

## What is Envbox?

Envbox is a privileged container that manages the sysbox runtime and spawns an unprivileged inner container that acts as the user's workspace. The inner container can run system-level software similar to a virtual machine (e.g., `systemd`, `dockerd`, etc.).

### Benefits of Envbox:
- ✅ No custom runtime installation on Kubernetes nodes
- ✅ No node-level configuration changes required
- ✅ Better isolation between workspaces
- ✅ Simplified cluster management
- ✅ Full Docker capabilities without compromising cluster security

## Prerequisites

- Coder deployment on Kubernetes
- Kubernetes namespace for workspaces (default: `coder`)
- Sufficient cluster resources for privileged containers
- Storage class that supports `ReadWriteOnce` persistent volumes

## Configuration

### Template Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `use_kubeconfig` | Use host kubeconfig vs in-cluster auth | `false` |
| `namespace` | Kubernetes namespace for workspaces | `coder` |
| `create_tun` | Add TUN device to workspace | `false` |
| `create_fuse` | Add FUSE device to workspace | `false` |

### User Parameters

| Parameter | Description | Options |
|-----------|-------------|---------|
| `cpu` | Number of CPU cores | 2, 4, 6, 8 |
| `memory` | Memory in GB | 4, 8, 16, 32 |
| `disk_size` | Persistent disk size in GB | 20, 50, 100 |

## Usage

### Creating a Workspace

1. Select this template when creating a new workspace
2. Choose your desired CPU, memory, and disk size
3. Start the workspace
4. Access via VS Code Web, JetBrains Gateway, or terminal

### Using Docker

Once your workspace is running, Docker is immediately available:

```bash
# Check Docker version
docker --version

# Run a container
docker run hello-world

# Build an image
docker build -t myapp .

# Use docker-compose
docker-compose up
