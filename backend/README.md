# Backend Development Template (EKS)

This Coder template provisions a complete backend development environment on Amazon EKS.

## Stack

### Languages & Frameworks
- **Java 17** (OpenJDK) with Maven and Gradle
- **Node.js** (LTS) via nvm for version management
- **Python** with **uv** for fast, reliable package management
- **FastAPI** for building modern web APIs

### Database Clients
- **psycopg2** - PostgreSQL client library for Python
- **cassandra-driver** - Cassandra/ScyllaDB Python driver with vector search support

### IDEs
- **VS Code Web** (code-server) - Port 13337
- **JupyterLab** - Port 8888
- **IntelliJ Toolbox** - Install your preferred JetBrains IDE

## Resource Configuration

Configurable via template parameters:
- **CPU**: 2, 4, 6, or 8 cores (default: 2)
- **Memory**: 4, 8, 16, or 32 GB (default: 4 GB)
- **Disk**: 20, 50, or 100 GB (default: 20 GB)

## Database Clients

The template installs Python client libraries for:
- **PostgreSQL** via `psycopg2-binary`
- **Cassandra** via `cassandra-driver`

Connect to your existing database instances by configuring connection strings in your application.

## Deployment

```bash
coder templates push backend -d ./backend
