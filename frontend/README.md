# Frontend Development Template (EKS)

This Coder template provisions a complete frontend development environment on Amazon EKS.

## Stack

### Languages & Frameworks
- **Java 17** (OpenJDK) with Maven and Gradle
- **Node.js** (LTS) managed via **pnpm**
- **Python 3** with pip and venv
- **pnpm** for efficient package management
- **Angular** CLI for building modern web applications

### IDEs
- **VS Code Web** (code-server) - Port 13337
- **JupyterLab** - Port 8888
- **IntelliJ Toolbox** - Install your preferred JetBrains IDE

## Resource Configuration

Configurable via template parameters:
- **CPU**: 2, 4, 6, or 8 cores (default: 2)
- **Memory**: 4, 8, 16, or 32 GB (default: 4 GB)
- **Disk**: 20, 50, or 100 GB (default: 20 GB)

## Pre-installed Tools

- **pnpm** - Fast, disk space efficient package manager
- **Angular CLI** - Command-line interface for Angular
- Node.js LTS version

## Deployment

```bash
coder templates push frontend -d ./frontend
