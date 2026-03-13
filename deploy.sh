#!/usr/bin/env bash
# deploy.sh — Run ONCE from your laptop to bootstrap everything.
# After this, all future deploys happen automatically via GitHub Actions on git push.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
BOOTSTRAP_DIR="$PROJECT_ROOT/infra/bootstrap"
DEV_DIR="$PROJECT_ROOT/infra/envs/dev"
APP_NAME="web-api"
AWS_REGION="us-east-1"

# ── PREFLIGHT ─────────────────────────────────────────────────
echo "==> Checking required tools..."
for tool in aws terraform docker git; do
  command -v "$tool" &>/dev/null || { echo "ERROR: $tool not found"; exit 1; }
done

aws sts get-caller-identity --query 'Account' --output text &>/dev/null \
  || { echo "ERROR: AWS credentials not configured. Run: aws configure"; exit 1; }

[[ -z "${DB_PASSWORD:-}" ]] && { echo "ERROR: export DB_PASSWORD=YourPass before running."; exit 1; }

# ── STEP 1: BOOTSTRAP STATE BACKEND ──────────────────────────
echo ""
echo "==> [1/4] Bootstrapping Terraform state backend (S3 + DynamoDB)..."
cd "$BOOTSTRAP_DIR"
terraform init -input=false
terraform apply -input=false -auto-approve \
  -var="app_name=$APP_NAME" \
  -var="aws_region=$AWS_REGION"

S3_BUCKET=$(terraform output -raw s3_bucket_name)
DYNAMO_TABLE=$(terraform output -raw dynamodb_table_name)
echo "    State bucket : $S3_BUCKET"
echo "    Lock table   : $DYNAMO_TABLE"

# ── STEP 2: AUTO-PATCH BACKEND BLOCK ─────────────────────────
echo ""
echo "==> [2/4] Patching backend config in infra/envs/dev/main.tf..."
MAIN_TF="$DEV_DIR/main.tf"
sed -i "s|bucket\s*=\s*\"[^\"]*tfstate[^\"]*\"|bucket         = \"$S3_BUCKET\"|" "$MAIN_TF"
sed -i "s|dynamodb_table\s*=\s*\"[^\"]*\"|dynamodb_table = \"$DYNAMO_TABLE\"|" "$MAIN_TF"
echo "    Backend patched."

# ── STEP 3: APPLY FULL INFRASTRUCTURE ────────────────────────
echo ""
echo "==> [3/4] Applying full infrastructure (VPC, ECS, RDS, ALB, CloudFront)..."
cd "$DEV_DIR"
terraform init -input=false \
  -backend-config="bucket=$S3_BUCKET" \
  -backend-config="key=$APP_NAME/dev/terraform.tfstate" \
  -backend-config="region=$AWS_REGION" \
  -backend-config="dynamodb_table=$DYNAMO_TABLE" \
  -backend-config="encrypt=true" \
  -reconfigure

terraform apply -input=false -auto-approve \
  -var="db_password=$DB_PASSWORD" \
  -var="app_name=$APP_NAME" \
  -var="aws_region=$AWS_REGION"

ECR_URI=$(terraform output -raw ecr_repository_url)
ALB_DNS=$(terraform output -raw alb_dns)
CF_URL=$(terraform output -raw cloudfront_url)
S3_FRONTEND=$(terraform output -raw s3_bucket_name)

# ── STEP 4: FIRST IMAGE PUSH FROM LAPTOP ─────────────────────
# After this, GitHub Actions handles all future image builds and pushes.
echo ""
echo "==> [4/4] Building and pushing initial Docker image to ECR..."
GIT_SHA=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD)
IMAGE_TAG="sha-$GIT_SHA"

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_URI"

docker build -t "$APP_NAME:$IMAGE_TAG" "$PROJECT_ROOT/app"
docker tag "$APP_NAME:$IMAGE_TAG" "$ECR_URI:$IMAGE_TAG"
docker push "$ECR_URI:$IMAGE_TAG"
echo "    Pushed: $ECR_URI:$IMAGE_TAG"

# Force ECS to use the new image
aws ecs update-service \
  --cluster "$APP_NAME-cluster" \
  --service "$APP_NAME-service" \
  --force-new-deployment \
  --region "$AWS_REGION" > /dev/null

# Upload frontend
aws s3 sync "$PROJECT_ROOT/frontend/" "s3://$S3_FRONTEND" --delete

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           BOOTSTRAP COMPLETE-Infra is live              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  ALB endpoint   : http://%-36s║\n" "$ALB_DNS"
printf "║  CloudFront URL : %-39s║\n" "$CF_URL"
printf "║  ECR URI        : %-39s║\n" "$ECR_URI"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  From now on — just git push to main.                        ║"
echo "║  GitHub Actions will build, push to ECR, and redeploy ECS.   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. Add these secrets to your GitHub repo:"
echo "     AWS_ACCOUNT_ID = $(aws sts get-caller-identity --query Account --output text)"
echo "  2. Add the OIDC trust to IAM (already provisioned by Terraform)"
echo "  3. git push origin main  →  pipeline runs automatically"
