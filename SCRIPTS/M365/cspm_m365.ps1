<#
.SYNOPSIS
Script PowerShell para automatizar a criacao de aplicacao no Entra ID e configuracao de permissoes para rodar vulneri_cspm_m365 no Microsoft 365 (M365).

.DESCRIPTION
Baseado no seu script Bash, realiza:
- Verificacao da existencia do Azure CLI
- Login interativo (caso nao autenticado)
- Criacao da aplicacao e client secret
- Recuperacao e adicao das permissoes via GUIDs para Microsoft Graph, Exchange Online e Skype and Teams Tenant Admin API
- Consentimento administrativo para todas as permissoes (quando possivel)
- Exportacao das variaveis de ambiente para arquivo .txt para uso em shell

.NOTES
Requer Azure CLI instalado e suporta execucao em PowerShell no Windows/Linux.
#>

# Forca encerramento em erros
$ErrorActionPreference = "Stop"

function Check-AzCli {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Error "Azure CLI nao encontrada. Por favor instale antes de prosseguir."
        exit 1
    } else {
        Write-Host "[OK] Azure CLI encontrado."
    }
}

function Start-AzLogin {
    try {
        az account show > $null 2>&1
    }
    catch {
        Write-Host "--- Login Azure/Microsoft 365 ---"
        Write-Host "Por favor faca login na sua conta Azure/M365."
        az login --allow-no-subscriptions | Out-Null
    }
}

function Get-GuidForPermission {
    param(
        [string]$ServicePrincipalId,
        [string]$PermissionName
    )
    $sp = az ad sp show --id $ServicePrincipalId | ConvertFrom-Json
    foreach($role in $sp.appRoles) {
        if ($role.value -eq $PermissionName) {
            return $role.id
        }
    }
    return $null
}

Write-Host "=== Iniciando CSPM_M365: Configuracao automatizada para Vulneri_CSPM_M365 ==="

Check-AzCli
Start-AzLogin

$timestamp = [int][double]::Parse((Get-Date -UFormat %s))
$AppName = "Vulneri_CSPM_M365_$timestamp"
$SecretName = "Vulneri_CSPM_M365Secret"

Write-Host ("[INFO] Criando aplicacao Azure AD (Entra ID) com nome: {0}" -f $AppName)
$appJson = az ad app create --display-name $AppName | ConvertFrom-Json

$AppId = $appJson.appId
$ObjectId = $appJson.id

if ([string]::IsNullOrEmpty($AppId) -or $AppId -eq "null") {
    Write-Error "[ERRO] Falha ao criar a aplicacao Azure AD."
    exit 1
}

$TenantId = (az account show | ConvertFrom-Json).tenantId

Write-Host "[INFO] Registrando segredo de cliente da aplicacao..."
$secretJson = az ad app credential reset --id $AppId --append --display-name $SecretName | ConvertFrom-Json
$SecretValue = $secretJson.password

if ([string]::IsNullOrEmpty($SecretValue) -or $SecretValue -eq "null") {
    Write-Error "[ERRO] Falha ao gerar o segredo da aplicacao."
    exit 1
}

Write-Host ""
Write-Host "[INFO] Resolvendo GUIDs das permissoes necessarias para o vulneri_cspm_m365..."

$MsGraphApi = "00000003-0000-0000-c000-000000000000"
$ExchangeApi = "00000002-0000-0ff1-ce00-000000000000"
$TeamsApi = "48ac35b8-9aa8-4d74-927d-1f4a14a0b239"

$graphPermissions = @(
    "AuditLog.Read.All",
    "Directory.Read.All",
    "Policy.Read.All",
    "SharePointTenantSettings.Read.All",
    "Organization.Read.All",
    "Domain.Read.All"
)

$graphPermissionGuids = @()
foreach ($perm in $graphPermissions) {
    $guid = Get-GuidForPermission -ServicePrincipalId $MsGraphApi -PermissionName $perm
    if ([string]::IsNullOrEmpty($guid)) {
        Write-Error ("[ERRO] GUID para permissao '{0}' nao encontrado no Microsoft Graph." -f $perm)
        exit 1
    } else {
        Write-Host ("[OK] Permissao '{0}' (Microsoft Graph) -> GUID: {1}" -f $perm, $guid)
        $graphPermissionGuids += $guid
    }
}

$exchangeGuid = Get-GuidForPermission -ServicePrincipalId $ExchangeApi -PermissionName "Exchange.ManageAsApp"
if ([string]::IsNullOrEmpty($exchangeGuid)) {
    Write-Error "[ERRO] GUID para permissao 'Exchange.ManageAsApp' nao encontrado no Exchange Online."
    exit 1
} else {
    Write-Host ("[OK] Permissao 'Exchange.ManageAsApp' (Exchange Online) -> GUID: {0}" -f $exchangeGuid)
}

$teamsGuid = Get-GuidForPermission -ServicePrincipalId $TeamsApi -PermissionName "application_access"
if ([string]::IsNullOrEmpty($teamsGuid)) {
    Write-Error "[ERRO] GUID para permissao 'application_access' nao encontrado no Skype and Teams Tenant Admin API."
    exit 1
} else {
    Write-Host ("[OK] Permissao 'application_access' (Teams API) -> GUID: {0}" -f $teamsGuid)
}

Write-Host ""
Write-Host "[INFO] Adicionando permissoes a aplicacao..."

foreach ($guid in $graphPermissionGuids) {
    Write-Host ("[INFO] Adicionando permissao GUID {0} (Microsoft Graph)..." -f $guid)
    az ad app permission add --id $AppId --api $MsGraphApi --api-permissions "$guid=Role" | Out-Null
}

Write-Host ("[INFO] Adicionando permissao GUID {0} (Exchange Online)..." -f $exchangeGuid)
az ad app permission add --id $AppId --api $ExchangeApi --api-permissions "$exchangeGuid=Role" | Out-Null

Write-Host ("[INFO] Adicionando permissao GUID {0} (Teams API)..." -f $teamsGuid)
az ad app permission add --id $AppId --api $TeamsApi --api-permissions "$teamsGuid=Role" | Out-Null

Write-Host "[INFO] Tentando conceder consentimento administrativo para todas as permissoes..."
try {
    az ad app permission admin-consent --id $AppId | Out-Null
    Write-Host "[OK] Consentimento administrativo concedido com sucesso para todas as permissoes."
}
catch {
    Write-Warning "[AVISO] Consentimento administrativo NAO pode ser concedido automaticamente."
}

Write-Host ""
$EnvFile = "vulneri_cspm_m365_env.txt"
Write-Host ("[INFO] Salvando variaveis de ambiente em '{0}'..." -f $EnvFile)

# Conteudo no formato shell export para facil uso com source no Linux bash
@"
export AZURE_CLIENT_ID='$AppId'
export AZURE_CLIENT_SECRET='$SecretValue'
export AZURE_TENANT_ID='$TenantId'
"@ | Set-Content -Encoding UTF8 $EnvFile

Write-Host ""
Write-Host "### Conteudo do arquivo de variaveis de ambiente ###"
Get-Content $EnvFile | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "=============================================================="
Write-Host "Processo concluido!"

Write-Host ""
Write-Host "IMPORTANTE:"
Write-Host "O consentimento administrativo nao foi concedido automaticamente,"
Write-Host "conceda manualmente no portal do Entra ID:"
Write-Host "  https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationsListBlade"
Write-Host "Localize o app, va em Manage e 'Permissoes de API' ou 'API Permissions'"
Write-Host "e clique 'Conceder consentimento do administrador para <tenant>' ou 'Grant admin consent for <tenant>'."
Write-Host ""
Write-Host "Variaveis de ambiente criadas no arquivo vulneri_cspm_m365_env.txt"
Write-Host "=============================================================="
