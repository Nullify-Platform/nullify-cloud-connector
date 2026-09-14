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
  --eks-access-regions R1,R2
                        Regions holding a managed EKS scan access stack
                        (nullify-eks-managed-scan-access.json). They are deleted
                        before the role stack, so no access entry outlives the role.
  --eks-access-stack-name NAME
                        Access stack name in each region
                        (default: nullify-eks-managed-scan-access)

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
EKS_ACCESS_REGIONS=""
EKS_ACCESS_STACK_NAME="nullify-eks-managed-scan-access"
RELEASE_NAME="nullify-collector"
NAMESPACE="nullify"
TF_DIR="${REPO_ROOT}/aws-integration-setup/terraform"
SKIP_CONFIRM=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --method) METHOD="$2"; shift 2 ;;
    --stack-name) STACK_NAME="$2"; shift 2 ;;
    --eks-access-regions) EKS_ACCESS_REGIONS="$2"; shift 2 ;;
    --eks-access-stack-name) EKS_ACCESS_STACK_NAME="$2"; shift 2 ;;
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

delete_eks_access_stacks() {
  local region
  local -a regions
  IFS=',' read -r -a regions <<< "$EKS_ACCESS_REGIONS"
  for region in "${regions[@]}"; do
    if ! aws cloudformation describe-stacks --region "$region" --stack-name "$EKS_ACCESS_STACK_NAME" &>/dev/null; then
      echo -e "${YELLOW}No stack '${EKS_ACCESS_STACK_NAME}' in ${region}; skipping.${NC}"
      continue
    fi
    echo -e "${BLUE}Deleting EKS access stack '${EKS_ACCESS_STACK_NAME}' in ${region}...${NC}"
    aws cloudformation delete-stack --region "$region" --stack-name "$EKS_ACCESS_STACK_NAME"
    if ! aws cloudformation wait stack-delete-complete --region "$region" --stack-name "$EKS_ACCESS_STACK_NAME"; then
      echo -e "${RED}Deleting '${EKS_ACCESS_STACK_NAME}' in ${region} failed or timed out; the role stack was not deleted.${NC}"
      exit 1
    fi
    echo -e "${GREEN}Stack '${EKS_ACCESS_STACK_NAME}' in ${region} deleted.${NC}"
  done
}

case $METHOD in
  cloudformation)
    echo -e "${BLUE}${BOLD}Removing CloudFormation stack: ${STACK_NAME}${NC}"

    if [[ -z "$EKS_ACCESS_REGIONS" ]]; then
      echo -e "${YELLOW}No --eks-access-regions given. If you deployed nullify-eks-managed-scan-access.json, pass its regions so those stacks are deleted first; access entries are not removed with the role.${NC}"
      echo -e "${YELLOW}Access entries created by setup-eks-managed-scan.sh need its 'remove' action.${NC}"
    fi

    MAIN_STACK_EXISTS=true
    if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
      MAIN_STACK_EXISTS=false
    fi

    if [[ "$MAIN_STACK_EXISTS" != true && -z "$EKS_ACCESS_REGIONS" ]]; then
      echo -e "${YELLOW}Stack '${STACK_NAME}' not found. Nothing to clean up.${NC}"
      exit 0
    fi

    confirm

    if [[ -n "$EKS_ACCESS_REGIONS" ]]; then
      delete_eks_access_stacks
    fi

    if [[ "$MAIN_STACK_EXISTS" != true ]]; then
      echo -e "${YELLOW}Stack '${STACK_NAME}' not found; only the EKS access stacks were removed.${NC}"
    else
      echo -e "${BLUE}Deleting stack...${NC}"
      aws cloudformation delete-stack --stack-name "$STACK_NAME"

      echo -e "${BLUE}Waiting for stack deletion to complete...${NC}"
      if aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" 2>/dev/null; then
        echo -e "${GREEN}Stack '${STACK_NAME}' deleted successfully.${NC}"
      else
        echo -e "${RED}Stack deletion failed or timed out. Check the AWS Console for details.${NC}"
        exit 1
      fi
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
