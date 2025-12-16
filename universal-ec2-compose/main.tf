terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    cloudinit = {
      source = "hashicorp/cloudinit"
    }
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "coder_parameter" "region" {
  name         = "region"
  display_name = "Region"
  description  = "The region to deploy the workspace in."
  default      = "us-east-1"
  mutable      = false
  option {
    name  = "Asia Pacific (Tokyo)"
    value = "ap-northeast-1"
    icon  = "/emojis/1f1ef-1f1f5.png"
  }
  option {
    name  = "Asia Pacific (Seoul)"
    value = "ap-northeast-2"
    icon  = "/emojis/1f1f0-1f1f7.png"
  }
  option {
    name  = "Asia Pacific (Osaka)"
    value = "ap-northeast-3"
    icon  = "/emojis/1f1ef-1f1f5.png"
  }
  option {
    name  = "Asia Pacific (Mumbai)"
    value = "ap-south-1"
    icon  = "/emojis/1f1ee-1f1f3.png"
  }
  option {
    name  = "Asia Pacific (Singapore)"
    value = "ap-southeast-1"
    icon  = "/emojis/1f1f8-1f1ec.png"
  }
  option {
    name  = "Asia Pacific (Sydney)"
    value = "ap-southeast-2"
    icon  = "/emojis/1f1e6-1f1fa.png"
  }
  option {
    name  = "Canada (Central)"
    value = "ca-central-1"
    icon  = "/emojis/1f1e8-1f1e6.png"
  }
  option {
    name  = "EU (Frankfurt)"
    value = "eu-central-1"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
  option {
    name  = "EU (Stockholm)"
    value = "eu-north-1"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
  option {
    name  = "EU (Ireland)"
    value = "eu-west-1"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
  option {
    name  = "EU (London)"
    value = "eu-west-2"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
  option {
    name  = "EU (Paris)"
    value = "eu-west-3"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
  option {
    name  = "South America (São Paulo)"
    value = "sa-east-1"
    icon  = "/emojis/1f1e7-1f1f7.png"
  }
  option {
    name  = "US East (N. Virginia)"
    value = "us-east-1"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "US East (Ohio)"
    value = "us-east-2"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "US West (N. California)"
    value = "us-west-1"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "US West (Oregon)"
    value = "us-west-2"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
}

data "coder_parameter" "instance_type" {
  name         = "instance_type"
  display_name = "Instance type"
  description  = "What instance type should your workspace use?"
  default      = "m5.2xlarge"
  mutable      = false
  option {
    name  = "2 vCPU, 4 GiB RAM"
    value = "t3.medium"
  }
  option {
    name  = "2 vCPU, 8 GiB RAM"
    value = "t3.large"
  }
  option {
    name  = "4 vCPU, 16 GiB RAM"
    value = "t3.xlarge"
  }
  option {
    name  = "8 vCPU, 32 GiB RAM"
    value = "t3.2xlarge"
  }
  option {
    name  = "8 vCPU, 16 GiB RAM (Compute Optimized)"
    value = "c5.2xlarge"
  }
  option {
    name  = "8 vCPU, 32 GiB RAM (General Purpose)"
    value = "m5.2xlarge"
  }
  option {
    name  = "8 vCPU, 64 GiB RAM (Memory Optimized)"
    value = "r5.2xlarge"
  }
  option {
    name  = "16 vCPU, 64 GiB RAM"
    value = "m5.4xlarge"
  }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Disk Size"
  description  = "The size of the root disk in GB"
  default      = "100"
  icon         = "/icon/database.svg"
  mutable      = false
  option {
    name  = "50 GB"
    value = "50"
  }
  option {
    name  = "100 GB"
    value = "100"
  }
  option {
    name  = "200 GB"
    value = "200"
  }
  option {
    name  = "500 GB"
    value = "500"
  }
}

provider "aws" {
  region = data.coder_parameter.region.value
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

resource "coder_agent" "dev" {
  count          = data.coder_workspace.me.start_count
  arch           = "amd64"
  auth           = "aws-instance-identity"
  os             = "linux"

  startup_script = <<-EOT
    #!/bin/bash
    set -e

    # Only run installations once - creates ~/.setup_complete marker
    if [ ! -f "$HOME/.setup_complete" ]; then
      echo "🚀 First-time setup - installing development tools..."
      
      # Install Java (OpenJDK 17)
      sudo apt-get update
      sudo apt-get install -y openjdk-17-jdk maven gradle
      export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
      export PATH="$JAVA_HOME/bin:$PATH"

      # Install Node.js (via nvm for version management)
      if [ ! -d "$HOME/.nvm" ]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
      fi
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
      
      # Add NVM to bashrc if not already there
      if ! grep -q "NVM_DIR" "$HOME/.bashrc"; then
        echo 'export NVM_DIR="$HOME/.nvm"' >> "$HOME/.bashrc"
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> "$HOME/.bashrc"
      fi
      
      nvm install --lts
      nvm use --lts

      # Install pnpm for Node.js package management
      npm install -g pnpm
      
      pnpm setup
      source "$HOME/.bashrc"

      # Install Angular CLI
      pnpm add -g @angular/cli

      # Install uv for Python package management
      curl -LsSf https://astral.sh/uv/install.sh | sh
      export PATH="$HOME/.local/bin:$PATH"

      # Create Python virtual environment
      if [ ! -d "$HOME/.venv" ]; then
        cd "$HOME"
        uv venv
      fi
      
      # Auto-activate venv in bashrc
      if ! grep -q ".venv/bin/activate" "$HOME/.bashrc"; then
        echo 'source "$HOME/.venv/bin/activate"' >> "$HOME/.bashrc"
      fi
      
      source "$HOME/.venv/bin/activate"

      # Install FastAPI and database drivers
      uv pip install fastapi uvicorn[standard] psycopg2-binary cassandra-driver

      # Install Docker and Docker Compose
      sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      sudo apt-get update
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin
      sudo usermod -aG docker coder

      # Verify Docker Compose is available (use sudo since group not active yet)
      sudo docker compose version

      # Mark setup as complete
      touch "$HOME/.setup_complete"
      echo "✅ Setup complete!"
    else
      echo "♻️  Using existing setup (run 'rm ~/.setup_complete' to reinstall)"
    fi

    # Auto-cleanup Docker if disk usage is high
    check_disk_and_cleanup() {
      if command -v docker &> /dev/null; then
        DISK_USAGE=$(df "$HOME" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
        if [ ! -z "$DISK_USAGE" ] && [ "$DISK_USAGE" -gt 80 ]; then
          echo "⚠️  Disk usage is high ($${DISK_USAGE}%). Cleaning up Docker..."
          sudo docker system prune -af --volumes || true
          echo "✅ Docker cleanup complete"
        fi
      fi
    }
    check_disk_and_cleanup

    # Verify Docker is available
    if command -v docker &> /dev/null; then
      sudo docker --version
      sudo docker compose version
    fi
  EOT

  shutdown_script = <<-EOT
    #!/bin/bash
    # Gracefully stop all Docker containers
    if command -v docker &> /dev/null; then
      echo "Stopping Docker containers..."
      sudo docker ps -q | xargs -r sudo docker stop -t 30 || true
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
    script       = "coder stat disk --path $HOME"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "Docker Status"
    key          = "docker_status"
    script       = "sudo docker info >/dev/null 2>&1 && echo '✓ Healthy' || echo '✗ Unhealthy'"
    interval     = 30
    timeout      = 5
  }
}

module "jetbrains" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/jetbrains/coder"
  version    = "~> 1.0"
  agent_id   = coder_agent.dev[0].id
  agent_name = "dev"
  folder     = "/home/coder"
  default    = ["PY", "IU"]
}

module "vscode-web" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/vscode-web/coder"
  version        = "~> 1.0"
  agent_id       = coder_agent.dev[0].id
  extensions     = ["github.copilot", "ms-python.python", "ms-toolsai.jupyter"]
  accept_license = true
}

module "jupyterlab" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jupyterlab/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.dev[0].id
}

locals {
  hostname   = lower(data.coder_workspace.me.name)
  linux_user = "coder"
}

data "cloudinit_config" "user_data" {
  gzip          = false
  base64_encode = false

  boundary = "//"

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile("${path.module}/cloud-init/cloud-config.yaml.tftpl", {
      hostname   = local.hostname
      linux_user = local.linux_user
    })
  }

  part {
    filename     = "userdata.sh"
    content_type = "text/x-shellscript"

    content = templatefile("${path.module}/cloud-init/userdata.sh.tftpl", {
      linux_user  = local.linux_user
      init_script = try(coder_agent.dev[0].init_script, "")
    })
  }
}

resource "aws_instance" "dev" {
  ami               = data.aws_ami.ubuntu.id
  availability_zone = "${data.coder_parameter.region.value}a"
  instance_type     = data.coder_parameter.instance_type.value

  user_data = data.cloudinit_config.user_data.rendered

  root_block_device {
    volume_size = data.coder_parameter.disk_size.value
    volume_type = "gp3"
  }

  tags = {
    Name              = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
    Coder_Provisioned = "true"
  }
  lifecycle {
    ignore_changes = [ami]
  }
}

resource "coder_metadata" "workspace_info" {
  resource_id = aws_instance.dev.id
  item {
    key   = "region"
    value = data.coder_parameter.region.value
  }
  item {
    key   = "instance type"
    value = aws_instance.dev.instance_type
  }
  item {
    key   = "disk"
    value = "${aws_instance.dev.root_block_device[0].volume_size} GiB"
  }
}

resource "aws_ec2_instance_state" "dev" {
  instance_id = aws_instance.dev.id
  state       = data.coder_workspace.me.transition == "start" ? "running" : "stopped"
}
