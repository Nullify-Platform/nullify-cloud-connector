#!/bin/bash
# Nullify Cloud Connector - Deployment Validation Script
# Validates AWS IAM setup and optional Kubernetes resources.
#
# Usage:
#   ./validate-deployment.sh --role-arn <ARN> --external-id <ID> [--namespace nullify] [--check-k8s]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass()  { ((PASS++)); echo -e "  ${GREEN}[PASS]${NC} $1"; }
fail()  { ((FAIL++)); echo -e "  ${RED}[FAIL]${NC} $1"; }
warn()  { ((WARN++)); echo -e "  ${YELLOW}[WARN]${NC} $1"; }
info()  { echo -e "  ${BLUE}[INFO]${NC} $1"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Required:
  --role-arn ARN        The Nullify IAM role ARN created in your account
  --external-id ID      The external ID for role assumption

Optional:
  --nullify-role-arn ARN  The Nullify cross-account role ARN (to test trust policy)
  --namespace NS          Kubernetes namespace (default: nullify)
  --check-k8s             Also validate Kubernetes resources
  --s3-bucket NAME        Validate S3 bucket access
  -h, --help              Show this help message

Examples:
  # Validate AWS-only setup
  $(basename "$0") --role-arn arn:aws:iam::123456789012:role/AWSIntegration-acme-NullifyReadOnlyRole --external-id my-external-id

  # Validate with Kubernetes
  $(basename "$0") --role-arn arn:aws:iam::123456789012:role/AWSIntegration-acme-NullifyReadOnlyRole --external-id my-external-id --check-k8s
EOF
  exit 0
}

# Parse arguments
ROLE_ARN=""
EXTERNAL_ID=""
NULLIFY_ROLE_ARN=""
NAMESPACE="nullify"
CHECK_K8S=false
S3_BUCKET=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --role-arn) ROLE_ARN="$2"; shift 2 ;;
    --external-id) EXTERNAL_ID="$2"; shift 2 ;;
    --nullify-role-arn) NULLIFY_ROLE_ARN="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --check-k8s) CHECK_K8S=true; shift ;;
    --s3-bucket) S3_BUCKET="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

if [[ -z "$ROLE_ARN" || -z "$EXTERNAL_ID" ]]; then
  echo -e "${RED}Error: --role-arn and --external-id are required${NC}"
  echo ""
  usage
fi

# ── Prerequisites ──────────────────────────────────────────────────
echo -e "${BLUE}=== Nullify Deployment Validation ===${NC}"
echo ""
echo -e "${BLUE}[1/5] Checking prerequisites...${NC}"

if command -v aws &>/dev/null; then
  AWS_VERSION=$(aws --version 2>&1 | head -1)
  pass "AWS CLI installed ($AWS_VERSION)"
else
  fail "AWS CLI not installed (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)"
fi

if aws sts get-caller-identity &>/dev/null; then
  CALLER=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null)
  pass "AWS credentials configured ($CALLER)"
else
  fail "AWS credentials not configured or expired (run: aws configure)"
fi

if $CHECK_K8S; then
  if command -v kubectl &>/dev/null; then
    pass "kubectl installed"
  else
    fail "kubectl not installed (required for --check-k8s)"
  fi

  if kubectl cluster-info &>/dev/null 2>&1; then
    pass "Kubernetes cluster reachable"
  else
    fail "Cannot reach Kubernetes cluster (check KUBECONFIG)"
  fi
fi

# ── IAM Role ──────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[2/5] Validating IAM role...${NC}"

# Check role exists
if aws iam get-role --role-name "$(echo "$ROLE_ARN" | awk -F'/' '{print $NF}')" &>/dev/null 2>&1; then
  pass "IAM role exists"
else
  fail "IAM role not found: $ROLE_ARN"
fi

# Check attached policies
POLICY_COUNT=$(aws iam list-attached-role-policies --role-name "$(echo "$ROLE_ARN" | awk -F'/' '{print $NF}')" --query 'length(AttachedPolicies)' --output text 2>/dev/null || echo "0")
if [[ "$POLICY_COUNT" -ge 3 ]]; then
  pass "IAM role has $POLICY_COUNT attached policies"
else
  warn "IAM role has only $POLICY_COUNT attached policies (expected at least 3: ReadOnly Part1, Part2, DenyActions)"
fi

# Test assume role
echo ""
echo -e "${BLUE}[3/5] Testing role assumption...${NC}"

if [[ -n "$NULLIFY_ROLE_ARN" ]]; then
  info "Skipping assume-role test (cross-account role can only be tested from Nullify's account)"
  info "Nullify cross-account role: $NULLIFY_ROLE_ARN"
else
  info "Skipping assume-role test (pass --nullify-role-arn to test trust policy)"
fi

# Check trust policy has external ID condition
TRUST_POLICY=$(aws iam get-role --role-name "$(echo "$ROLE_ARN" | awk -F'/' '{print $NF}')" --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null || echo "{}")
if echo "$TRUST_POLICY" | grep -q "sts:ExternalId"; then
  pass "Trust policy includes ExternalId condition"
else
  fail "Trust policy missing ExternalId condition (security risk)"
fi

# ── S3 Bucket ─────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[4/5] Validating optional integrations...${NC}"

if [[ -n "$S3_BUCKET" ]]; then
  if aws s3api head-bucket --bucket "$S3_BUCKET" &>/dev/null 2>&1; then
    pass "S3 bucket '$S3_BUCKET' exists and is accessible"
  else
    fail "S3 bucket '$S3_BUCKET' not found or not accessible"
  fi
else
  info "S3 bucket validation skipped (pass --s3-bucket to check)"
fi

# ── Kubernetes ────────────────────────────────────────────────────
if $CHECK_K8S; then
  echo ""
  echo -e "${BLUE}[5/5] Validating Kubernetes resources...${NC}"

  # Namespace
  if kubectl get namespace "$NAMESPACE" &>/dev/null 2>&1; then
    pass "Namespace '$NAMESPACE' exists"
  else
    fail "Namespace '$NAMESPACE' not found"
  fi

  # Service Account
  SA_NAME="nullify-k8s-collector-sa"
  if kubectl get serviceaccount "$SA_NAME" -n "$NAMESPACE" &>/dev/null 2>&1; then
    pass "ServiceAccount '$SA_NAME' exists"

    # Check IRSA annotation
    IRSA_ANNOTATION=$(kubectl get serviceaccount "$SA_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
    if [[ -n "$IRSA_ANNOTATION" ]]; then
      if [[ "$IRSA_ANNOTATION" == "$ROLE_ARN" ]]; then
        pass "IRSA annotation matches role ARN"
      else
        fail "IRSA annotation mismatch: got '$IRSA_ANNOTATION', expected '$ROLE_ARN'"
      fi
    else
      fail "ServiceAccount missing IRSA annotation (eks.amazonaws.com/role-arn)"
    fi
  else
    fail "ServiceAccount '$SA_NAME' not found in namespace '$NAMESPACE'"
  fi

  # ClusterRole
  if kubectl get clusterrole nullify-k8s-collector-role &>/dev/null 2>&1; then
    pass "ClusterRole 'nullify-k8s-collector-role' exists"
  else
    fail "ClusterRole 'nullify-k8s-collector-role' not found"
  fi

  # ClusterRoleBinding
  if kubectl get clusterrolebinding nullify-k8s-collector-rolebinding &>/dev/null 2>&1; then
    pass "ClusterRoleBinding exists"
  else
    fail "ClusterRoleBinding 'nullify-k8s-collector-rolebinding' not found"
  fi

  # CronJob
  if kubectl get cronjob nullify-k8s-collector -n "$NAMESPACE" &>/dev/null 2>&1; then
    pass "CronJob 'nullify-k8s-collector' exists"

    # Check last run
    LAST_RUN=$(kubectl get jobs -n "$NAMESPACE" -l app=nullify-k8s-collector --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].status.succeeded}' 2>/dev/null || echo "")
    if [[ "$LAST_RUN" == "1" ]]; then
      pass "Last collector job completed successfully"
    elif [[ -z "$LAST_RUN" ]]; then
      info "No collector job runs found yet (CronJob may not have triggered)"
    else
      warn "Last collector job did not succeed (check logs: kubectl logs -l app=nullify-k8s-collector -n $NAMESPACE)"
    fi
  else
    fail "CronJob 'nullify-k8s-collector' not found in namespace '$NAMESPACE'"
  fi
else
  echo ""
  echo -e "${BLUE}[5/5] Kubernetes validation skipped (pass --check-k8s to enable)${NC}"
fi

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}=== Validation Summary ===${NC}"
echo -e "  ${GREEN}Passed: $PASS${NC}"
[[ $WARN -gt 0 ]] && echo -e "  ${YELLOW}Warnings: $WARN${NC}"
[[ $FAIL -gt 0 ]] && echo -e "  ${RED}Failed: $FAIL${NC}"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}Validation FAILED — please fix the issues above.${NC}"
  exit 1
else
  echo -e "${GREEN}Validation PASSED — Nullify integration is configured correctly.${NC}"
  exit 0
fi
