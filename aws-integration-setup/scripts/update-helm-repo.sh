#!/bin/bash

# Update Helm Repository Script
# This script packages the chart and updates the Helm repository index

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CHART_DIR="charts/nullify-k8s-collector"
REPO_DIR="docs"
REPO_URL="https://nullify-cloud-connector.github.io/aws-integration-setup/"

echo -e "${BLUE}🔧 Updating Nullify Helm Repository${NC}"
echo "=================================="

# Check if Helm is available
if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ Helm is not installed or not in PATH${NC}"
    exit 1
fi

# Validate chart directory exists
if [ ! -d "$CHART_DIR" ]; then
    echo -e "${RED}❌ Chart directory not found: $CHART_DIR${NC}"
    exit 1
fi

# Create repository directory if it doesn't exist
mkdir -p "$REPO_DIR"

echo -e "${BLUE}📦 Packaging Helm chart...${NC}"
# Package the chart
if helm package "$CHART_DIR" -d "$REPO_DIR"; then
    echo -e "${GREEN}✅ Chart packaged successfully${NC}"
else
    echo -e "${RED}❌ Failed to package chart${NC}"
    exit 1
fi

echo -e "${BLUE}📋 Updating repository index...${NC}"
# Update the repository index
if helm repo index "$REPO_DIR" --url "$REPO_URL"; then
    echo -e "${GREEN}✅ Repository index updated${NC}"
else
    echo -e "${RED}❌ Failed to update repository index${NC}"
    exit 1
fi

# Show what was created/updated
echo -e "${BLUE}📁 Repository contents:${NC}"
ls -la "$REPO_DIR"

echo
echo -e "${GREEN}🎉 Helm repository updated successfully!${NC}"
echo
echo -e "${BLUE}📋 Next steps:${NC}"
echo "1. Commit and push changes to GitHub"
echo "2. Enable GitHub Pages for the repository (Settings > Pages > Source: Deploy from branch 'main' folder '/docs')"
echo "3. Users can then add the repository with:"
echo -e "${YELLOW}   helm repo add nullify $REPO_URL${NC}"
echo -e "${YELLOW}   helm repo update${NC}"
echo -e "${YELLOW}   helm install nullify-collector nullify/k8s-collector${NC}"

echo
echo -e "${BLUE}🔗 Repository URL will be: ${REPO_URL}${NC}" 