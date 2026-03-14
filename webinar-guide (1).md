# 🚀 From Zero to Hero: Production-Ready AWS Deployment
### Complete Step-by-Step Webinar Guide — Saturday Session

> **Stack:** Node.js API → Docker → ECR → ECS on EC2 + ALB → RDS → Secrets Manager → S3 + CloudFront → CI/CD  
> **Format:** Each step includes 🎤 Speaker Script + 🏗️ Terraform Code + 🖥️ AWS Console Walkthrough  
> **Estimated Duration:** ~120 minutes  
> **Slide Deck:** Aligns with *From Zero to Hero — AWS Production-Ready Demo*

---

## 📋 TABLE OF CONTENTS

| # | Step | Duration |
|---|------|----------|
| 0 | [Prerequisites & Safety](#step-0) | 5 min |
| 1 | [Project Baseline](#step-1) | 5 min |
| 2 | [Dockerize the Application](#step-2) | 10 min |
| 3 | [Terraform Remote State](#step-3) | 10 min |
| 4 | [VPC & Networking](#step-4) | 15 min |
| 5 | [ECR — Container Registry](#step-5) | 8 min |
| 6 | [Security Groups & IAM](#step-6) | 8 min |
| 7 | [RDS — Data Tier](#step-7) | 10 min |
| 8 | [ECS on EC2 + ALB — App Tier](#step-8) | 15 min |
| 9 | [S3 + CloudFront — Presentation Tier](#step-9) | 10 min |
| 10 | [Secrets Manager & Configuration](#step-10) | 8 min |
| 11 | [Observability & Alarms](#step-11) | 8 min |
| 12 | [CI/CD with GitHub Actions](#step-12) | 8 min |
| ✅ | [Hardening Checklist + Teardown](#hardening) | 5 min |

---

## 🏛️ TARGET ARCHITECTURE

```
Internet
    │
    ▼
CloudFront (450+ edge locations)
    │
    ├──► S3 Bucket (Static Frontend — private, OAC only)
    │
    └──► Application Load Balancer (ALB — public subnets)
              │  HTTPS + HTTP→HTTPS redirect
              ▼
         ECS Cluster (EC2 Launch Type — private subnets)
         ┌──────────────────────────────────────┐
         │  Auto Scaling Group (EC2 instances)  │
         │  ┌────────────┐  ┌────────────┐      │
         │  │ Container  │  │ Container  │      │
         │  │ (Node.js)  │  │ (Node.js)  │      │
         │  └────────────┘  └────────────┘      │
         └──────────────────────────────────────┘
              │
              ├──► RDS PostgreSQL (private subnets)
              └──► Secrets Manager (db password, tokens)

GitHub Actions CI/CD:
  push → test → build → push to ECR → deploy to ECS
```

### Three Tiers
| Tier | Service | Notes |
|------|---------|-------|
| **Presentation** | S3 + CloudFront | Static frontend, global CDN |
| **Application** | ECS on EC2 + ALB | Containerized API, visible infra |
| **Data** | RDS PostgreSQL | Private subnets, encrypted |

---

<a name="step-0"></a>
## STEP 0: Prerequisites & Safety
⏱️ *~5 minutes* | 📊 Slide: *"Before we start (Step 0)"*

### 🎤 WHAT TO SAY

> "Before a single line of code, let's talk about safety. Cloud mistakes are expensive and sometimes irreversible — especially around IAM and networking.
>
> Three rules I follow on every AWS project:
> 1. **Never use root credentials** for daily work. Root is for emergencies only — MFA enabled, credentials locked away.
> 2. **Set a budget alarm.** Before today's demo I set a $20/day alert. You will be surprised how fast costs add up if you forget to tear down.
> 3. **Use a dedicated sandbox account.** This isolates blast radius — if you misconfigure something, it only affects this account.
>
> You'll also need these tools installed locally..."

### ✅ Required Tools

```bash
# Verify all tools are ready
aws --version          # AWS CLI v2
terraform --version    # Terraform >= 1.5
docker --version       # Docker Desktop running
git --version          # Git

# Configure AWS credentials
aws configure          # Or use SSO: aws configure sso
aws sts get-caller-identity  # Verify you're authenticated
```

### 🖥️ AWS CONSOLE — WHAT TO SHOW

> 1. Go to **Billing → Budgets** — show the budget + alert configured
> 2. Go to **IAM → Users** — show that root account has MFA enabled
> 3. Show the **IAM role** being used (not root, not admin user)

---

<a name="step-1"></a>
## STEP 1: Project Baseline
⏱️ *~5 minutes* | 📊 Slide: *"Project baseline (Step 1)"*

### 🎤 WHAT TO SAY

> "Good project structure is the foundation everything else builds on. We follow one simple rule: **separate app code from infrastructure code**. They change at different rates and they're owned by different concerns.
>
> The `infra/envs/dev` and `infra/envs/prod` pattern means each environment has completely isolated state. Breaking prod while fixing dev is impossible by design."

### 📁 Project Structure

```
zero-to-hero/
├── app/
│   ├── index.js              # Node.js Express API
│   ├── package.json
│   └── Dockerfile
├── frontend/
│   └── index.html            # Static frontend
├── infra/
│   ├── modules/
│   │   ├── vpc/
│   │   ├── ecs/
│   │   ├── rds/
│   │   └── cdn/
│   └── envs/
│       ├── dev/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── terraform.tfvars
│       └── prod/
│           ├── main.tf
│           └── variables.tf
├── .github/
│   └── workflows/
│       └── deploy.yml
└── README.md
```

### Naming Conventions

- One service name: `web-api`
- One env per account: `dev` / `staging` / `prod`
- Tags on every resource: `project`, `env`, `owner`, `cost-center`

---

<a name="step-2"></a>
## STEP 2: Dockerize the Application
⏱️ *~10 minutes* | 📊 Slide: *"Dockerize and run locally (Step 2)"*

### 🎤 WHAT TO SAY

> "Docker is the contract between your laptop and the cloud. Whatever runs in Docker locally will run in ECS. No more 'works on my machine'.
>
> Two important practices in this Dockerfile: multi-stage builds keep the final image small, and running as a non-root user means if someone exploits our app, they don't get root inside the container.
>
> The health endpoint `/healthz` has zero database dependency — it just returns 200. This is intentional. The ALB health check hits this endpoint. If we check the DB in health, a DB blip takes down ALL our healthy containers."

### 📄 `app/index.js`

```javascript
const express = require('express');
const { Pool } = require('pg');

const app = express();
app.use(express.json());

const pool = new Pool({
  host:     process.env.DB_HOST,
  database: process.env.DB_NAME     || 'appdb',
  user:     process.env.DB_USER     || 'appuser',
  password: process.env.DB_PASSWORD,
  port:     5432,
  ssl: { rejectUnauthorized: false }
});

// ✅ Health check — NO DB dependency (ALB uses this)
app.get('/healthz', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// DB connectivity test
app.get('/db-check', async (req, res) => {
  try {
    const result = await pool.query('SELECT NOW()');
    res.json({ connected: true, time: result.rows[0].now });
  } catch (err) {
    res.status(500).json({ connected: false, error: err.message });
  }
});

app.get('/', (req, res) => {
  res.json({ message: 'Hello from the cloud!', env: process.env.ENV || 'local' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => console.log(`Listening on :${PORT}`));
```

### 📄 `app/Dockerfile`

```dockerfile
# Stage 1: Build
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install --production

# Stage 2: Runtime (smaller final image)
FROM node:18-alpine
WORKDIR /app

# Non-root user (security best practice)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=builder /app/node_modules ./node_modules
COPY . .

USER appuser
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:3000/healthz || exit 1

CMD ["node", "index.js"]
```

### Test Locally

```bash
docker build -t web-api:local ./app
docker run --rm -p 3000:3000 \
  -e DB_HOST=localhost \
  -e DB_PASSWORD=localpass \
  web-api:local

# Verify
curl -s http://localhost:3000/healthz
```

### Common Gotchas
- Binding to `127.0.0.1` instead of `0.0.0.0` — container won't be reachable
- No graceful shutdown → dropped requests on deploy
- Huge images → slow ECR pushes → slow ECS deployments

---

<a name="step-3"></a>
## STEP 3: Terraform Remote State
⏱️ *~10 minutes* | 📊 Slide: *"Infrastructure as Code + remote state (Step 3)"*

### 🎤 WHAT TO SAY

> "Local Terraform state is fine for your laptop. The moment a second person touches the infra, or your CI/CD pipeline runs, you need remote state.
>
> Two things remote state gives you: first, the state file is in S3 — encrypted, versioned, never lost. Second, the DynamoDB lock table means only one `terraform apply` can run at a time. No race conditions, no corrupted state.
>
> Now here's something people always ask: how do you create the S3 bucket and DynamoDB table themselves? With Terraform, of course. We have a `bootstrap/` folder that is its own tiny Terraform project. It uses local state — this is the one time that's intentional. Classic chicken-and-egg: you can't store state in S3 before S3 exists.
>
> After bootstrap runs, it prints the exact backend config snippet you paste into your main module. One `terraform apply`, and your state backend is production-grade — versioned, encrypted, locked, with `prevent_destroy` so you can never accidentally delete it.
>
> The workflow from then on is always: `fmt → validate → plan → apply`. And the golden rule: **no manual clicking in prod.** If it's not in Terraform, it doesn't exist."

### Bootstrap: Create the S3 + DynamoDB Backend (one-time)

The bootstrap is itself a Terraform project — no manual clicking, no AWS CLI commands. It lives in `infra/bootstrap/` and uses **local state** intentionally. This is the classic chicken-and-egg problem: you can't store state in S3 before the S3 bucket exists, so this folder is the one exception where local state is correct.

```bash
cd infra/bootstrap

terraform init    # No backend block — local state is intentional here

terraform apply -var="app_name=web-api" -var="aws_region=us-east-1"
```

Terraform creates:
- **S3 bucket** — versioned, AES-256 encrypted, all public access blocked, old versions expire after 90 days
- **DynamoDB table** — `PAY_PER_REQUEST` billing, `LockID` hash key for state locking

Both resources have `prevent_destroy = true` so a stray `terraform destroy` can never wipe your state.

After apply, Terraform prints the exact backend snippet to copy:

```hcl
# Copy this into infra/envs/dev/main.tf backend block:
backend "s3" {
  bucket         = "web-api-tfstate-123456789012"
  key            = "web-api/dev/terraform.tfstate"
  region         = "us-east-1"
  dynamodb_table = "web-api-tfstate-lock"
  encrypt        = true
}
```

Paste this into the `backend "s3" {}` block in `infra/envs/dev/main.tf`, then continue with Step 4.

### 📄 `infra/envs/dev/main.tf`

```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state — encrypted, versioned, locked
  backend "s3" {
    bucket         = "web-api-tfstate-prod"
    key            = "web-api/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "web-api-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.app_name
      Env       = var.environment
      ManagedBy = "Terraform"
      Owner     = "tid.devops"
    }
  }
}

data "aws_availability_zones" "available" { state = "available" }
```

### Terraform Workflow

```bash
cd infra/envs/dev

terraform fmt        # Format all files
terraform validate   # Syntax + logic check
terraform plan       # Preview changes — ALWAYS review this
terraform apply      # Apply (prompts for confirmation)
```

### 🖥️ AWS CONSOLE — WHAT TO SHOW

> 1. Open a terminal and run `cd infra/bootstrap && terraform init && terraform apply` — show the live output
> 2. Copy the `backend_config_snippet` from the output into `infra/envs/dev/main.tf`
> 3. Go to **S3** — show the state bucket: versioning enabled, encryption enabled, public access blocked
> 4. Go to **DynamoDB → Tables** — show the `web-api-tfstate-lock` table with `LockID` key
> 5. After the first `terraform apply` in Step 4 — navigate into the S3 bucket and show the `.tfstate` file appearing

---

<a name="step-4"></a>
## STEP 4: VPC & Networking
⏱️ *~15 minutes* | 📊 Slide: *"Networking: VPC, subnets, routing (Step 4)"*

### 🎤 WHAT TO SAY

> "The VPC is your private data center in AWS. No one outside can reach anything inside unless you explicitly allow it.
>
> We create subnets in **two Availability Zones**. An AZ is a physically separate data centre — different power, cooling, networking. If one fails, traffic automatically routes to the other. This is high availability by design, not by accident.
>
> Public subnets face the internet — only the ALB goes here.
> Private subnets are invisible to the internet — ECS, RDS, everything sensitive goes here.
>
> The NAT Gateway lets private resources reach the internet outbound — to pull Docker images from ECR, for example — without exposing them to inbound traffic."

### 📄 `infra/envs/dev/variables.tf`

```hcl
variable "aws_region"    { default = "us-east-1" }
variable "app_name"      { default = "web-api" }
variable "environment"   { default = "dev" }
variable "db_password"   { sensitive = true }
variable "container_image" {}
```

### 📄 `infra/envs/dev/vpc.tf`

```hcl
# ─── VPC ──────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.app_name}-vpc" }
}

# ─── INTERNET GATEWAY
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.app_name}-igw" }
}

# ─── PUBLIC SUBNETS (ALB lives here)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.app_name}-public-${count.index + 1}" }
}

# ─── PRIVATE SUBNETS (ECS + RDS live here)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "${var.app_name}-private-${count.index + 1}" }
}

# ─── NAT GATEWAY (private → internet, not the reverse)
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.app_name}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.app_name}-nat-gw" }
  depends_on    = [aws_internet_gateway.main]
}

#ROUTE TABLES
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.app_name}-public-rt" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = { Name = "${var.app_name}-private-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

### 🖥️ AWS CONSOLE — WHAT TO SHOW

> 1. **VPC → Your VPCs** — show the VPC with `10.0.0.0/16`
> 2. **Subnets** — show 2 public + 2 private across two AZs
> 3. **Internet Gateways** — show IGW attached to VPC
> 4. **NAT Gateways** — show NAT in public subnet, highlight cost ($45/month)
> 5. **Route Tables** — public routes to IGW, private routes to NAT

---

<a name="step-5"></a>
## STEP 5: ECR — Container Registry
⏱️ *~8 minutes* | 📊 Slide: *"Container registry: ECR + image hygiene (Step 5)"*

### 🎤 WHAT TO SAY

> "ECR is Docker Hub, but private and inside AWS. ECS pulls images from ECR — it's fast because they're in the same network, and it's secure because no image is ever public.
>
> The most important habit: **always tag images with the Git commit SHA**. Not 'latest'. Not a version number. The commit SHA. Why? When something breaks in production at 2am, you need to know exactly which code is running. And rollback is just redeploying the previous SHA."

### 📄 `infra/envs/dev/ecr.tf`

```hcl
resource "aws_ecr_repository" "app" {
  name                 = var.app_name
  image_tag_mutability = "IMMUTABLE"  # Once pushed, a tag cannot be overwritten

  image_scanning_configuration {
    scan_on_push = true  # Scan for CVEs automatically
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "${var.app_name}-ecr" }
}

# Lifecycle policy: keep last 10 tagged images, delete untagged after 1 day
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
```

### Build & Push Image

```bash
# Get the ECR URI from Terraform
ECR_URI=$(terraform output -raw ecr_repository_url)
GIT_SHA=$(git rev-parse --short HEAD)

# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin $ECR_URI

# Build, tag with commit SHA, push
docker build -t web-api:${GIT_SHA} ./app
docker tag web-api:${GIT_SHA} ${ECR_URI}:${GIT_SHA}
docker push ${ECR_URI}:${GIT_SHA}

echo "Pushed: ${ECR_URI}:${GIT_SHA}"
```

### 🖥️ AWS CONSOLE — WHAT TO SHOW

> 1. **ECR → Repositories** — show the repository, click into it
> 2. Show the pushed image with the SHA tag
> 3. Click **Scan results** — show the vulnerability report (scan_on_push)
> 4. Show **Image tag immutability** is IMMUTABLE

---

<a name="step-6"></a>
## STEP 6: Security Groups & IAM
⏱️ *~8 minutes* |Slide: *(part of Step 6 — ECS/ALB)*

### 🎤 WHAT TO SAY

> "Security groups are stateful firewalls. The design here is a chain of trust:
> - The ALB accepts traffic from the internet on 80/443
> - ECS instances ONLY accept traffic from the ALB — not from the internet
> - RDS ONLY accepts traffic from the ECS security group
>
> Even if someone compromised the ALB, they still can't reach RDS directly. Defence in depth.
>
> For IAM — least privilege. The ECS task execution role can pull images and write logs. Nothing more. The ECS instance role can register with the cluster. Nothing more."

### 📄 `infra/envs/dev/security.tf`

```hcl
# ─── ALB: accepts internet traffic ────────────────────────────
resource "aws_security_group" "alb" {
  name   = "${var.app_name}-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress { from_port = 80;  to_port = 80;  protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 443; to_port = 443; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0;   to_port = 0;   protocol = "-1";  cidr_blocks = ["0.0.0.0/0"] }

  tags = { Name = "${var.app_name}-alb-sg" }
}

# ─── ECS: accepts traffic from ALB only ───────────────────────
resource "aws_security_group" "ecs" {
  name   = "${var.app_name}-ecs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 32768
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]  # ← ALB SG ID, not CIDR
    description     = "Dynamic port range from ALB only"
  }

  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
  tags = { Name = "${var.app_name}-ecs-sg" }
}

# ─── RDS: accepts traffic from ECS only ───────────────────────
resource "aws_security_group" "rds" {
  name   = "${var.app_name}-rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]  # ← ECS SG ID only
    description     = "Postgres from ECS only"
  }

  tags = { Name = "${var.app_name}-rds-sg" }
}

# ─── IAM: ECS Task Execution Role ─────────────────────────────
resource "aws_iam_role" "ecs_execution" {
  name = "${var.app_name}-ecs-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow ECS to read secrets from Secrets Manager
resource "aws_iam_role_policy" "ecs_secrets" {
  name = "read-secrets"
  role = aws_iam_role.ecs_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.app_name}/*"
    }]
  })
}

# ─── IAM: EC2 Instance Profile for ECS Agent ──────────────────
resource "aws_iam_role" "ecs_instance" {
  name = "${var.app_name}-ecs-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs" {
  name = "${var.app_name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
}
```

### 🖥️ AWS CONSOLE — WHAT TO SHOW

> 1. **EC2 → Security Groups** — show the three SGs (ALB, ECS, RDS)
> 2. Click ECS SG inbound rules — highlight it references ALB SG by ID, not by CIDR
> 3. Click RDS SG — highlight it references ECS SG ID only
> 4. **IAM → Roles** — show the two ECS roles and their policies

---

<a name="step-7"></a>
## STEP 7: RDS — Data Tier
⏱️ *~10 minutes* | 📊 Slide: *"Data layer: RDS Postgres (Step 7)"*

### 🎤 WHAT TO SAY

> "RDS is managed PostgreSQL. Managed means AWS handles patching, backups, hardware failures. You just connect.
>
> Two things I want you to notice:
> - `storage_encrypted = true` — all data on disk is encrypted at rest. Non-negotiable.
> - `backup_retention_period = 7` — 7 days of automated backups. And please, actually test restoring from backup before you need it in production. Most teams never do.
>
> We're using `db.t3.micro` today for cost. In production this would be `db.t3.medium` or larger, and you'd enable Multi-AZ for automatic failover."

### 📄 `infra/envs/dev/rds.tf`

```hcl
resource "aws_db_subnet_group" "main" {
  name       = "${var.app_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "${var.app_name}-db-subnet-group" }
}

resource "aws_db_instance" "main" {
  identifier        = "${var.app_name}-db"
  engine            = "postgres"
  engine_version    = "15.4"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true      # ← Encrypt at rest

  db_name  = "appdb"
  username = "appuser"
  password = var.db_password    # ← From tfvars or env var, never hardcoded

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Backups
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  performance_insights_enabled = true

  # For demo — set false + enable deletion_protection in production
  skip_final_snapshot = true
  deletion_protection = false

  tags = { Name = "${var.app_name}-db" }
}
```

### Validate the Connection (from inside ECS)

```bash
# Connectivity check from inside ECS task
psql "$DATABASE_URL" -c "SELECT NOW();"

# Check backup status via CLI
aws rds describe-db-instances \
  --db-instance-identifier web-api-db \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Backup:BackupRetentionPeriod,Encrypted:StorageEncrypted}'
```

### 🖥️ AWS CONSOLE — WHAT TO SHOW

> 1. **RDS → Databases** — show the instance status (creating/available)
> 2. **Connectivity tab** — no public IP, private endpoint only
> 3. **Configuration tab** — `Storage encrypted: Yes`, backups enabled
> 4. **Monitoring tab** — show Performance Insights dashboard

---

<a name="step-8"></a>
## STEP 8: ECS on EC2 + ALB — Application Tier
⏱️ *~15 minutes* | 📊 Slide: *"Deploy compute: ECS on EC2 + ALB (Step 6 in deck)"*

### 🎤 WHAT TO SAY

> "This is the heart of our application tier. We're using ECS with EC2 launch type — meaning we provision actual EC2 instances that run the ECS agent, which manages our containers.
>
> Why EC2 launch type instead of Fargate? With EC2 you can see everything — the cluster, the instances, the ECS agent, the container placement. It's more educational and gives you more infrastructure control. Fargate abstracts all of this away.
>
> The ALB is the traffic cop. All requests hit the ALB first. It checks our containers are healthy via `/healthz` every 30 seconds, and only routes traffic to passing containers. If a container fails, the ALB stops sending traffic to it — ECS replaces it — and your users never see the failure."

### 📄 `infra/envs/dev/ecs.tf`

```hcl
# ─── ECS CLUSTER ──────────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = { Name = "${var.app_name}-cluster" }
}

# ─── LATEST ECS-OPTIMISED AMI ─────────────────────────────────
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

# ─── LAUNCH TEMPLATE ──────────────────────────────────────────
resource "aws_launch_template" "ecs" {
  name_prefix   = "${var.app_name}-ecs-lt-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = "t3.small"

  iam_instance_profile { arn = aws_iam_instance_profile.ecs.arn }
  vpc_security_group_ids = [aws_security_group.ecs.id]

  # Register instance with ECS cluster on boot
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config
    echo ECS_ENABLE_CONTAINER_METADATA=true >> /etc/ecs/ecs.config
  EOF
  )

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs { volume_size = 30; volume_type = "gp3"; encrypted = true; delete_on_termination = true }
  }

  monitoring { enabled = true }
  tags = { Name = "${var.app_name}-ecs-instance" }
}

# ─── AUTO SCALING GROUP ───────────────────────────────────────
resource "aws_autoscaling_group" "ecs" {
  name                = "${var.app_name}-ecs-asg"
  desired_capacity    = 2
  min_size            = 1
  max_size            = 4
  vpc_zone_identifier = aws_subnet.private[*].id
  protect_from_scale_in = true

  launch_template { id = aws_launch_template.ecs.id; version = "$Latest" }

  tag { key = "AmazonECSManaged"; value = "true"; propagate_at_launch = true }
  tag { key = "Name"; value = "${var.app_name}-ecs-instance"; propagate_at_launch = true }
}

# ─── CAPACITY PROVIDER (links ASG to ECS) ─────────────────────
resource "aws_ecs_capacity_provider" "main" {
  name = "${var.app_name}-cp"
  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "ENABLED"
    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 80
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 2
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.main.name]
  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.main.name
  }
}

# ─── CLOUDWATCH LOG GROUP ─────────────────────────────────────
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = 30
}

# ─── ALB ──────────────────────────────────────────────────────
resource "aws_lb" "main" {
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  tags               = { Name = "${var.app_name}-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = "${var.app_name}-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/healthz"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  deregistration_delay = 30
  tags = { Name = "${var.app_name}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action { type = "forward"; target_group_arn = aws_lb_target_group.app.arn }
}

# ─── ECS TASK DEFINITION ──────────────────────────────────────
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.app_name}-task"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  cpu    = 256
  memory = 512

  container_definitions = jsonencode([{
    name      = "app"
    image     = var.container_image
    essential = true

    portMappings = [{
      containerPort = 3000
      hostPort      = 0       # Dynamic port mapping
      protocol      = "tcp"
    }]

    environment = [
      { name = "ENV",     value = var.environment },
      { name = "DB_NAME", value = "appdb" },
      { name = "DB_USER", value = "appuser" },
      { name = "DB_HOST", value = aws_db_instance.main.address }
    ]

    # Pull secret from Secrets Manager (never hardcode passwords!)
    secrets = [{
      name      = "DB_PASSWORD"
      valueFrom = aws_secretsmanager_secret.db_password.arn
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "app"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:3000/healthz || exit 1"]
      interval    = 30; timeout = 5; retries = 3; startPeriod = 60
    }
  }])

  tags = { Name = "${var.app_name}-task" }
}

# ─── ECS SERVICE (self-healing, rolling deploys) ──────────────
resource "aws_ecs_service" "app" {
  name            = "${var.app_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.main.name
    weight = 100; base = 1
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 3000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60

  deployment_circuit_breaker { enable = true; rollback = true }

  depends_on = [aws_lb_listener.http]
  tags = { Name = "${var.app_name}-service" }
}
```

### Validate Deployment

```bash
aws ecs list-services --cluster web-api-cluster
aws ecs describe-services \
  --cluster web-api-cluster \
  --services web-api-service \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'

curl -s http://$(terraform output -raw alb_dns)/healthz
```

### 🖥️ AWS CONSOLE — WHAT TO SHOW

> 1. **ECS → Clusters** — show cluster with Container Insights enabled
> 2. **Infrastructure tab** — show EC2 container instances registered
> 3. **Services tab** — show service running 2/2 desired tasks
> 4. **Tasks tab** — click a task, show containers + logs link
> 5. **EC2 → Load Balancers** — copy ALB DNS, open in browser
> 6. **EC2 → Target Groups → Targets** — show healthy targets ✅

---

<a name="step-9"></a>
## STEP 9: S3 + CloudFront — Presentation Tier
⏱️ *~10 minutes* | 📊 Slide: *"Frontend: S3 + CloudFront (Step 9)"*

### 🎤 WHAT TO SAY

> "For the frontend, we don't need a server at all. Static HTML, CSS, and JS live in S3 — an object storage service. S3 is infinitely scalable, 99.999999999% durable, and costs almost nothing.
>
> But S3 alone has latency. A user in Nairobi hitting a bucket in us-east-1 will feel that distance.
>
> CloudFront fixes that. It's a CDN with over 450 edge locations globally. Your frontend gets cached at the edge closest to each user. That Nairobi user now gets served from the nearest edge node — not from Virginia.
>
> Notice the bucket is completely private. The only way to access files is through CloudFront using Origin Access Control. This is the secure way to do it — no public S3 URLs."

### 📄 `infra/envs/dev/cdn.tf`

```hcl
resource "random_id" "suffix" { byte_length = 4 }

# ─── S3 BUCKET (private — CloudFront only) ────────────────────
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.app_name}-frontend-${random_id.suffix.hex}"
  tags   = { Name = "${var.app_name}-frontend" }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration { status = "Enabled" }
}

# ─── ORIGIN ACCESS CONTROL (OAC) ──────────────────────────────
resource "aws_cloudfront_origin_access_control" "main" {
  name                              = "${var.app_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ─── CLOUDFRONT DISTRIBUTION ──────────────────────────────────
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  # Origin 1: S3 for static frontend
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
  }

  # Origin 2: ALB for API calls
  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "alb-api"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default behaviour: serve from S3
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
    default_ttl = 3600
    max_ttl     = 86400
  }

  # /api/* routes to ALB (no caching for API responses)
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "alb-api"
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Origin"]
      cookies { forward = "none" }
    }
    default_ttl = 0; max_ttl = 0
  }

  restrictions { geo_restriction { restriction_type = "none" } }
  viewer_certificate { cloudfront_default_certificate = true }

  tags = { Name = "${var.app_name}-cloudfront" }
}

# ─── S3 BUCKET POLICY (allow CloudFront OAC only) ─────────────
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.main.arn }
      }
    }]
  })
}
```

### Deploy Frontend

```bash
# Upload frontend files to S3
aws s3 sync ./frontend/ s3://$(terraform output -raw s3_bucket_name)

# Get the CloudFront URL
terraform output cloudfront_url
# Open in browser — served from nearest edge location globally!
```

### 🖥️ AWS CONSOLE — WHAT TO SHOW

> 1. **S3** — show the bucket, try to access a file directly — get 403 (correct!)
> 2. **CloudFront → Distributions** — show the distribution deployed
> 3. **Origins tab** — show both S3 and ALB origins
> 4. **Behaviors tab** — show `/api/*` goes to ALB, everything else to S3
> 5. Open CloudFront URL in browser — frontend loads instantly ✅

---

<a name="step-10"></a>
## STEP 10: Secrets Manager & Configuration
⏱️ *~8 minutes* | 📊 Slide: *"Secrets & configuration (Step 10)"*

### 🎤 WHAT TO SAY

> "Rule number one: never put secrets in code. Not in environment variables baked into the image. Not in `.env` files committed to git. Secrets live in Secrets Manager.
>
> The pattern is simple: the secret has a name. The ECS task definition references that name by ARN. At runtime, ECS injects the secret as an environment variable — the container never needs to call the Secrets Manager API itself.
>
> Separate roles for separate concerns: the ECS task role can read ONLY the secrets it needs. The CI/CD role can push images and update services — but can't read secrets. If credentials are ever compromised, blast radius is contained."

### 📄 `infra/envs/dev/secrets.tf`

```hcl
# ─── DB PASSWORD ──────────────────────────────────────────────
resource "aws_secretsmanager_secret" "db_password" {
  name        = "${var.app_name}/db_password"
  description = "RDS master password for ${var.app_name}"

  recovery_window_in_days = 7   # 7-day recovery before permanent deletion

  tags = { Name = "${var.app_name}-db-password" }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}

# ─── APP SECRETS (tokens, API keys, etc.) ─────────────────────
resource "aws_secretsmanager_secret" "app_secrets" {
  name        = "${var.app_name}/app"
  description = "Application secrets for ${var.app_name}"
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    jwt_secret = "replace-with-real-secret-in-production"
  })
}
```

### CLI Commands for Live Demo

```bash
# Create a secret
aws secretsmanager create-secret \
  --name web/prod/db_password \
  --secret-string '"super-secret"'

# Read it back (demo only — don't do this in prod scripts)
aws secretsmanager get-secret-value \
  --secret-id web/prod/db_password

# Rotate a secret (zero-downtime)
aws secretsmanager rotate-secret \
  --secret-id web/prod/db_password \
  --rotation-rules AutomaticallyAfterDays=30
```

### 🖥️ AWS CONSOLE — WHAT TO SHOW

> 1. **Secrets Manager → Secrets** — show the secrets created
> 2. Click a secret — show the ARN (this is what ECS task definition references)
> 3. Show **Rotation** tab — can be enabled for automatic rotation
> 4. **IAM → Roles → ecs-exec-role** — show it has access to these secrets only

---

<a name="step-11"></a>
## STEP 11: Observability — Logs, Metrics, Alarms
⏱️ *~8 minutes* | 📊 Slide: *"Observability: logs, metrics, alarms (Step 11)"*

### 🎤 WHAT TO SAY

> "Shipping to production without monitoring is like driving with your eyes closed. You need to know before your users do when something is wrong.
>
> The minimum viable monitoring stack: structured logs, three key metrics — 5xx error rate, p99 latency, CPU/memory — and alarms that route to a human. An alarm nobody sees is useless.
>
> Container Insights gives you per-container metrics automatically. We already enabled it on the ECS cluster. This is one line of Terraform that saves you hours of debugging."

### 📄 `infra/envs/dev/monitoring.tf`

```hcl
# SNS Topic for alarm notifications (routes to Slack/email)
resource "aws_sns_topic" "alerts" {
  name = "${var.app_name}-alerts"
  tags = { Name = "${var.app_name}-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "your-team@example.com"   # Replace with real email
}

# ─── ALARM: 5xx Error Rate ─────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.app_name}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "More than 10 5xx errors in 60 seconds"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

# ─── ALARM: Unhealthy Hosts ────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.app_name}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "At least one target is unhealthy"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.app.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

# ─── ALARM: ECS CPU High ───────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "${var.app_name}-ecs-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS CPU above 80% for 3 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }
}
```

### Quick Log Commands

```bash
# Live log tail
aws logs tail /ecs/web-api --follow

# Check ALB metrics
aws cloudwatch list-metrics \
  --namespace AWS/ApplicationELB | head -20
```

### 🖥️ AWS CONSOLE — WHAT TO SHOW

> 1. **CloudWatch → Container Insights → ECS** — show per-service CPU/memory graphs
> 2. **CloudWatch → Log Groups → /ecs/web-api** — show live container logs
> 3. **CloudWatch → Alarms** — show the three alarms we created (OK state)
> 4. Click an alarm → show the metric graph and threshold line

---

<a name="step-12"></a>
## STEP 12: CI/CD with GitHub Actions
⏱️ *~8 minutes* | 📊 Slide: *"CI/CD: GitHub Actions → AWS (Step 12)"*

### 🎤 WHAT TO SAY

> "Everything we've built so far requires a human to run `terraform apply` and `docker push`. CI/CD automates that. Every code push triggers the pipeline — test, build, push to ECR, deploy to ECS.
>
> The critical security practice here: use **OIDC authentication** — not long-lived access keys. GitHub Actions gets a short-lived token that assumes an IAM role. There are no AWS credentials stored as GitHub secrets. If the token leaks, it expires in minutes and is scoped to exactly one role.
>
> This is the deploy pattern that scales — `git push` is all a developer ever needs to do."

### 📄 `.github/workflows/deploy.yml`

```yaml
name: Deploy to AWS

on:
  push:
    branches: [main]

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: web-api
  ECS_CLUSTER: web-api-cluster
  ECS_SERVICE: web-api-service

permissions:
  id-token: write   # Required for OIDC
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '18' }
      - run: cd app && npm install && npm test

  build-push:
    needs: test
    runs-on: ubuntu-latest
    outputs:
      image: ${{ steps.build.outputs.image }}
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC — no long-lived keys!)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions-deploy
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build, tag, push
        id: build
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG ./app
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          echo "image=$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG" >> $GITHUB_OUTPUT

  deploy:
    needs: build-push
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions-deploy
          aws-region: ${{ env.AWS_REGION }}

      - name: Deploy to ECS (rolling update)
        run: |
          aws ecs update-service \
            --cluster ${{ env.ECS_CLUSTER }} \
            --service ${{ env.ECS_SERVICE }} \
            --force-new-deployment

      - name: Wait for service stability
        run: |
          aws ecs wait services-stable \
            --cluster ${{ env.ECS_CLUSTER }} \
            --services ${{ env.ECS_SERVICE }}
          echo "✅ Deploy complete"
```

### 🖥️ AWS CONSOLE — WHAT TO SHOW

> 1. **GitHub → Actions** tab — show a pipeline run in progress
> 2. Click the run — show test → build → deploy stages
> 3. **ECS → Cluster → Service → Deployments tab** — show rolling deploy in progress
> 4. **CloudWatch → Logs** — show new container starting up

---

<a name="hardening"></a>
## ✅ HARDENING CHECKLIST + TEARDOWN
⏱️ *~5 minutes* | 📊 Slide: *"Hardening checklist (prod-readiness)"*

### 🎤 WHAT TO SAY

> "Before you call anything production-ready, run through this checklist. It's from the AWS Well-Architected Framework — five pillars: Security, Reliability, Performance, Cost, Operations.
>
> And finally — one of the most powerful things about Terraform..."

### ✅ Production Readiness Checklist

**Security**
- [ ] IAM least privilege — task role + deploy role only
- [ ] MFA on root + remove all long-lived access keys
- [ ] TLS via ACM + HTTPS-only listener on ALB
- [ ] DB in private subnets, encrypted at rest + in transit
- [ ] No secrets in code or container images
- [ ] Image scanning enabled on ECR
- [ ] WAF (optional) for rate limiting + SQL injection protection

**Reliability**
- [ ] Multi-AZ on ALB, ECS (2+ tasks), and RDS option
- [ ] Health checks on all services
- [ ] Deployment circuit breaker + auto-rollback enabled
- [ ] Backups tested (actually restore one!)
- [ ] Runbook written — what to do when the alarm fires at 2am

**Cost**
- [ ] Budgets + anomaly detection configured
- [ ] ECR lifecycle policies (don't accumulate old images)
- [ ] Tagging strategy for cost allocation
- [ ] Review instance sizes after first week of real traffic

### Teardown

```bash
# ⚠️  Run this after the demo to avoid charges!
cd infra/envs/dev
terraform destroy -auto-approve

# One command. Every resource. In dependency order. Zero orphans.
# This is infrastructure as code.
```

---

## 💰 ESTIMATED MONTHLY COST (minimal scale)

| Resource | Spec | Est. Cost/Month |
|----------|------|-----------------|
| NAT Gateway | 1x | ~$45 |
| EC2 (ECS instances) | 2x t3.small | ~$30 |
| RDS PostgreSQL | db.t3.micro | ~$25 |
| ALB | 1x | ~$20 |
| CloudFront | Pay per request | ~$1–5 |
| S3 | Storage + requests | ~$1 |
| **Total** | | **~$120–130/mo** |

> 💡 The NAT Gateway ($45/month) is the biggest surprise for newcomers. For a staging environment, consider placing ECS in public subnets temporarily. For production, the security is worth it.

---

## 🚀 MASTER DEPLOYMENT COMMAND REFERENCE

```bash
# Bootstrap (one-time) — creates S3 state bucket + DynamoDB lock table
cd infra/bootstrap && terraform init && terraform apply
# Copy backend_config_snippet output into infra/envs/dev/main.tf, then:

# Build & Push image
GIT_SHA=$(git rev-parse --short HEAD)
ECR_URI=$(terraform output -raw ecr_repository_url)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URI
docker build -t web-api:${GIT_SHA} ./app
docker push ${ECR_URI}:${GIT_SHA}

# Deploy infrastructure
cd infra/envs/dev
terraform init
terraform plan -var="db_password=YourSecurePass123!" -var="container_image=${ECR_URI}:${GIT_SHA}"
terraform apply -var="db_password=YourSecurePass123!" -var="container_image=${ECR_URI}:${GIT_SHA}"

# Upload frontend
aws s3 sync ./frontend/ s3://$(terraform output -raw s3_bucket_name)

# Verify
curl -s $(terraform output -raw cloudfront_url)
aws logs tail /ecs/web-api --follow

# TEARDOWN (run after demo!)
terraform destroy -auto-approve
```

---

## ⏱️ WEBINAR TIMING GUIDE

| Step | Topic | Duration | Cumulative |
|------|-------|----------|------------|
| 0 | Prerequisites & Safety | 5 min | 5 min |
| 1 | Project Baseline | 5 min | 10 min |
| 2 | Dockerize Application | 10 min | 20 min |
| 3 | Terraform Remote State | 10 min | 30 min |
| 4 | VPC & Networking | 15 min | 45 min |
| 5 | ECR Registry | 8 min | 53 min |
| 6 | Security Groups & IAM | 8 min | 61 min |
| 7 | RDS Database | 10 min | 71 min |
| 8 | ECS on EC2 + ALB | 15 min | 86 min |
| 9 | S3 + CloudFront | 10 min | 96 min |
| 10 | Secrets Manager | 8 min | 104 min |
| 11 | Observability | 8 min | 112 min |
| 12 | CI/CD Pipeline | 8 min | 120 min |
| ✅ | Hardening + Teardown | 5 min | 125 min |
| Q&A | Community questions | 10–15 min | ~140 min |

---

## 💡 PRESENTATION TIPS FOR SATURDAY

1. **Pre-apply Terraform** before the session — infra takes 15–20 min. Use the AWS Console walkthroughs to show what was built.
2. **Have two browser tabs** — your code editor + AWS Console
3. **Open CloudWatch Logs** in a third tab — live logs during the demo are very visual
4. **Show the architecture diagram** (Slide 3) at every major step transition
5. **Emphasise WHY** at every step — not just what, but why we made each choice
6. **Run `terraform destroy`** live at the end — the single command teardown is always impressive

---

*Webinar: From Zero to Hero — AWS Production-Ready Demo*
*Stack: Node.js → Docker → ECR → ECS on EC2 → RDS → Secrets Manager → S3 + CloudFront → GitHub Actions*
*Aligns with slide deck: zero_to_hero_production_ready_aws.pptx (updated)*
