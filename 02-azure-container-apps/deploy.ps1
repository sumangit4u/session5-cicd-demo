# deploy.ps1 - ONE-SHOT deploy of the GenAI app to Azure Container Apps (Windows PowerShell).
#
# Mirrors the PDF's GCP Cloud Run steps, on Azure:
#   Cloud Run        -> Azure Container Apps   (serverless, scale-to-zero)
#   Artifact Registry-> Azure Container Registry (ACR)
#   gcloud           -> az
#
# Everything is created in ONE resource group so `teardown.ps1` can delete it all at once.
# Reads GOOGLE_API_KEY from ../../../module3_agents/.env and injects it as a Container App
# secret (never baked into the image).
#
# Prereqs: Azure CLI (`az`), an Azure subscription, and `az login` already done.
#
# Usage:  ./deploy.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot

# ---- Config (cheap by design) -------------------------------------------------
$RESOURCE_GROUP = "genai-session4-rg"
$LOCATION       = "centralindia"          # pick a region near your users
$ACR_NAME       = "genaiacr" + (Get-Random -Maximum 99999)   # must be globally unique
$ENV_NAME       = "genai-env"
$APP_NAME       = "genai-app"
$IMAGE_TAG      = "genai-app:latest"
$APP_SRC        = Join-Path $ScriptDir "..\app"               # the shared app/ folder
$ENV_FILE       = Join-Path $ScriptDir "..\..\..\module3_agents\.env"

# ---- Read the model key from the shared .env ---------------------------------
if (-not (Test-Path $ENV_FILE)) { throw "Cannot find shared secrets file: $ENV_FILE" }
$ApiKey = $null
foreach ($line in Get-Content $ENV_FILE) {
    if ($line -match '^\s*GOOGLE_API_KEY\s*=\s*(.+?)\s*$') { $ApiKey = $Matches[1].Trim('"').Trim("'") }
}
if (-not $ApiKey) { throw "GOOGLE_API_KEY not found in $ENV_FILE" }

Write-Host "==> Ensuring the containerapp CLI extension + providers are ready..." -ForegroundColor Cyan
az extension add --name containerapp --upgrade --only-show-errors | Out-Null
az provider register --namespace Microsoft.App --wait --only-show-errors | Out-Null
az provider register --namespace Microsoft.OperationalInsights --wait --only-show-errors | Out-Null
az provider register --namespace Microsoft.ContainerRegistry --wait --only-show-errors | Out-Null

Write-Host "==> [1/6] Resource group ($RESOURCE_GROUP in $LOCATION)..." -ForegroundColor Cyan
az group create --name $RESOURCE_GROUP --location $LOCATION --only-show-errors | Out-Null

Write-Host "==> [2/6] Container Registry ($ACR_NAME, Basic SKU)..." -ForegroundColor Cyan
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic `
    --admin-enabled true --only-show-errors | Out-Null

Write-Host "==> [3/6] Building image in the cloud (az acr build -> amd64, no local Docker needed)..." -ForegroundColor Cyan
az acr build --registry $ACR_NAME --image $IMAGE_TAG $APP_SRC --only-show-errors
if ($LASTEXITCODE -ne 0) {
    # ACR Tasks is blocked on free-trial / Azure-for-Students subscriptions
    # (TasksOperationsNotAllowed), so build locally like in Session 3 and push instead.
    Write-Warning "Cloud build failed - falling back to local Docker build + push (needs Docker Desktop running)."
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker not found. Start Docker Desktop (installed in Session 3) and rerun ./deploy.ps1"
    }
    az acr login --name $ACR_NAME | Out-Null
    docker build --platform linux/amd64 -t "$ACR_NAME.azurecr.io/$IMAGE_TAG" $APP_SRC
    if ($LASTEXITCODE -ne 0) { throw "docker build failed" }
    docker push "$ACR_NAME.azurecr.io/$IMAGE_TAG"
    if ($LASTEXITCODE -ne 0) { throw "docker push failed" }
}

Write-Host "==> [4/6] Container Apps environment ($ENV_NAME)..." -ForegroundColor Cyan
az containerapp env create --name $ENV_NAME --resource-group $RESOURCE_GROUP `
    --location $LOCATION --only-show-errors | Out-Null

# ACR admin creds so Container Apps can pull the private image (demo simplification;
# production would use a managed identity instead of admin credentials).
$AcrServer = "$ACR_NAME.azurecr.io"
$AcrUser   = az acr credential show --name $ACR_NAME --query username -o tsv
$AcrPass   = az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv

Write-Host "==> [5/6] Deploying to Container Apps (scale-to-zero, 0.5 vCPU / 1Gi)..." -ForegroundColor Cyan
az containerapp create `
    --name $APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --environment $ENV_NAME `
    --image "$AcrServer/$IMAGE_TAG" `
    --registry-server $AcrServer `
    --registry-username $AcrUser `
    --registry-password $AcrPass `
    --target-port 8000 `
    --ingress external `
    --min-replicas 0 `
    --max-replicas 5 `
    --cpu 0.5 --memory 1.0Gi `
    --secrets "gemini-api-key=$ApiKey" `
    --env-vars "GEMINI_API_KEY=secretref:gemini-api-key" `
    --only-show-errors | Out-Null

Write-Host "==> [6/6] Health check..." -ForegroundColor Cyan
$FQDN = az containerapp show --name $APP_NAME --resource-group $RESOURCE_GROUP `
    --query properties.configuration.ingress.fqdn -o tsv
Start-Sleep -Seconds 15
try {
    Invoke-RestMethod "https://$FQDN/health" | ConvertTo-Json
} catch {
    Write-Warning "Health check not ready yet - try again in a minute: https://$FQDN/health"
}

Write-Host ""
Write-Host "DONE. Your GenAI app is live at:  https://$FQDN" -ForegroundColor Green
Write-Host "Swagger docs:                     https://$FQDN/docs" -ForegroundColor Green
Write-Host ""
Write-Host "Remember to run ./teardown.ps1 when finished to stop all charges." -ForegroundColor Yellow
Write-Host "(ACR name was $ACR_NAME - it's inside $RESOURCE_GROUP, so teardown removes it too.)"
