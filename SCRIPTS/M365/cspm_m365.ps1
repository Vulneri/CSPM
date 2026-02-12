#!/usr/bin/env pwsh

# Permitir execução temporária de scripts nesta sessão
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# ----- CONFIGURACAO INICIAL -----
$ErrorActionPreference = "Stop"

$AppName       = "vulneri_azure_cspm_25"
$EnvFile       = "vulneri_cspm_azure_env.txt"
$GraphApiId    = "00000003-0000-0000-c000-000000000000"
$ExchangeApiId = "00000002-0000-0ff1-ce00-000000000000"

$GraphPermissions = @( 
    "7ab1d382-f21e-4acd-a863-ba3e13f7da61",  # Directory.Read.All
    "5d6b6bb7-de71-4623-b4af-96380a352509",  # Policy.Read.All
    "df021288-bdef-4463-88db-98f22de89214",  # UserAuthenticationMethod.Read.All
    "012133ce-4467-4f61-b44d-585ee912e95a",  # Reports.Read.All
    "350df2c0-82a9-4621-9311-53b019199d25",  # SecurityEvents.Read.All
    "b8964574-aaa4-4efd-ad07-062e078ea873",  # Billing.Read.All
    "204e0828-b5ca-4ad8-b9f3-f32a958e7cc4",  # Sites.Read.All (Inventory/FinOps)
    "e4c9e354-4dc5-45b8-9e7c-e139bb829e4e",  # AuditLog.Read.All (Purview)
    "83d4163d-a2d8-4d3b-9695-4ae3ca98f888",  # SharePointTenantSettings.Read.All
    "498476ce-e0fe-48b0-8017-37ba7e2685c6",  # Organization.Read.All
    "dbb9058a-0e50-45d7-ae91-66909b5d4664",  # Domain.Read.All
    "483bed4a-2ad3-4361-a73b-c83ccdbdc53c",  # RoleManagement.Read.Directory
    "37730810-e9ba-4e46-b07e-8ca78d182097",  # Policy.Read.ConditionalAccess
    "6e472fd1-ad78-48da-a0f0-97ab2c6b769e",  # IdentityRiskEvent.Read.All
    "f3796328-9177-4401-b687-d16ad56ed3e4"   # SubscribedSkus.Read.All
)

$ExchangePermissions = @(
    "dc50a0fb-09a3-484d-be87-e023b12c6440"   # Exchange.ManageAsApp
)

$O365ManagementApiId = "ff74b927-94b6-45bc-9171-47fed879668d"
$O365ManagementPermissions = @(
    "c5301311-66d4-4530-90fe-431835773177",  # ActivityFeed.Read
    "e1136b36-508b-49fc-9eac-62423e85934f",  # ActivityFeed.ReadDlp
    "656bb153-61ce-427c-9b16-52bb664c1206"   # ServiceHealth.Read
)

$AzureRoles     = @("Reader", "Security Reader", "Cost Management Reader", "Billing Reader")

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
            # Fallback para download direto se winget falhar
            Write-Host "[INFO] Winget nao disponivel. Baixando instalador MSI..."
            $msiPath = "$env:TEMP\AzureCLI.msi"
            Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile $msiPath
            Start-Process msiexec.exe -Wait -ArgumentList "/I $msiPath /quiet"
            Remove-Item $msiPath
            Write-Host "[OK] Azure CLI instalado. Reinicie o PowerShell." -ForegroundColor Green
            exit 0
        }
    } else {
        Write-Error "Azure CLI nao encontrada. Por favor instale manualmente no seu sistema Linux."
        exit 1
    }
}

function Verificar-AzureCLI {
    if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
        Install-AzCli
    } else {
        Write-Host "[INFO] Azure CLI encontrado."
    }
}

function Autenticar-Azure {
    Write-Host "[INFO] Conectando ao Microsoft Entra ID (via Azure CLI)..."
    try {
        az account show > $null 2>&1
    } catch {
        az login --allow-no-subscriptions | Out-Null
    }
    
    $subsJson = az account list --query "[].{name:name, id:id, tenantId:tenantId}" -o json
    $script:SUBSCRIPTIONS = $subsJson | ConvertFrom-Json
    
    # Corrige detecção: array vazio pode ser convertido para @() ou $null
    $subsCount = 0
    if ($null -ne $SUBSCRIPTIONS) {
        if ($SUBSCRIPTIONS -is [array]) {
            $subsCount = $SUBSCRIPTIONS.Count
        } elseif ($SUBSCRIPTIONS.PSObject.Properties.Count -gt 0) {
            $subsCount = 1
        }
    }
    
    if ($subsCount -eq 0) {
        # Em tenants puramente M365 (sem Azure Subscription), isso é normal.
        $accountInfo = az account show --query "{tenantId:tenantId}" -o json | ConvertFrom-Json
        $script:TENANT_ID = $accountInfo.tenantId
        $script:SUBSCRIPTIONS = @()  # Força array vazio
        Write-Host "[OK] Conectado ao Tenant M365-only: $TENANT_ID" -ForegroundColor Green
    } else {
        $script:TENANT_ID = $SUBSCRIPTIONS[0].tenantId
        Write-Host "[OK] Tenant hibrido identificado: $TENANT_ID ($subsCount subscription(s))" -ForegroundColor Green
    }
}

function Registrar-Aplicacao {
    $nomeApp = "$AppName_$(Get-Random -Maximum 9999)"
    Write-Host "[INFO] Registrando aplicacao '$nomeApp'..."

    $requiredResourceAccess = @()

    if ($GraphPermissions.Count -gt 0) {
        $requiredResourceAccess += @{
            resourceAppId  = "$GraphApiId"
            resourceAccess = @($GraphPermissions | ForEach-Object { @{ id = "$_"; type = "Role" } })
        }
    }

    if ($ExchangePermissions.Count -gt 0) {
        $requiredResourceAccess += @{
            resourceAppId  = "$ExchangeApiId"
            resourceAccess = @($ExchangePermissions | ForEach-Object { @{ id = "$_"; type = "Role" } })
        }
    }

    if ($O365ManagementPermissions.Count -gt 0) {
        $requiredResourceAccess += @{
            resourceAppId  = "$O365ManagementApiId"
            resourceAccess = @($O365ManagementPermissions | ForEach-Object { @{ id = "$_"; type = "Role" } })
        }
    }

    $jsonPath = [System.IO.Path]::GetTempFileName()
    $requiredResourceAccess | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $jsonPath

    $app = az ad app create `
        --display-name $nomeApp `
        --required-resource-accesses "@$jsonPath" `
        --output json | ConvertFrom-Json

    Remove-Item $jsonPath

    if (-not $app.appId) {
        Write-Host "[ERRO] Falha ao registrar a aplicação. Verifique se você tem permissões suficientes no Azure AD."
        exit 1
    }

    $script:APP_ID = $app.appId
    $script:APP_OBJECT_ID = $app.id
    Write-Host "[INFO] Aplicacao registrada com App ID: $APP_ID"
}

function Criar-ClientSecret {
    Write-Host "[INFO] Criando client secret..."
    $secret = az ad app credential reset --id $APP_ID --display-name "vulneri-secret" -o json | ConvertFrom-Json
    $script:CLIENT_SECRET = $secret.password
    Write-Host "[INFO] Client secret criado."
}

function Atribuir-Permissoes-Graph {
    Write-Host "[INFO] Aguardando consistencia do Azure (10s) antes do consentimento..."
    Start-Sleep -Seconds 10
    Write-Host "[INFO] Solicitando consentimento administrativo para Graph APIs..."
    try {
        & az ad app permission admin-consent --id $APP_ID --only-show-errors > $null 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Consentimento concedido automaticamente via CLI." -ForegroundColor Green
        } else {
            throw "Consentimento falhou"
        }
    } catch {
        Write-Warning "Consentimento automatico falhou. Sera necessario conceder manualmente ao final."
    }
}

function Criar-ServicePrincipal {
    Write-Host "[INFO] Criando service principal para a aplicacao..."
    $sp = az ad sp create --id $APP_ID -o json | ConvertFrom-Json
    $script:SP_OBJECT_ID = $sp.id
}

function Atribuir-Permissoes-RBAC {
    # Verifica de forma robusta se há subscriptions
    $hasSubscriptions = $false
    if ($null -ne $SUBSCRIPTIONS -and $SUBSCRIPTIONS.Count -gt 0) {
        $hasSubscriptions = $true
    }
    
    if (-not $hasSubscriptions) {
        Write-Host "[INFO] Tenant M365-only detectado (sem subscriptions Azure). Pulando atribuicao de roles Azure RBAC." -ForegroundColor Cyan
        Write-Host "[INFO] As permissoes Graph/Exchange/O365 Management sao suficientes para M365." -ForegroundColor Cyan
        return
    }
    
    Write-Host "[INFO] Tenant hibrido detectado ($($SUBSCRIPTIONS.Count) subscription(s) Azure encontrada(s))." -ForegroundColor Cyan
    Write-Host "[INFO] Atribuindo roles de seguranca e billing em TODAS as assinaturas..."
    
    foreach ($sub in $SUBSCRIPTIONS) {
        Write-Host "  -> Processando assinatura: $($sub.name) ($($sub.id))" -ForegroundColor Cyan
        foreach ($role in $AzureRoles) {
            try {
                az role assignment create `
                    --assignee-object-id $SP_OBJECT_ID `
                    --assignee-principal-type ServicePrincipal `
                    --role $role `
                    --scope "/subscriptions/$($sub.id)" | Out-Null
                Write-Host "     [OK] Role '$role' atribuida." -ForegroundColor Green
            } catch {
                Write-Warning "     [AVISO] Falha ao atribuir '$role'. Verifique privilegios de Owner/User Access Administrator."
            }
        }
    }
}

function Exportar-Credenciais {
    Write-Host "[INFO] Salvando variaveis de ambiente em '$EnvFile'..."
    $content = @"
export AZURE_CLIENT_ID='$APP_ID'
export AZURE_CLIENT_SECRET='$CLIENT_SECRET'
export AZURE_TENANT_ID='$TENANT_ID'
"@
    $content | Out-File -Encoding UTF8 $EnvFile
    
    Write-Host ""
    Write-Host "=============================================================" -ForegroundColor Yellow
    Write-Host "  ACAO MANUAL NECESSARIA - CONSENTIMENTO ADMINISTRATIVO" -ForegroundColor Yellow
    Write-Host "=============================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Para que os modulos Vulneri (CSPM/Inventory/FinOps) funcionem corretamente," -ForegroundColor White
    Write-Host "voce DEVE conceder consentimento administrativo para TODAS as permissoes:" -ForegroundColor White
    Write-Host ""
    Write-Host "1. Acesse o portal do Entra ID" -ForegroundColor Cyan
    Write-Host "2. Va em 'API Permissions' da aplicacao criada" -ForegroundColor Cyan
    Write-Host "3. Clique em 'Grant admin consent for <TenantName>'" -ForegroundColor Cyan
    Write-Host "4. Aguarde ate ver o icone verde de check em todas as permissoes" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Link direto para API Permissions:" -ForegroundColor White
    $consentUrl = "https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/CallAnAPI/appId/$APP_ID"
    Write-Host $consentUrl -ForegroundColor Green
    Write-Host ""
    Write-Host "=============================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "[OK] Credenciais salvas em: $EnvFile" -ForegroundColor Green
    Write-Host "[OK] Aplicacao ID: $APP_ID" -ForegroundColor Green
    
    # Tenta abrir o browser automaticamente
    Write-Host ""
    Write-Host "[INFO] Tentando abrir o navegador automaticamente..." -ForegroundColor Cyan
    try {
        Start-Process $consentUrl
        Write-Host "[OK] Navegador aberto. Por favor, conceda o consentimento." -ForegroundColor Green
    } catch {
        Write-Warning "Nao foi possivel abrir o navegador automaticamente. Por favor, copie o link acima manualmente."
    }
}

# Execucao sequencial das funcoes
Write-Host "=== Iniciando Setup do Vulneri para Microsoft 365 ==="

$isWin = ($env:OS -match "Windows") -or ($IsWindows)
if ($isWin -and -not (Test-Admin)) {
    Write-Warning "!!! ATENCAO: Corra este script como ADMINISTRADOR para evitar erros de permissao local !!!"
}

Verificar-AzureCLI
Autenticar-Azure
Registrar-Aplicacao
Criar-ClientSecret
Atribuir-Permissoes-Graph
Criar-ServicePrincipal
Atribuir-Permissoes-RBAC
Exportar-Credenciais
