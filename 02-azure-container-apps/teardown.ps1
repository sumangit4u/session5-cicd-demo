# teardown.ps1 - ONE-SHOT delete of EVERYTHING created by deploy.ps1 (Windows PowerShell).
#
# Because deploy.ps1 puts the Container App, its environment, the Log Analytics
# workspace, AND the Container Registry all inside a single resource group, a single
# `az group delete` removes the whole lot in one shot. This is the reliable way to
# guarantee no resource keeps billing after class.
#
# Usage:  ./teardown.ps1

$ErrorActionPreference = "Stop"
$RESOURCE_GROUP = "genai-session4-rg"

Write-Host "Deleting resource group '$RESOURCE_GROUP' and ALL resources inside it..." -ForegroundColor Yellow
az group delete --name $RESOURCE_GROUP --yes --no-wait

Write-Host "Delete started (running in the background)." -ForegroundColor Green
Write-Host "Verify it's gone with:  az group show --name $RESOURCE_GROUP"
Write-Host "(It should eventually report 'ResourceGroupNotFound'.)"
