#!/usr/bin/env pwsh

# -----------------------------------------------------------
# Script: access_azure.ps1
# Objetivo: Automatiza o registro de uma aplicação no Azure AD,
# gera client secret, atribui permissões no Microsoft Graph
# e concede permissão de Reader na subscription.
# -----------------------------------------------------------
#
# OUTPUT
# PS C:\Users\user> Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
# PS C:\Users\user> .\access_azure.ps1
# [INFO] Azure CLI encontrado.
# [INFO] Autenticando no Azure CLI...
# WARNING: Select the account you want to log in with. For more information on login with Azure CLI, see https://go.microsoft.com/fwlink/?linkid=2271136
# [INFO] Tenant autenticado: 7i74yfgf-7493-7294-8372-93ukdo7rhrf48
# [INFO] Subscription ativa: Pago pelo Uso (ugfikei3-3423-4242-bf94-84jfkdh6349)
# [INFO] Registrando aplicacao '3636'...
# [INFO] Aplicacao registrada com App ID: 84ydn572-836h-8jd6-830d-8305629jud73
# [INFO] Criando client secret...
# WARNING: The output includes credentials that you must protect. Be sure that you do not include these credentials in your code or check the credentials into your source control. For more information, see https://aka.ms/azadsp-cli
# [INFO] Client secret criado.
# [INFO] Criando service principal para a aplicacao...
# [INFO] Atribuindo role 'Reader' na subscription '4b4236db-8121-4695-bf57-41a852941748'...
# [INFO] Permissao atribuida.
# [INFO] Exportando credenciais para C:\Users\ldeso\Downloads/vulneri_powershell_XX_azure_credentials.csv...
# [INFO] Conteudo do CSV:
# client_id,client_secret,tenant_id,subscription_id
# 284ydn572-836h-8jd6-830d-8305629jud73,X8D7W~fKdJQtyiDNfJwg_uLhuWZItqctul8D4afo,7i74yfgf-7493-7294-8372-93ukdo7rhrf48,ugfikei3-3423-4242-bf94-84jfkdh6349
#
#
###################################################################


# Permitir execução temporária de scripts nesta sessão
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# ----- CONFIGURACAO INICIAL -----
$ErrorActionPreference = "Stop"

$AppName       = "vulneri_pshell_cspm_25"
$CsvPath       = "$PWD/${AppName}_azure_credentials.csv"
$GraphApiId    = "00000003-0000-0000-c000-000000000000"
$GraphPermissions = @( 
    "7ab1d382-f21e-4acd-a863-ba3e13f7da61",  # Directory.Read.All
    "5d6b6bb7-de71-4623-b4af-96380a352509",  # Policy.Read.All
    "df021288-bdef-4463-88db-98f22de89214"   # UserAuthenticationMethod.Read.All
)
$AzureRole     = "Reader"

# Instalar Azure CLI automaticamente, se não estiver presente
if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    Write-Host "[INFO] Azure CLI não encontrado. Iniciando instalação..."
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
    Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
    Remove-Item .\AzureCLI.msi
    Write-Host "[INFO] Azure CLI instalado. Reinicie o PowerShell e execute novamente o script."
    exit 0
}

function Verificar-AzureCLI {
    if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
        Write-Host "[ERRO] Azure CLI nao encontrado. Instale o Azure CLI antes de continuar."
        Write-Host "[LINK] https://learn.microsoft.com/cli/azure/install-azure-cli"
        exit 1
    } else {
        Write-Host "[INFO] Azure CLI encontrado."
    }
}

function Autenticar-Azure {
    Write-Host "[INFO] Autenticando no Azure CLI..."
    az login | Out-Null
    $subs = az account list --query "[?isDefault].{name:name, id:id, tenantId:tenantId}" -o json | ConvertFrom-Json
    if ($subs.Count -eq 0) {
        Write-Host "[ERRO] Nenhuma subscription encontrada."; exit 1
    }
    $sub = $subs[0]
    $script:SUBSCRIPTION_ID = $sub.id
    $script:TENANT_ID = $sub.tenantId
    Write-Host "[INFO] Tenant autenticado: $TENANT_ID"
    Write-Host "[INFO] Subscription ativa: $($sub.name) ($SUBSCRIPTION_ID)"
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

function Criar-ServicePrincipal {
    Write-Host "[INFO] Criando service principal para a aplicacao..."
    $sp = az ad sp create --id $APP_ID -o json | ConvertFrom-Json
    $script:SP_OBJECT_ID = $sp.id
}

function Atribuir-Permissao {
    Write-Host "[INFO] Atribuindo role '$AzureRole' na subscription '$SUBSCRIPTION_ID'..."
    az role assignment create `
        --assignee-object-id $SP_OBJECT_ID `
        --assignee-principal-type ServicePrincipal `
        --role $AzureRole `
        --scope "/subscriptions/$SUBSCRIPTION_ID" | Out-Null
    Write-Host "[INFO] Permissao atribuida."
}

function Exportar-Credenciais {
    Write-Host "[INFO] Exportando credenciais para $CsvPath..."
    "client_id,client_secret,tenant_id,subscription_id" | Out-File -Encoding UTF8 $CsvPath
    "$APP_ID,$CLIENT_SECRET,$TENANT_ID,$SUBSCRIPTION_ID" | Out-File -Append -Encoding UTF8 $CsvPath
    Write-Host "[INFO] Conteudo do CSV:"
    Get-Content $CsvPath
}

# Execucao sequencial das funcoes
Verificar-AzureCLI
Autenticar-Azure
Registrar-Aplicacao
Criar-ClientSecret
Criar-ServicePrincipal
Atribuir-Permissao
Exportar-Credenciais
