Based on this Kubernetes/EKS template using envbox, here are the **modified client installation instructions**:

---

## Client Requirements for Coder Workspaces (EKS/Kubernetes Template)

### Required on All Client Machines

**1. Coder CLI** (`coder` binary) - **REQUIRED**
- **Windows**: 
  ```powershell
  winget install Coder.Coder
  ```
  Or download the `.msi` installer from [GitHub releases](https://github.com/coder/coder/releases)

- **macOS/Linux**:
  ```bash
  curl -L https://coder.com/install.sh | sh
  ```

After installation, authenticate:
```bash
coder login https://your-coder-deployment.com
```

### Access Methods

#### 1. **Web Browser** (Zero Install)
No additional software needed! Access via:
- Web Terminal (built-in)
- VS Code Web (via template module)
- JupyterLab (via template module)
- JetBrains Gateway projector

#### 2. **VS Code Desktop**
- Download from [code.visualstudio.com](https://code.visualstudio.com/download)
- Click "VS Code Desktop" button in Coder dashboard
- Coder Remote extension auto-installs on first connection
- Extensions available: GitHub Copilot, Python, Jupyter (pre-configured in template)

Manual extension install:
```
ext install coder.coder-remote
```

#### 3. **JetBrains IDEs via JetBrains Toolbox**
- Download and install [JetBrains Toolbox](https://www.jetbrains.com/toolbox-app/)
- Install your preferred IDE through Toolbox:
  - **PyCharm Professional** (default for this template)
  - **IntelliJ IDEA Ultimate** (default for this template)
  - GoLand, WebStorm, Rider, CLion, etc.
- Open your IDE and install the **Coder** plugin:
  - Go to **Settings/Preferences → Plugins**
  - Search for "Coder" and install
  - Restart IDE
- Connect to workspace:
  - Open Coder plugin in IDE
  - Sign in to your Coder deployment
  - Select workspace and `/home/coder/project` directory

**Alternative: JetBrains Gateway**
- Standalone lightweight client for remote development
- Download from [jetbrains.com/remote-development/gateway](https://www.jetbrains.com/remote-development/gateway/)
- Install Coder plugin and connect to workspace

#### 4. **SSH Access**
After installing Coder CLI:
```bash
coder config-ssh
```

Then connect:
```bash
ssh coder.<workspace-name>
```

**Note**: SSH client usually pre-installed on macOS/Linux. Windows 10+ includes OpenSSH.

### What's Different About This Template

This template uses **envbox** (Docker-in-Kubernetes), so workspaces include:
- Full Docker support inside workspaces
- Base image: `codercom/enterprise-base:ubuntu`
- Pre-configured development stack:
  - Java 17 + Maven + Gradle
  - Node.js (via nvm) + pnpm + Angular CLI
  - Python (via uv) + FastAPI + database drivers
  - VS Code Web, JupyterLab, JetBrains

All dependencies are installed **on first workspace start** and persist across stop/start cycles.

### Quick Start for Users

1. **Install Coder CLI** (Windows: `winget`, Mac/Linux: `curl`)
2. **Login**: `coder login https://your-deployment.com`
3. **Create workspace** via Coder dashboard
4. **Access options**:
   - Browser: Click "VS Code Web" or "JupyterLab"
   - Desktop: Click "VS Code Desktop" (auto-installs extension)
   - JetBrains: Install Toolbox → Install IDE → Install Coder plugin
   - Terminal: `coder ssh <workspace-name>`

### Advanced: Port Forwarding
For local development/testing:
```bash
coder port-forward <workspace-name> --tcp 8000:8000
```

---

**Summary**: Only the **Coder CLI** is strictly required. Everything else (IDEs, SSH) is optional based on user preference. Web-based access requires zero client installation.
