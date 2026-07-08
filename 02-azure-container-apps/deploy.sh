#!/usr/bin/env bash
# deploy.sh - ONE-SHOT deploy of the GenAI app to Azure Container Apps (macOS / Linux).
#
# Mirrors the PDF's GCP Cloud Run steps, on Azure:
#   Cloud Run -> Azure Container Apps | Artifact Registry -> ACR | gcloud -> az
#
# Everything goes in ONE resource group so teardown.sh can delete it all at once.
# Reads GOOGLE_API_KEY from ../../../module3_agents/.env and injects it as a secret.
#
# Prereqs: Azure CLI (`az`), a subscription, and `az login` already done.
# Usage:   ./deploy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Config (cheap by design) ----
RESOURCE_GROUP="genai-session4-rg"
LOCATION="centralindia"                 # pick a region near your users
ACR_NAME="genaiacr$RANDOM"              # must be globally unique
ENV_NAME="genai-env"
APP_NAME="genai-app"
IMAGE_TAG="genai-app:latest"
APP_SRC="$SCRIPT_DIR/../app"
ENV_FILE="$SCRIPT_DIR/../../../module3_agents/.env"

# ---- Read the model key from the shared .env ----
[ -f "$ENV_FILE" ] || { echo "Cannot find shared secrets file: $ENV_FILE"; exit 1; }
API_KEY="$(grep -E '^\s*GOOGLE_API_KEY\s*=' "$ENV_FILE" | head -1 | cut -d'=' -f2- | tr -d '"'"'"' ')"
[ -n "$API_KEY" ] || { echo "GOOGLE_API_KEY not found in $ENV_FILE"; exit 1; }

echo "==> Ensuring containerapp extension + providers..."
az extension add --name containerapp --upgrade --only-show-errors >/dev/null
az provider register --namespace Microsoft.App --wait --only-show-errors >/dev/null
az provider register --namespace Microsoft.OperationalInsights --wait --only-show-errors >/dev/null
az provider register --namespace Microsoft.ContainerRegistry --wait --only-show-errors >/dev/null

echo "==> [1/6] Resource group ($RESOURCE_GROUP in $LOCATION)..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --only-show-errors >/dev/null

echo "==> [2/6] Container Registry ($ACR_NAME, Basic SKU)..."
az acr create --resource-group "$RESOURCE_GROUP" --name "$ACR_NAME" --sku Basic \
    --admin-enabled true --only-show-errors >/dev/null

echo "==> [3/6] Building image in the cloud (az acr build -> amd64)..."
if ! az acr build --registry "$ACR_NAME" --image "$IMAGE_TAG" "$APP_SRC" --only-show-errors; then
    # ACR Tasks is blocked on free-trial / Azure-for-Students subscriptions
    # (TasksOperationsNotAllowed), so build locally like in Session 3 and push instead.
    echo "!! Cloud build failed - falling back to local Docker build + push (needs Docker running)."
    command -v docker >/dev/null || { echo "Docker not found. Start Docker Desktop (Session 3) and rerun ./deploy.sh"; exit 1; }
    az acr login --name "$ACR_NAME"
    docker build --platform linux/amd64 -t "$ACR_NAME.azurecr.io/$IMAGE_TAG" "$APP_SRC"
    docker push "$ACR_NAME.azurecr.io/$IMAGE_TAG"
fi

echo "==> [4/6] Container Apps environment ($ENV_NAME)..."
az containerapp env create --name "$ENV_NAME" --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" --only-show-errors >/dev/null

ACR_SERVER="$ACR_NAME.azurecr.io"
ACR_USER="$(az acr credential show --name "$ACR_NAME" --query username -o tsv)"
ACR_PASS="$(az acr credential show --name "$ACR_NAME" --query 'passwords[0].value' -o tsv)"

echo "==> [5/6] Deploying to Container Apps (scale-to-zero, 0.5 vCPU / 1Gi)..."
az containerapp create \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --environment "$ENV_NAME" \
    --image "$ACR_SERVER/$IMAGE_TAG" \
    --registry-server "$ACR_SERVER" \
    --registry-username "$ACR_USER" \
    --registry-password "$ACR_PASS" \
    --target-port 8000 \
    --ingress external \
    --min-replicas 0 \
    --max-replicas 5 \
    --cpu 0.5 --memory 1.0Gi \
    --secrets "gemini-api-key=$API_KEY" \
    --env-vars "GEMINI_API_KEY=secretref:gemini-api-key" \
    --only-show-errors >/dev/null

echo "==> [6/6] Health check..."
FQDN="$(az containerapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" \
    --query properties.configuration.ingress.fqdn -o tsv)"
sleep 15
curl -fsS "https://$FQDN/health" || echo "(not ready yet - retry in a minute)"

echo ""
echo "DONE. Live at:  https://$FQDN"
echo "Swagger docs:   https://$FQDN/docs"
echo "Run ./teardown.sh when finished to stop all charges (ACR was $ACR_NAME)."
