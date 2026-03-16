#!/bin/bash
# Nullify Cloud Connector - Cleanup Script
# Removes Nullify integration resources.
#
# Usage:
#   ./cleanup.sh --method cloudformation|terraform|helm [OPTIONS]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") --method <METHOD> [OPTIONS]

Required:
  --method METHOD       Deployment method: cloudformation, terraform, or helm

Options (CloudFormation):
  --stack-name NAME     CloudFormation stack name (default: nullify-integration)

Options (Helm):
  --release NAME        Helm release name (default: nullify-collector)
  --namespace NS        Kubernetes namespace (default: nullify)

Options (Terraform):
  --tf-dir DIR          Terraform working directory

General:
  --yes                 Skip confirmation prompt
  -h, --help            Show this help message
EOF
  exit 0
}

METHOD=""
STACK_NAME="nullify-integration"
RELEASE_NAME="nullify-collector"
NAMESPACE="nullify"
TF_DIR="${REPO_ROOT}/aws-integration-setup/terraform"
SKIP_CONFIRM=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --method) METHOD="$2"; shift 2 ;;
    --stack-name) STACK_NAME="$2"; shift 2 ;;
    --release) RELEASE_NAME="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --tf-dir) TF_DIR="$2"; shift 2 ;;
    --yes) SKIP_CONFIRM=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

if [[ -z "$METHOD" ]]; then
  echo -e "${RED}Error: --method is required${NC}"
  echo ""
  usage
fi

confirm() {
  if $SKIP_CONFIRM; then return 0; fi
  echo ""
  echo -e "${YELLOW}${BOLD}WARNING: This will permanently remove Nullify integration resources.${NC}"
  read -rp "Are you sure? (type 'yes' to confirm): " RESPONSE
  if [[ "$RESPONSE" != "yes" ]]; then
    echo -e "${RED}Aborted.${NC}"
    exit 1
  fi
}

case $METHOD in
  cloudformation)
    echo -e "${BLUE}${BOLD}Removing CloudFormation stack: ${STACK_NAME}${NC}"

    if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null 2>&1; then
      echo -e "${YELLOW}Stack '${STACK_NAME}' not found. Nothing to clean up.${NC}"
      exit 0
    fi

    confirm

    echo -e "${BLUE}Deleting stack...${NC}"
    aws cloudformation delete-stack --stack-name "$STACK_NAME"

    echo -e "${BLUE}Waiting for stack deletion to complete...${NC}"
    if aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" 2>/dev/null; then
      echo -e "${GREEN}Stack '${STACK_NAME}' deleted successfully.${NC}"
    else
      echo -e "${RED}Stack deletion failed or timed out. Check the AWS Console for details.${NC}"
      exit 1
    fi
    ;;

  terraform)
    echo -e "${BLUE}${BOLD}Removing Terraform resources from: ${TF_DIR}${NC}"

    if [[ ! -d "$TF_DIR" ]]; then
      echo -e "${RED}Terraform directory not found: ${TF_DIR}${NC}"
      exit 1
    fi

    confirm

    cd "$TF_DIR"
    echo -e "${BLUE}Running terraform destroy...${NC}"
    terraform destroy -auto-approve
    echo -e "${GREEN}Terraform resources destroyed successfully.${NC}"
    ;;

  helm)
    echo -e "${BLUE}${BOLD}Removing Helm release: ${RELEASE_NAME} (namespace: ${NAMESPACE})${NC}"

    if ! helm status "$RELEASE_NAME" -n "$NAMESPACE" &>/dev/null 2>&1; then
      echo -e "${YELLOW}Helm release '${RELEASE_NAME}' not found in namespace '${NAMESPACE}'. Nothing to clean up.${NC}"
      exit 0
    fi

    confirm

    echo -e "${BLUE}Uninstalling Helm release...${NC}"
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"

    echo -e "${BLUE}Cleaning up namespace...${NC}"
    read -rp "Delete namespace '${NAMESPACE}'? [y/N]: " DELETE_NS
    if [[ "$DELETE_NS" =~ ^[yY]$ ]]; then
      kubectl delete namespace "$NAMESPACE" --wait=false
      echo -e "${GREEN}Namespace '${NAMESPACE}' deletion initiated.${NC}"
    fi

    echo -e "${GREEN}Helm release '${RELEASE_NAME}' removed successfully.${NC}"
    ;;

  *)
    echo -e "${RED}Error: Invalid method '${METHOD}'. Use: cloudformation, terraform, or helm${NC}"
    exit 1
    ;;
esac

echo ""
echo -e "${GREEN}Cleanup complete.${NC}"
echo -e "${BLUE}Note: The Nullify cross-account role in Nullify's account is managed by Nullify and does not need to be removed.${NC}"
