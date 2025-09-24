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

variable "use_kubeconfig" {
  type        = bool
  description = "Use host kubeconfig? (true/false)"
  default     = false
}

variable "workspaces_namespace" {
  type        = string
  description = "The namespace to create workspaces in (must exist prior to creating workspaces). Default value takes from coder managed namespace."
  default     = ""
}

variable "home_disk_size" {
  type        = number
  description = "Size of the home disk in GB"
  default     = 20
  validation {
    condition     = var.home_disk_size >= 10 && var.home_disk_size <= 1000
    error_message = "Home disk size must be between 10 and 1000 GB."
  }
}

variable "cpu" {
  type        = number
  description = "CPU cores for the workspace"
  default     = 2
  validation {
    condition     = var.cpu >= 1 && var.cpu <= 16
    error_message = "CPU must be between 1 and 16 cores."
  }
}

variable "memory" {
  type        = number
  description = "Memory in GB for the workspace"
  default     = 4
  validation {
    condition     = var.memory >= 2 && var.memory <= 64
    error_message = "Memory must be between 2 and 64 GB."
  }
}

variable "image" {
  type        = string
  description = "Container image to use for the workspace"
  default     = "codercom/enterprise-base:ubuntu"
  validation {
    condition = contains([
      "codercom/enterprise-base:ubuntu",
      "codercom/enterprise-jupyter:latest",
      "jupyter/datascience-notebook:latest",
      "codercom/enterprise-node:latest"
    ], var.image)
    error_message = "Please select a supported image."
  }
}

data "coder_provisioner" "me" {
}

data "coder_workspace" "me" {
}

data "coder_workspace_owner" "me" {
}

# External auth for GitHub integration
data "coder_external_auth" "github" {
  id = "github"
}

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific cluster
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

resource "coder_agent" "main" {
  arch                   = data.coder_provisioner.me.arch
  os                     = "linux"
  startup_script_timeout = 180
  startup_script         = <<-EOT
    set -e

    # Install/start code-server
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.19.1
    /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &

    # Install JupyterLab if not present
    if ! command -v jupyter &> /dev/null; then
      echo "Installing JupyterLab..."
      pip3 install --user jupyterlab ipykernel matplotlib pandas numpy seaborn plotly
      python3 -m ipykernel install --user --name python3
    fi

    # Start JupyterLab
    jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root \
      --ServerApp.token='' --ServerApp.password='' \
      --ServerApp.allow_origin='*' \
      --ServerApp.disable_check_xsrf=True >/tmp/jupyter.log 2>&1 &

    # Configure Git if GitHub token is available
    if [ -n "${data.coder_external_auth.github.access_token}" ]; then
      git config --global credential.helper 'store --file=/tmp/.git-credentials'
      echo "https://oauth2:${data.coder_external_auth.github.access_token}@github.com" > /tmp/.git-credentials
      git config --global user.name "${data.coder_workspace_owner.me.name}"
      git config --global user.email "${data.coder_workspace_owner.me.email}"
    fi

    # Install common development tools
    sudo apt-get update
    sudo apt-get install -y git curl wget vim htop tree jq unzip

    # Install Docker if not present
    if ! command -v docker &> /dev/null; then
      curl -fsSL https://get.docker.com | sh
      sudo usermod -aG docker coder
    fi
  EOT

  # These environment variables allow you to make Git commits right away after creating a
  # workspace. Note that they take precedence over configuration in Git's global config!
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_memory_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg
    script   = "uptime | awk -F'load average:' '{print $2}'"
    interval = 60
    timeout  = 1
  }

  metadata {
    display_name = "Disk Usage (Host)"
    key          = "7_disk_host"
    script       = "coder stat disk --path / --host"
    interval     = 60
    timeout      = 1
  }
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://localhost:13337/?folder=/home/coder"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "coder_app" "jupyter" {
  agent_id     = coder_agent.main.id
  slug         = "jupyter"
  display_name = "JupyterLab"
  url          = "http://localhost:8888"
  icon         = "https://upload.wikimedia.org/wikipedia/commons/3/38/Jupyter_logo.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8888/api/status"
    interval  = 10
    threshold = 3
  }
}

resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}-home"
    namespace = var.workspaces_namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-pvc"
      "app.kubernetes.io/instance" = "coder-pvc-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
      "app.kubernetes.io/component" = "dev-workspace"
    }
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${var.home_disk_size}Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "main" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.workspaces_namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
      "app.kubernetes.io/component" = "dev-workspace"
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
        }
      }

      spec {
        security_context {
          run_as_user = "1000"
          fs_group    = "1000"
        }

        container {
          name              = "dev"
          image             = var.image
          image_pull_policy = "Always"
          command           = ["sh", "-c", coder_agent.main.init_script]
          security_context {
            run_as_user = "1000"
          }
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          env {
            name  = "GITHUB_TOKEN"
            value = data.coder_external_auth.github.access_token
          }
          resources {
            requests = {
              "cpu"    = "${var.cpu}"
              "memory" = "${var.memory}Gi"
            }
            limits = {
              "cpu"    = "${var.cpu}"
              "memory" = "${var.memory}Gi"
            }
          }
          volume_mount {
            mount_path = "/home/coder"
            name       = "home"
            read_only  = false
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.home.metadata.0.name
            read_only  = false
          }
        }

        affinity {
          # This affinity attempts to spread out all workspace pods evenly across
          # nodes.
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["coder-workspace"]
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "main" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.workspaces_namespace
  }
  spec {
    selector = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    }
    port {
      name        = "ssh"
      port        = 22
      protocol    = "TCP"
      target_port = 22
    }
  }
}

resource "coder_metadata" "workspace_info" {
  resource_id = kubernetes_deployment.main[0].id

  item {
    key   = "image"
    value = var.image
  }

  item {
    key   = "cpu"
    value = "${var.cpu} cores"
  }

  item {
    key   = "memory"
    value = "${var.memory}GB"
  }

  item {
    key   = "disk"
    value = "${var.home_disk_size}GB"
  }

  item {
    key   = "github_authenticated"
    value = data.coder_external_auth.github.access_token != "" ? "✅" : "❌"
  }
}