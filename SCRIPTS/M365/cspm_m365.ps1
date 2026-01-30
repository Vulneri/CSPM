#!/usr/bin/env pwsh

# Permitir execução temporária de scripts nesta sessão
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# ----- CONFIGURACAO INICIAL -----
$ErrorActionPreference = "Stop"

$AppName       = "vulneri_azure_cspm_25"
$EnvFile       = "vulneri_cspm_azure_env.txt"
$GraphApiId    = "00000003-0000-0000-c000-000000000000"
$GraphPermissions = @( 
    "7ab1d382-f21e-4acd-a863-ba3e13f7da61",  # Directory.Read.All
    "5d6b6bb7-de71-4623-b4af-96380a352509",  # Policy.Read.All
    "df021288-bdef-4463-88db-98f22de89214",  # UserAuthenticationMethod.Read.All (Legacy/Extra)
    "012133ce-4467-4f61-b44d-585ee912e95a",  # Reports.Read.All
    "350df2c0-82a9-4621-9311-53b019199d25",  # SecurityEvents.Read.All
    "b8964574-aaa4-4efd-ad07-062e078ea873"   # Billing.Read.All
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
    Write-Host "[INFO] Autenticando no Azure CLI..."
    try {
        az account show > $null 2>&1
    } catch {
        az login --allow-no-subscriptions | Out-Null
    }
    
    $script:SUBSCRIPTIONS = az account list --query "[].{name:name, id:id, tenantId:tenantId}" -o json | ConvertFrom-Json
    if ($SUBSCRIPTIONS.Count -eq 0) {
        Write-Host "[ERRO] Nenhuma subscription encontrada."; exit 1
    }
    
    # Pega o TenantId da primeira sub como referencia
    $script:TENANT_ID = $SUBSCRIPTIONS[0].tenantId
    Write-Host "[OK] Tenant identificado: $TENANT_ID"
    Write-Host "[OK] Total de assinaturas mapeadas: $($SUBSCRIPTIONS.Count)"
}

function Registrar-Aplicacao {
    $nomeApp = "$AppName_$(Get-Random -Maximum 9999)"
    Write-Host "[INFO] Registrando aplicacao '$nomeApp'..."

    $requiredResourceAccess = @(
        @{
            resourceAppId  = $GraphApiId
            resourceAccess = $GraphPermissions | ForEach-Object { @{ id = $_; type = "Role" } }
        }
    )

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
            Write-Host "[OK] Consentimento concedido via CLI." -ForegroundColor Green
        } else {
            throw "Consentimento falhou"
        }
    } catch {
        Write-Warning "Consentimento automatico falhou (comum por politicas do tenant ou delay sincronizacao)."
        $portalUrl = "https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/CallAnAPI/appId/$APP_ID/isRedirect~/true/isMSAApp~/false/showInServiceTree~/false"
        Write-Host "[ACAO NECESSARIA] Clique no link abaixo e clique em 'Conceder Consentimento' para finalizar:" -ForegroundColor Yellow
        Write-Host $portalUrl -ForegroundColor Cyan
        
        # Tenta abrir o browser automaticamente no Windows
        try { Start-Process $portalUrl } catch {}
    }
}

function Criar-ServicePrincipal {
    Write-Host "[INFO] Criando service principal para a aplicacao..."
    $sp = az ad sp create --id $APP_ID -o json | ConvertFrom-Json
    $script:SP_OBJECT_ID = $sp.id
}

function Atribuir-Permissoes-RBAC {
    Write-Host "[INFO] Atribuindo papeis de seguranca e billing em TODAS as assinaturas..."
    
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
    Write-Host "IMPORTANTE:"
    Write-Host "O consentimento administrativo pode nao ter sido concedido automaticamente."
    Write-Host "Caso necessario, conceda manualmente no portal do Entra ID:"
    Write-Host "  https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationsListBlade"
    Write-Host "Localize o app, va em 'API Permissions' e clique em 'Grant admin consent'."
    Write-Host ""
    Write-Host "[OK] Configuracao concluida! Credenciais salvas em: $EnvFile" -ForegroundColor Green
}

# Execucao sequencial das funcoes
Write-Host "=== Iniciando Azure CSPM/FinOps Setup Tools ==="

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
