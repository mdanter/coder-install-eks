# Universal Development Template (EKS)

This Coder template provisions a complete full-stack development environment on Amazon EKS with both backend and frontend capabilities.

## Stack

### Languages
- **Java 17** (OpenJDK) with Maven and Gradle
- **Node.js** (LTS) via nvm for version management
- **Python** with **uv** for fast, reliable package management

### Backend Frameworks & Tools
- **FastAPI** for building modern web APIs
- **psycopg2** - PostgreSQL client library
- **cassandra-driver** - Cassandra/ScyllaDB Python driver

### Frontend Frameworks & Tools
- **pnpm** for efficient package management
- **Angular** CLI for building modern web applications

### IDEs
- **VS Code Web** (code-server) - Port 13337
- **JupyterLab** - Port 8888
- **IntelliJ Toolbox** - Install your preferred JetBrains IDE

## Resource Configuration

Configurable via template parameters (higher defaults due to combined stack):
- **CPU**: 2, 4, 6, or 8 cores (default: 4)
- **Memory**: 4, 8, 16, or 32 GB (default: 8 GB)
- **Disk**: 20, 50, or 100 GB (default: 50 GB)

## Database Clients

The template installs Python client libraries for:
- **PostgreSQL** via `psycopg2-binary`
- **Cassandra** via `cassandra-driver`

Connect to your existing database instances by configuring connection strings in your application.

## Deployment

```bash
coder templates push universal -d ./universal
