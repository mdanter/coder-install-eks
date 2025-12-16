# AWS Linux Development Workspace (with Prebuilds)

A full-featured AWS EC2 development environment with Docker, multiple language runtimes, IDE integrations, and **prebuilt workspaces for instant availability**.

## Features

- **Compute**: Configurable instance types from 2 vCPU/4GB to 16 vCPU/64GB (default: m5.2xlarge - 8 vCPU, 32GB RAM)
- **Storage**: Configurable root disk from 50GB to 500GB (default: 100GB, gp3)
- **Regions**: 17 AWS regions available
- **Prebuilds**: 2 ready-to-claim workspaces maintained automatically

### Pre-installed Development Tools

| Category | Tools |
|----------|-------|
| **Languages** | Java 17 (OpenJDK), Node.js LTS (via nvm), Python 3 (via uv) |
| **Build Tools** | Maven, Gradle, pnpm, Angular CLI |
| **Containers** | Docker CE, Docker Compose, Docker Buildx |
| **Python** | FastAPI, Uvicorn, psycopg2, cassandra-driver |

### IDE Integrations

- **VS Code** (code-server) - browser-based
- **VS Code Web** - with GitHub Copilot, Python, Jupyter extensions
- **JetBrains** - PyCharm and IntelliJ IDEA
- **JupyterLab** - for notebook workflows

## Prebuilds

This template maintains **2 prebuilt workspaces** ready for instant claiming. When a user creates a workspace with the default preset, they receive a pre-provisioned instance immediately instead of waiting for infrastructure creation.

### Prebuild Configuration

| Setting | Value |
|---------|-------|
| Instances | 2 |
| TTL | 24 hours |
| Preset | us-east-1, m5.2xlarge, 100GB |

### How It Works

1. Coder automatically provisions and maintains 2 idle workspaces
2. When a user creates a workspace with matching parameters, they claim a prebuilt instance
3. Prebuilt workspaces are rebuilt every 24 hours to stay fresh
4. If all prebuilds are claimed, new workspaces provision normally

### Cost Considerations

Prebuilt workspaces incur costs while idle. With 2x m5.2xlarge instances:
- ~$0.384/hour × 2 = ~$0.77/hour for prebuilds
- ~$554/month if running 24/7

Consider adjusting `instances` count based on team size and usage patterns.

## Prerequisites

1. AWS credentials configured for Coder provisioner
2. IAM permissions for EC2 instance management
3. VPC with internet access (for package installation)
4. **Coder Enterprise license** (prebuilds require Enterprise)

## Required Files

This template requires cloud-init files in `cloud-init/` directory:

### `cloud-init/cloud-config.yaml.tftpl`

```yaml
#cloud-config
hostname: ${hostname}
users:
  - name: ${linux_user}
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: [sudo, docker]
```

### `cloud-init/userdata.sh.tftpl`

```bash
#!/bin/bash
set -euo pipefail

# Create user home directory
mkdir -p /home/${linux_user}
chown ${linux_user}:${linux_user} /home/${linux_user}

# Run Coder agent init script
sudo -u ${linux_user} sh -c '${init_script}'
```

## Usage

1. Add the template to Coder:
   ```bash
   coder templates push aws-linux-prebuilds
   ```

2. Create a workspace (instant if prebuild available):
   ```bash
   coder create my-workspace --template aws-linux-prebuilds
   ```

3. Check prebuild status:
   ```bash
   coder templates versions aws-linux-prebuilds
   ```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `region` | AWS region | `us-east-1` |
| `instance_type` | EC2 instance type | `m5.2xlarge` |
| `disk_size` | Root volume size (GB) | `100` |

## Instance Types

| Option | vCPU | RAM | Use Case |
|--------|------|-----|----------|
| t3.medium | 2 | 4 GB | Light development |
| t3.large | 2 | 8 GB | Standard development |
| t3.xlarge | 4 | 16 GB | Multi-service development |
| t3.2xlarge | 8 | 32 GB | Heavy workloads |
| c5.2xlarge | 8 | 16 GB | Compute-intensive builds |
| m5.2xlarge | 8 | 32 GB | **Default** - balanced |
| r5.2xlarge | 8 | 64 GB | Memory-intensive workloads |
| m5.4xlarge | 16 | 64 GB | Large-scale development |

## Workspace Metadata

The workspace displays:
- Region
- Instance type
- Disk size
- CPU/RAM/Disk usage (live)
- Docker health status

## First-Time Setup

On first start, the workspace installs all development tools (~5-10 minutes). Subsequent starts skip installation using a `~/.setup_complete` marker.

To force reinstallation:
```bash
rm ~/.setup_complete
```

## Auto-Cleanup

When disk usage exceeds 80%, Docker automatically prunes unused images, containers, and volumes.

## Shutdown Behavior

Docker containers are gracefully stopped (30s timeout) when the workspace stops.

## Customizing Prebuilds

### Adjust Instance Count

Edit the `coder_prebuilt_workspace` resource:

```hcl
resource "coder_prebuilt_workspace" "preset" {
  instances = 5  # Increase for larger teams
  ...
}
```

### Add Multiple Presets

Create additional presets for different configurations:

```hcl
resource "coder_workspace_preset" "large" {
  name = "large"
  parameters = {
    region        = "us-east-1"
    instance_type = "m5.4xlarge"
    disk_size     = "200"
  }
}

resource "coder_prebuilt_workspace" "large" {
  name      = "prebuild-large"
  agents    = [coder_agent.dev[0].id]
  preset_id = coder_workspace_preset.large.id
  instances = 1
  expiration_policy {
    ttl = 86400
  }
}
```

### Adjust TTL

Shorter TTL = fresher workspaces, more rebuilds:

```hcl
expiration_policy {
  ttl = 43200  # 12 hours
}
```

## IAM Policy

Ensure your Coder provisioner has permissions for:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:CreateTags",
        "ec2:DescribeImages"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "ec2:ResourceTag/Coder_Provisioned": "true"
        }
      }
    }
  ]
}
```

## Troubleshooting

### Prebuilds Not Creating

1. Verify Coder Enterprise license is active
2. Check template version is published (not draft)
3. Review provisioner logs for errors

### High Prebuild Costs

1. Reduce `instances` count
2. Use smaller instance types for prebuilds
3. Shorten TTL to reduce idle time

### Users Not Getting Prebuilds

Prebuilds only match when **all parameters match exactly**. Users selecting non-default options will provision normally.
