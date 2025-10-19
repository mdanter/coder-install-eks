# Universal Development Environment with Docker-in-Docker (Multi-OS)

A production-ready Coder template providing a comprehensive development environment with full Docker-in-Docker capabilities using [envbox](https://github.com/coder/envbox). **Optimized for all EKS node operating systems** including Amazon Linux 2023, Bottlerocket, and Ubuntu.

## Features

### Development Stack
- **Java**: OpenJDK 17, Maven, Gradle
- **Node.js**: NVM for version management, pnpm, Angular CLI
- **Python**: uv package manager, FastAPI, PostgreSQL/Cassandra drivers
- **Docker**: Full Docker-in-Docker via envbox with persistent cache

### IDEs & Tools
- **VS Code Web**: Browser-based with Copilot, Python, and Jupyter extensions
- **JetBrains**: PyCharm and IntelliJ IDEA support via Gateway
- **JupyterLab**: Interactive notebooks

### Production Features
- **Fast Restarts**: 10x faster after first start (idempotent setup)
- **Auto-Cleanup**: Automatic Docker pruning at 80% disk usage
- **Graceful Shutdowns**: Containers stop cleanly with 30s timeout
- **Health Monitoring**: Real-time Docker status in UI
- **Multi-OS Support**: Works on AL2023, Bottlerocket, and Ubuntu nodes
- **Persistent Shell Config**: NVM and Python venv auto-activate

##For Bottlerocket

Bottlerocket: "cannot clone: Invalid argument"
User namespaces not enabled. Add to user data:
```
[
settings.kernel.sysctl
]
"user.max_user_namespaces" = "65536"
```
