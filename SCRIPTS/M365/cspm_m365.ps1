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

function Test-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-AzCli {
    $isWin = ($env:OS -match "Windows") -or ($IsWindows)
    if ($isWin) {
        Write-Host "[INFO] Azure CLI nao detectada. Tentando instalar via Winget..." -ForegroundColor Yellow
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install -e --id Microsoft.AzureCLI --accept-source-agreements --accept-package-agreements
            Write-Host "[OK] Instalacao iniciada. Por favor, REINICIE o PowerShell apos o termino para que o comando 'az' seja reconhecido." -ForegroundColor Green
            exit 0
        } else {
            Write-Error "Winget nao encontrado. Por favor, instale o Azure CLI manualmente em: https://aka.ms/installazurecliwindows"
            exit 1
        }
    } else {
        Write-Error "Azure CLI nao encontrada. Por favor instale manualmente no seu sistema Linux."
        exit 1
    }
}

function Check-AzCli {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Install-AzCli
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

function Check-M365Licensing {
    Write-Host "[INFO] Verificando licenciamento do tenant (SKUs)..."
    try {
        $skus = az rest --method get --url https://graph.microsoft.com/v1.0/subscribedSkus | ConvertFrom-Json
        $foundSecurityLicents = $false
        
        Write-Host "### Licencas Encontradas ###"
        foreach ($sku in $skus.value) {
            $skuName = $sku.skuPartNumber
            Write-Host ("  - {0} (Total: {1}, Consumido: {2})" -f $skuName, $sku.prepaidUnits.enabled, $sku.consumedUnits)
            
            if ($skuName -match "AAD_PREMIUM|SPE_E3|SPE_E5|ENTERPRISEPREMIUM|AAD_PREMIUM_V2") {
                $foundSecurityLicents = $true
            }
        }
        
        if (-not $foundSecurityLicents) {
            Write-Warning "[AVISO] Nenhuma licenca de seguranca avancada (P1/P2/E3/E5) detectada explicitamente."
            Write-Warning "        Algumas auditorias (Conditional Access, Identity Protection) podem falhar ou retornar vazio."
        } else {
            Write-Host "[OK] Licencas de seguranca detectadas. Auditoria avancada liberada."
        }
    }
    catch {
        Write-Warning "[AVISO] Nao foi possivel verificar os SKUs. Continuando sem validacao de licenca."
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

$isWin = ($env:OS -match "Windows") -or ($IsWindows)
if ($isWin -and -not (Test-Admin)) {
    Write-Warning "!!! ATENCAO: O script nao esta rodando como Administrador !!!"
    Write-Warning "Isso pode causar falhas ao tentar atribuir o papel de Global Reader ou instalar o Azure CLI."
    Write-Host "Recomendamos fechar e abrir o PowerShell como Administrador."
    Write-Host ""
}

Check-AzCli
Start-AzLogin
Check-M365Licensing

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
    "Domain.Read.All",
    "SecurityEvents.Read.All",
    "RoleManagement.Read.Directory",
    "Policy.Read.ConditionalAccess",
    "IdentityRiskEvent.Read.All",
    "Reports.Read.All",
    "Billing.Read.All",
    "SubscribedSkus.Read.All"
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

# --- OFFICE 365 MANAGEMENT APIS ---
$O365MgmtApi = "ff74b927-94b6-45bc-9171-47fed879668d"
Write-Host "[INFO] Resolvendo GUIDs para Office 365 Management API..."
$o365Permissions = @("ActivityFeed.Read", "ActivityFeed.ReadDlp", "ServiceHealth.Read")
$o365PermissionGuids = @()

foreach ($perm in $o365Permissions) {
    $guid = Get-GuidForPermission -ServicePrincipalId $O365MgmtApi -PermissionName $perm
    if ([string]::IsNullOrEmpty($guid)) {
        Write-Warning ("[AVISO] GUID para permissao '{0}' nao encontrado no O365 Management API." -f $perm)
    } else {
        Write-Host ("[OK] Permissao '{0}' (O365 Mgmt) -> GUID: {1}" -f $perm, $guid)
        $o365PermissionGuids += $guid
    }
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

foreach ($guid in $o365PermissionGuids) {
    Write-Host ("[INFO] Adicionando permissao GUID {0} (O365 Management API)..." -f $guid)
    az ad app permission add --id $AppId --api $O365MgmtApi --api-permissions "$guid=Role" | Out-Null
}

Write-Host "[INFO] Tentando conceder consentimento administrativo para todas as permissoes..."
try {
    az ad app permission admin-consent --id $AppId | Out-Null
    Write-Host "[OK] Consentimento administrativo concedido com sucesso para todas as permissoes."
}
catch {
    Write-Warning "[AVISO] Consentimento administrativo NAO pode ser concedido automaticamente."
}

Write-Host "[INFO] Configurando RBAC: Atribuindo papel de 'Global Reader' a aplicacao..."
try {
    # Garante que o Service Principal existe antes da atribuicao
    az ad sp create --id $AppId | Out-Null
    $spObjectId = (az ad sp show --id $AppId | ConvertFrom-Json).id
    az role assignment create --assignee $spObjectId --role "Global Reader" --scope "/" | Out-Null
    az role assignment create --assignee $spObjectId --role "Billing Reader" --scope "/" | Out-Null
    Write-Host "[OK] Papeis 'Global Reader' e 'Billing Reader' atribuidos com sucesso."
}
catch {
    Write-Warning "[AVISO] Falha ao atribuir papeis de Admin. Verifique se voce tem privilegios de Admin."
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
