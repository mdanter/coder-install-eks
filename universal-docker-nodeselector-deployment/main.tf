terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "coder" {}

variable "use_kubeconfig" {
  type        = bool
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces.  A valid "~/.kube/config" must be present on the Coder host.
  EOF
  default     = false
}

variable "namespace" {
  type        = string
  description = "The Kubernetes namespace to create workspaces in (must exist prior to creating workspaces)"
  default     = "coder"
}

variable "create_tun" {
  type        = bool
  description = "Add a TUN device to the workspace."
  default     = false
}

variable "create_fuse" {
  type        = bool
  description = "Add a FUSE device to the workspace."
  default     = false
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "The number of CPU cores"
  default      = "4"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "2 Cores"
    value = "2"
  }
  option {
    name  = "4 Cores"
    value = "4"
  }
  option {
    name  = "6 Cores"
    value = "6"
  }
  option {
    name  = "8 Cores"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "The amount of memory in GB"
  default      = "8"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "4 GB"
    value = "4"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
  option {
    name  = "16 GB"
    value = "16"
  }
  option {
    name  = "32 GB"
    value = "32"
  }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Disk Size"
  description  = "The size of the disk in GB"
  default      = "50"
  icon         = "/icon/memory.svg"
  mutable      = false
  option {
    name  = "20 GB"
    value = "20"
  }
  option {
    name  = "50 GB"
    value = "50"
  }
  option {
    name  = "100 GB"
    value = "100"
  }
}

provider "kubernetes" {
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"
  
  startup_script = <<-EOT
    #!/bin/bash
    set -e

    # Only run installations once - creates ~/.setup_complete marker
    if [ ! -f ~/.setup_complete ]; then
      echo "🚀 First-time setup - installing development tools..."
      
      # Install Java (OpenJDK 17)
      sudo apt-get update
      sudo apt-get install -y openjdk-17-jdk maven gradle
      export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
      export PATH="$JAVA_HOME/bin:$PATH"

      # Install Node.js (via nvm for version management)
      if [ ! -d "$HOME/.nvm" ]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
      fi
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
      
      # Add NVM to bashrc if not already there
      if ! grep -q "NVM_DIR" ~/.bashrc; then
        echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc
      fi
      
      nvm install --lts
      nvm use --lts

      # Install pnpm for Node.js package management
      npm install -g pnpm
      
      pnpm setup
      source /home/coder/.bashrc

      # Install Angular CLI
      pnpm add -g @angular/cli

      # Install uv for Python package management
      curl -LsSf https://astral.sh/uv/install.sh | sh
      export PATH="$HOME/.local/bin:$PATH"

      # Create Python virtual environment
      if [ ! -d /home/coder/.venv ]; then
        cd /home/coder
        uv venv
      fi
      
      # Auto-activate venv in bashrc
      if ! grep -q ".venv/bin/activate" ~/.bashrc; then
        echo 'source /home/coder/.venv/bin/activate' >> ~/.bashrc
      fi
      
      source .venv/bin/activate

      # Install FastAPI and database drivers
      uv pip install fastapi uvicorn[standard] psycopg2-binary cassandra-driver

      # Mark setup as complete
      touch ~/.setup_complete
      echo "✅ Setup complete!"
    else
      echo "♻️  Using existing setup (run 'rm ~/.setup_complete' to reinstall)"
    fi

    # Auto-cleanup Docker if disk usage is high
    check_disk_and_cleanup() {
      if command -v docker &> /dev/null; then
        DISK_USAGE=$(df /home/coder 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
        if [ ! -z "$DISK_USAGE" ] && [ "$DISK_USAGE" -gt 80 ]; then
          echo "⚠️  Disk usage is high ($${DISK_USAGE}%). Cleaning up Docker..."
          docker system prune -af --volumes || true
          echo "✅ Docker cleanup complete"
        fi
      fi
    }
    check_disk_and_cleanup

    # Docker is available via envbox - you can now use docker commands!
    if command -v docker &> /dev/null; then
      docker --version
    fi
  EOT

  shutdown_script = <<-EOT
    #!/bin/bash
    # Gracefully stop all Docker containers
    if command -v docker &> /dev/null; then
      echo "Stopping Docker containers..."
      docker ps -q | xargs -r docker stop -t 30 || true
      echo "Docker containers stopped"
    fi
  EOT

  metadata {
    display_name = "CPU Usage"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Disk Usage"
    key          = "disk_usage"
    script       = "coder stat disk --path /home/coder"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "Docker Status"
    key          = "docker_status"
    script       = "docker info >/dev/null 2>&1 && echo '✓ Healthy' || echo '✗ Unhealthy'"
    interval     = 30
    timeout      = 5
  }
}

module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.1.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
  default  = ["PY", "IU"]
}

module "vscode-web" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/vscode-web/coder"
  version        = "1.4.1"
  agent_id       = coder_agent.main.id
  extensions     = ["github.copilot", "ms-python.python", "ms-toolsai.jupyter"]
  accept_license = true
}

module "jupyterlab" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jupyterlab/coder"
  version  = "1.2.0"
  agent_id = coder_agent.main.id
}

resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}-home"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-pvc"
      "app.kubernetes.io/instance" = "coder-pvc-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
      "app.kubernetes.io/part-of"  = "coder"
      "coder.owner"                = data.coder_workspace_owner.me.name
      "coder.owner_id"             = data.coder_workspace_owner.me.id
      "coder.workspace_id"         = data.coder_workspace.me.id
      "coder.workspace_name_at_creation" = data.coder_workspace.me.name
    }
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${data.coder_parameter.disk_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "main" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
      "app.kubernetes.io/part-of"  = "coder"
      "coder.owner"                = data.coder_workspace_owner.me.name
      "coder.owner_id"             = data.coder_workspace_owner.me.id
      "coder.workspace_id"         = data.coder_workspace.me.id
      "coder.workspace_name"       = data.coder_workspace.me.name
    }
  }
  
  spec {
    replicas = 1
    
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "coder-workspace"
        "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"     = "coder-workspace"
          "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
          "app.kubernetes.io/part-of"  = "coder"
          "coder.owner"                = data.coder_workspace_owner.me.name
          "coder.owner_id"             = data.coder_workspace_owner.me.id
          "coder.workspace_id"         = data.coder_workspace.me.id
          "coder.workspace_name"       = data.coder_workspace.me.name
        }
      }

      spec {
        # kubectl describe node | grep Labels -A 10
        # edit the label key-value pairs to match this template to nodes
        node_selector = {
          "kubernetes.io/os" = "linux"
          "eks.amazonaws.com/nodegroup-image" = "amazon-linux-2"
        }

        container {
          name              = "dev"
          image             = "ghcr.io/coder/envbox:latest"
          image_pull_policy = "IfNotPresent"
          command           = ["/envbox", "docker"]

          security_context {
            privileged = true
          }

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }

          env {
            name  = "CODER_AGENT_URL"
            value = data.coder_workspace.me.access_url
          }

          env {
            name  = "CODER_INNER_IMAGE"
            value = "index.docker.io/codercom/enterprise-base:ubuntu"
          }

          env {
            name  = "CODER_INNER_USERNAME"
            value = "coder"
          }

          env {
            name  = "CODER_BOOTSTRAP_SCRIPT"
            value = coder_agent.main.init_script
          }

          env {
            name  = "CODER_MOUNTS"
            value = "/home/coder:/home/coder"
          }

          env {
            name  = "CODER_ADD_FUSE"
            value = var.create_fuse
          }

          env {
            name  = "CODER_INNER_HOSTNAME"
            value = data.coder_workspace.me.name
          }

          env {
            name  = "CODER_ADD_TUN"
            value = var.create_tun
          }

          env {
            name = "CODER_CPUS"
            value_from {
              resource_field_ref {
                resource = "limits.cpu"
              }
            }
          }

          env {
            name = "CODER_MEMORY"
            value_from {
              resource_field_ref {
                resource = "limits.memory"
              }
            }
          }

          resources {
            requests = {
              "cpu"    = "${data.coder_parameter.cpu.value}"
              "memory" = "${data.coder_parameter.memory.value}Gi"
            }
            limits = {
              "cpu"    = "${data.coder_parameter.cpu.value * 2}"
              "memory" = "${data.coder_parameter.memory.value * 1.5}Gi"
            }
          }

          volume_mount {
            mount_path = "/home/coder"
            name       = "home"
            read_only  = false
            sub_path   = "home"
          }

          volume_mount {
            mount_path = "/var/lib/coder/docker"
            name       = "home"
            sub_path   = "cache/docker"
          }

          volume_mount {
            mount_path = "/var/lib/coder/containers"
            name       = "home"
            sub_path   = "cache/containers"
          }

          volume_mount {
            mount_path = "/var/lib/sysbox"
            name       = "sysbox"
          }

          volume_mount {
            mount_path = "/var/lib/containers"
            name       = "home"
            sub_path   = "envbox/containers"
          }

          volume_mount {
            mount_path = "/var/lib/docker"
            name       = "home"
            sub_path   = "envbox/docker"
          }

          volume_mount {
            mount_path = "/usr/src"
            name       = "usr-src"
          }

          volume_mount {
            mount_path = "/lib/modules"
            name       = "lib-modules"
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.home.metadata.0.name
            read_only  = false
          }
        }

        volume {
          name = "sysbox"
          empty_dir {}
        }

        volume {
          name = "usr-src"
          host_path {
            path = "/usr/src"
            type = "Directory"
          }
        }

        volume {
          name = "lib-modules"
          host_path {
            path = "/lib/modules"
            type = "Directory"
          }
        }
      }
    }
  }
}
