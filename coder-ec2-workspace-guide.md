Here are step-by-step instructions to set up AWS and Coder (already deployed in EKS) to create EC2-based workspaces:

## Prerequisites
- Coder already installed in EKS
- `kubectl` configured to access your cluster
- AWS CLI installed
- Coder CLI installed

## Part 1: AWS IAM Setup

### Step 1: Set Environment Variables

```bash
export CLUSTER_NAME="your-eks-cluster-name"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

### Step 2: Create IAM Policy for Coder EC2 Provisioning

```bash
cat << 'EOF' > coder-ec2-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2Management",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeImages",
        "ec2:DescribeVolumes",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeKeyPairs",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeRegions",
        "ec2:DescribeRouteTables",
        "ec2:DescribeNetworkInterfaces",
        "ec2:RunInstances",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:ModifyInstanceAttribute",
        "ec2:CreateVolume",
        "ec2:DeleteVolume",
        "ec2:AttachVolume",
        "ec2:DetachVolume"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SecurityGroupManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress"
      ],
      "Resource": "*"
    },
    {
      "Sid": "NetworkInterfaceManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:AttachNetworkInterface",
        "ec2:DetachNetworkInterface",
        "ec2:ModifyNetworkInterfaceAttribute"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMPassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "ec2.amazonaws.com"
        }
      }
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name CoderEC2ProvisionerPolicy \
  --policy-document file://coder-ec2-policy.json \
  --description "Policy for Coder to provision EC2 workspaces"
```

### Step 3: Create IAM Role for Coder Service Account (IRSA)

**Option A: Using eksctl (Recommended)**

```bash
# First, check which namespace and service account name Coder uses
kubectl get sa -n coder

# Typically it's 'coder' service account in 'coder' namespace
# Adjust if different
export CODER_NAMESPACE="coder"
export CODER_SA_NAME="coder"

eksctl create iamserviceaccount \
  --cluster=${CLUSTER_NAME} \
  --namespace=${CODER_NAMESPACE} \
  --name=${CODER_SA_NAME} \
  --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CoderEC2ProvisionerPolicy \
  --override-existing-serviceaccounts \
  --approve
```

**Option B: Manual Setup**

```bash
# Get OIDC provider
OIDC_PROVIDER=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

# Verify OIDC provider exists
aws iam list-open-id-connect-providers | grep ${OIDC_PROVIDER}

# If not, create it
eksctl utils associate-iam-oidc-provider --cluster=${CLUSTER_NAME} --approve

# Create trust policy
cat << EOF > coder-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:coder:coder"
        }
      }
    }
  ]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name CoderEC2ProvisionerRole-${CLUSTER_NAME} \
  --assume-role-policy-document file://coder-trust-policy.json

# Attach policy
aws iam attach-role-policy \
  --role-name CoderEC2ProvisionerRole-${CLUSTER_NAME} \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CoderEC2ProvisionerPolicy

# Annotate service account
kubectl annotate serviceaccount -n coder coder \
  eks.amazonaws.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/CoderEC2ProvisionerRole-${CLUSTER_NAME} \
  --overwrite
```

### Step 4: Create IAM Role for Workspace EC2 Instances

```bash
cat << 'EOF' > workspace-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name CoderWorkspaceRole \
  --assume-role-policy-document file://workspace-trust-policy.json \
  --description "Role for Coder workspace EC2 instances"

# Attach useful policies
aws iam attach-role-policy \
  --role-name CoderWorkspaceRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

# Optional: Add more policies as needed
# aws iam attach-role-policy --role-name CoderWorkspaceRole --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess

# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name CoderWorkspaceInstanceProfile

aws iam add-role-to-instance-profile \
  --instance-profile-name CoderWorkspaceInstanceProfile \
  --role-name CoderWorkspaceRole

# Wait for instance profile to be ready
sleep 10
```

### Step 5: Restart Coder Pods to Pick Up New IAM Role

```bash
kubectl rollout restart deployment -n coder coder
kubectl rollout status deployment -n coder coder
```

## Part 2: Network Setup

### Step 6: Get EKS VPC Information

```bash
# Get VPC ID
export VPC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.resourcesVpcConfig.vpcId" --output text)

echo "VPC ID: ${VPC_ID}"

# List available subnets
echo "Available subnets:"
aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query 'Subnets[].[SubnetId,CidrBlock,AvailabilityZone,Tags[?Key==`Name`].Value|[0],MapPublicIpOnLaunch]' \
  --output table

# Choose a subnet for workspaces (can be public or private)
# For private subnet with NAT Gateway (recommended):
export WORKSPACE_SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*private*" \
  --query 'Subnets[0].SubnetId' --output text)

# Or manually set:
# export WORKSPACE_SUBNET_ID="subnet-xxxxx"

echo "Workspace Subnet ID: ${WORKSPACE_SUBNET_ID}"
```

### Step 7: Create Security Group for Workspaces

```bash
# Create security group
export SG_ID=$(aws ec2 create-security-group \
  --group-name coder-workspaces \
  --description "Security group for Coder EC2 workspaces" \
  --vpc-id ${VPC_ID} \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=coder-workspaces},{Key=ManagedBy,Value=Coder}]' \
  --query 'GroupId' --output text)

echo "Security Group ID: ${SG_ID}"

# Allow all outbound traffic
aws ec2 authorize-security-group-egress \
  --group-id ${SG_ID} \
  --protocol -1 \
  --cidr 0.0.0.0/0 2>/dev/null || echo "Default egress rule already exists"

# Allow all traffic between workspace instances
aws ec2 authorize-security-group-ingress \
  --group-id ${SG_ID} \
  --source-group ${SG_ID} \
  --protocol -1

# Optional: Allow SSH from specific CIDR (for debugging)
# aws ec2 authorize-security-group-ingress \
#   --group-id ${SG_ID} \
#   --protocol tcp \
#   --port 22 \
#   --cidr 0.0.0.0/0

echo "Security group created successfully"
```

### Step 8: Verify Coder Can Reach AWS API

```bash
# Test AWS API access from Coder pod
kubectl exec -n coder deploy/coder -- aws sts get-caller-identity
kubectl exec -n coder deploy/coder -- aws ec2 describe-instances --region ${AWS_REGION} --max-items 1
```

## Part 3: Create Coder Template

### Step 9: Install and Configure Coder CLI

```bash
# Install Coder CLI if not already installed
curl -L https://coder.com/install.sh | sh

# Get Coder URL
export CODER_URL=$(kubectl get svc -n coder coder -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
# Or if using ingress:
# export CODER_URL="https://coder.example.com"

echo "Coder URL: ${CODER_URL}"

# Login to Coder
coder login ${CODER_URL}
```

### Step 10: Create Template Directory

```bash
mkdir -p ~/coder-templates/aws-ec2
cd ~/coder-templates/aws-ec2
```

### Step 11: Create main.tf

```bash
cat << 'EOF' > main.tf
terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.12"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = data.coder_parameter.region.value
}

provider "coder" {}

data "coder_parameter" "region" {
  name         = "region"
  display_name = "AWS Region"
  description  = "The AWS region to deploy the workspace in"
  default      = "us-east-1"
  mutable      = false
  option {
    name  = "US East (N. Virginia)"
    value = "us-east-1"
  }
  option {
    name  = "US West (Oregon)"
    value = "us-west-2"
  }
  option {
    name  = "EU (Ireland)"
    value = "eu-west-1"
  }
}

data "coder_parameter" "instance_type" {
  name         = "instance_type"
  display_name = "Instance Type"
  description  = "The EC2 instance type"
  default      = "t3.large"
  mutable      = true
  option {
    name  = "Medium (t3.medium - 2 vCPU, 4 GB RAM)"
    value = "t3.medium"
  }
  option {
    name  = "Large (t3.large - 2 vCPU, 8 GB RAM)"
    value = "t3.large"
  }
  option {
    name  = "XLarge (t3.xlarge - 4 vCPU, 16 GB RAM)"
    value = "t3.xlarge"
  }
  option {
    name  = "2XLarge (t3.2xlarge - 8 vCPU, 32 GB RAM)"
    value = "t3.2xlarge"
  }
}

data "coder_parameter" "volume_size" {
  name         = "volume_size"
  display_name = "Volume Size (GB)"
  description  = "Size of the root volume in GB"
  default      = "50"
  mutable      = false
  validation {
    min = 30
    max = 500
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Get latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 Instance
resource "aws_instance" "workspace" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = data.coder_parameter.instance_type.value
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.instance_profile_name

  root_block_device {
    volume_size = data.coder_parameter.volume_size.value
    volume_type = "gp3"
    iops        = 3000
    throughput  = 125
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    coder_agent_token = coder_agent.main.token
    coder_agent_url   = data.coder_workspace.me.access_url
    username          = lower(data.coder_workspace_owner.me.name)
  }))

  tags = {
    Name             = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    Workspace        = data.coder_workspace.me.name
    Owner            = data.coder_workspace_owner.me.name
    ManagedBy        = "Coder"
    CoderWorkspaceID = data.coder_workspace.me.id
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# Coder Agent
resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"

  startup_script_behavior = "blocking"

  startup_script = <<-EOT
    #!/bin/bash
    set -e
    
    # Wait for cloud-init to complete
    cloud-init status --wait
    
    # Update system
    sudo apt-get update
    
    # Install development tools
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
      build-essential \
      git \
      curl \
      wget \
      vim \
      nano \
      htop \
      jq \
      unzip \
      software-properties-common
    
    # Install Docker
    if ! command -v docker &> /dev/null; then
      curl -fsSL https://get.docker.com -o get-docker.sh
      sudo sh get-docker.sh
      sudo usermod -aG docker ${lower(data.coder_workspace_owner.me.name)}
      rm get-docker.sh
    fi
    
    # Install Docker Compose
    if ! command -v docker-compose &> /dev/null; then
      sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
      sudo chmod +x /usr/local/bin/docker-compose
    fi
    
    # Install AWS CLI v2
    if ! command -v aws &> /dev/null; then
      curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
      unzip -q awscliv2.zip
      sudo ./aws/install
      rm -rf aws awscliv2.zip
    fi
    
    # Install kubectl
    if ! command -v kubectl &> /dev/null; then
      curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
      sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
      rm kubectl
    fi
    
    # Install Terraform
    if ! command -v terraform &> /dev/null; then
      wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
      sudo apt-get update && sudo apt-get install -y terraform
    fi
    
    # Install code-server
    if ! command -v code-server &> /dev/null; then
      curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone
    fi
    
    # Configure code-server
    mkdir -p ~/.config/code-server
    cat > ~/.config/code-server/config.yaml <<EOFCONFIG
bind-addr: 127.0.0.1:13337
auth: none
cert: false
EOFCONFIG
    
    # Start code-server in background
    code-server --install-extension golang.go &
    code-server --install-extension ms-python.python &
  EOT

  metadata {
    display_name = "CPU Usage"
    key          = "cpu_usage"
    script       = "top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1"
    interval     = 10
    timeout      = 5
  }

  metadata {
    display_name = "Memory Usage"
    key          = "mem_usage"
    script       = "free | grep Mem | awk '{printf \"%.1f%%\", $3/$2 * 100.0}'"
    interval     = 10
    timeout      = 5
  }

  metadata {
    display_name = "Disk Usage"
    key          = "disk_usage"
    script       = "df -h / | tail -1 | awk '{print $5}'"
    interval     = 60
    timeout      = 5
  }

  metadata {
    display_name = "Instance ID"
    key          = "instance_id"
    script       = "echo ${aws_instance.workspace.id}"
    interval     = 3600
    timeout      = 5
  }
}

# VS Code Web
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://localhost:13337/?folder=/home/${lower(data.coder_workspace_owner.me.name)}"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 10
  }
}

# Outputs
output "instance_id" {
  value       = aws_instance.workspace.id
  description = "EC2 Instance ID"
}

output "public_ip" {
  value       = aws_instance.workspace.public_ip
  description = "Public IP address"
}

output "private_ip" {
  value       = aws_instance.workspace.private_ip
  description = "Private IP address"
}

output "instance_type" {
  value       = aws_instance.workspace.instance_type
  description = "Instance type"
}
EOF
```

### Step 12: Create variables.tf

```bash
cat << 'EOF' > variables.tf
variable "subnet_id" {
  description = "Subnet ID for workspace instances"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for workspace instances"
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile name for workspace instances"
  type        = string
  default     = "CoderWorkspaceInstanceProfile"
}
EOF
```

### Step 13: Create cloud-init.yaml

```bash
cat << 'EOF' > cloud-init.yaml
#cloud-config
hostname: workspace

users:
  - name: ${username}
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: sudo, docker
    lock_passwd: false

packages:
  - curl
  - wget
  - git
  - ca-certificates

write_files:
  - path: /etc/systemd/system/coder-agent.service
    permissions: "0644"
    content: |
      [Unit]
      Description=Coder Agent
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=simple
      User=${username}
      Environment="CODER_AGENT_TOKEN=${coder_agent_token}"
      Environment="CODER_AGENT_URL=${coder_agent_url}"
      ExecStart=/usr/local/bin/coder agent
      Restart=always
      RestartSec=5s
      StandardOutput=journal
      StandardError=journal

      [Install]
      WantedBy=multi-user.target

  - path: /home/${username}/.bashrc
    permissions: "0644"
    owner: ${username}:${username}
    append: true
    content: |
      # Coder workspace configuration
      export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
      alias k=kubectl
      alias tf=terraform

runcmd:
  - |
    set -e
    
    # Download Coder agent
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
      ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then
      ARCH="arm64"
    fi
    
    # Get latest Coder version
    CODER_VERSION=$(curl -s https://api.github.com/repos/coder/coder/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    
    curl -fsSL "https://github.com/coder/coder/releases/download/v$${CODER_VERSION}/coder_$${CODER_VERSION}_linux_$${ARCH}.tar.gz" -o /tmp/coder.tar.gz
    tar -xzf /tmp/coder.tar.gz -C /tmp
    sudo mv /tmp/coder /usr/local/bin/coder
    sudo chmod +x /usr/local/bin/coder
    rm /tmp/coder.tar.gz
    
  - systemctl daemon-reload
  - systemctl enable coder-agent
  - systemctl start coder-agent
  
  - |
    # Set ownership
    chown -R ${username}:${username} /home/${username}

final_message: "Coder workspace is ready!"
EOF
```

### Step 14: Create README.md

```bash
cat << 'EOF' > README.md
# AWS EC2 Workspace Template

This template provisions EC2-based workspaces from Coder running in EKS.

## Features

- Ubuntu 22.04 LTS
- Docker & Docker Compose
- AWS CLI v2
- kubectl
- Terraform
- VS Code (code-server)
- Auto-scaling storage with EBS

## Requirements

- VPC with subnets
- Security group allowing outbound to Coder
- IAM instance profile for workspaces
EOF
```

### Step 15: Push Template to Coder

```bash
# Verify environment variables are set
echo "Subnet ID: ${WORKSPACE_SUBNET_ID}"
echo "Security Group ID: ${SG_ID}"

# Push template
coder templates push aws-ec2 \
  --directory ~/coder-templates/aws-ec2 \
  --variable subnet_id="${WORKSPACE_SUBNET_ID}" \
  --variable security_group_id="${SG_ID}" \
  --variable instance_profile_name="CoderWorkspaceInstanceProfile" \
  --yes
```

## Part 4: Testing

### Step 16: Create Test Workspace

```bash
# Create workspace via CLI
coder create my-dev-workspace --template aws-ec2

# Wait for workspace to be ready
coder list
```

### Step 17: Verify Workspace

```bash
# Check workspace status
coder stat my-dev-workspace

# SSH into workspace
coder ssh my-dev-workspace

# Inside workspace, verify tools
docker --version
aws --version
kubectl version --client
terraform --version

# Verify IAM role works
aws sts get-caller-identity

# Exit workspace
exit
```

### Step 18: Test VS Code Access

```bash
# Open VS Code in browser
coder open my-dev-workspace --app code-server
```

## Troubleshooting

### Issue 1: Agent Won't Connect

```bash
# Check Coder logs
kubectl logs -n coder deploy/coder --tail=100

# Check if workspace can reach Coder
# Get a workspace instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:ManagedBy,Values=Coder" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# Connect via SSM and check agent logs
aws ssm start-session --target ${INSTANCE_ID}
# Once connected:
# sudo journalctl -u coder-agent -f
# sudo cat /var/log/cloud-init-output.log
```

### Issue 2: Permission Errors

```bash
# Verify service account has correct annotation
kubectl get sa -n coder coder -o yaml | grep role-arn

# Test AWS access from Coder pod
kubectl exec -n coder deploy/coder -- aws ec2 describe-instances --region ${AWS_REGION} --max-items 1

# Check IAM role trust policy
aws iam get-role --role-name CoderEC2ProvisionerRole-${CLUSTER_NAME} --query 'Role.AssumeRolePolicyDocument'
```

### Issue 3: Template Push Fails

```bash
# Validate Terraform
cd ~/coder-templates/aws-ec2
terraform init
terraform validate

# Check Coder CLI is logged in
coder login ${CODER_URL}

# Verify template syntax
coder templates plan aws-ec2 \
  --directory ~/coder-templates/aws-ec2 \
  --variable subnet_id="${WORKSPACE_SUBNET_ID}" \
  --variable security_group_id="${SG_ID}"
```

### Issue 4: Instances Won't Start

```bash
# Check AWS limits
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A

# Verify subnet has available IPs
aws ec2 describe-subnets --subnet-ids ${WORKSPACE_SUBNET_ID} \
  --query 'Subnets[0].AvailableIpAddressCount'

# Check instance profile exists
aws iam get-instance-profile --instance-profile-name CoderWorkspaceInstanceProfile
```

## Next Steps

1. **Add more templates** for different use cases (GPU instances, ARM, specific tech stacks)
2. **Configure workspace auto-stop** to save costs
3. **Set up monitoring** for workspace usage and costs
4. **Enable SSO** for Coder authentication
5. **Configure backup** for workspace data if needed
6. **Add workspace quota policies** to control costs

## Summary

Your setup is now complete:
- ✅ IAM roles configured for Coder and workspaces
- ✅ Network security groups configured
- ✅ Coder template created and pushed
- ✅ Test workspace running

Users can now create EC2-based workspaces directly from the Coder UI at `${CODER_URL}`.
