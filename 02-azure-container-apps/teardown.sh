#!/usr/bin/env bash
# teardown.sh - ONE-SHOT delete of EVERYTHING created by deploy.sh (macOS / Linux).
#
# deploy.sh puts the Container App, its environment, the Log Analytics workspace, AND
# the Container Registry all inside ONE resource group, so a single `az group delete`
# removes the whole lot. This guarantees nothing keeps billing after class.
#
# Usage:  ./teardown.sh
set -euo pipefail

RESOURCE_GROUP="genai-session4-rg"

echo "Deleting resource group '$RESOURCE_GROUP' and ALL resources inside it..."
az group delete --name "$RESOURCE_GROUP" --yes --no-wait

echo "Delete started (background). Verify with: az group show --name $RESOURCE_GROUP"
echo "(It should eventually report 'ResourceGroupNotFound'.)"
