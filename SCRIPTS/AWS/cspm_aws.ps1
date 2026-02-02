# ==============================================================================
# ASSISTENTE DE CONFIGURACAO VULNERI (CSPM/FINOPS) - WINDOWS
# Versao: 4.4 - Super Clean (Sem Emojis / Sem Simbolos Especiais)
# ==============================================================================

# Cores e Estilos simples
function Write-VLog ($m) { Write-Host "[VULNERI] $m" -ForegroundColor Green }
function Write-VErr ($m) { Write-Host "[ERRO] $m" -ForegroundColor Red }
function Write-VWarn ($m) { Write-Host "[AVISO] $m" -ForegroundColor Yellow }
function Write-VStep ($m) { Write-Host "" ; Write-Host "--- $m ---" -ForegroundColor Cyan }

Clear-Host
Write-Host "==========================================================" -ForegroundColor Blue
Write-Host "        ASSISTENTE DE CONFIGURACAO VULNERI (AWS)          " -ForegroundColor Blue
Write-Host "==========================================================" -ForegroundColor Blue
Write-Host "Conectando sua AWS a Vulneri."
Write-Host ""

# --- VERIFICACAO DE ADMINISTRADOR ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-VWarn "ACESSO NEGADO: Por favor, abra o PowerShell como ADMINISTRADOR."
    Read-Host "Pressione [ENTER] para sair"
    exit
}

# --- ETAPA 0: AWS CLI ---
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-VLog "AWS CLI nao encontrado. Instalando via Winget..."
    winget install --id Amazon.AWSCLI --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) {
        Write-VLog "Instalado com sucesso!"
        Write-Host "IMPORTANTE: Abra um NOVO terminal para o comando 'aws' funcionar." -ForegroundColor Cyan
        Read-Host "Pressione [ENTER] para sair"
        exit
    } else {
        Write-VErr "Falha na instalacao. Baixe em: https://aws.amazon.com/cli/"
        Read-Host "Pressione [ENTER] para sair"
        exit
    }
}

# --- ETAPA 0.5: PERFIL ---
$configPath = "$Home\.aws\config"
$skip = $false

if (Test-Path $configPath) {
    $content = Get-Content $configPath -Raw
    if ($content -like "*profile Vulneri_Setup*") {
        Write-Host "Configuracao 'Vulneri_Setup' encontrada." -ForegroundColor Yellow
        Write-Host "1. Reutilizar configuracoes e logar"
        Write-Host "2. Apagar e configurar do zero"
        Write-Host "3. Sair"
        $c = Read-Host "Escolha [1-3]"
        if ($c -eq "1") { $skip = $true }
        elseif ($c -eq "2") { 
            Write-VLog "Limpando perfil antigo..."
            $new = $content -replace "(?ms)\[profile Vulneri_Setup\].*?output\s*=\s*json(\s*)", ""
            Set-Content $configPath $new
        } else { exit }
    }
}

# --- ETAPA 1: COLETA ---
if (-not $skip) {
    Write-VStep "ETAPA 1.1: Localizando o Portal de Acesso"
    Write-Host "Dica: Geralmente comeca com 'https://d-' (Ex: https://d-90679...). "
    Write-Host "Fica em: AWS access portal URLs -> Default IPv4 only."
    Read-Host "Pressione [ENTER] para abrir o navegador..."
    Start-Process "https://console.aws.amazon.com/singlesignon/home#/dashboard"
    $url = Read-Host "Cole o link do portal aqui"
    if (-not $url) { Write-VErr "Link obrigatorio."; exit }

    Write-VStep "ETAPA 1.2: Localizando a Regiao"
    Read-Host "Pressione [ENTER] para ver a regiao em Settings..."
    Start-Process "https://console.aws.amazon.com/singlesignon/home#/settings"
    Write-Host "Va em 'Settings' -> 'Details' e procure por 'Region'."
    $reg = Read-Host "Digite a Regiao (Ex: us-east-1) [ENTER para us-east-1]"
    if (-not $reg) { $reg = "us-east-1" }

    Write-VStep "ETAPA 1.3a: Localizando ID da Conta"
    Write-Host "No topo direito, abaixo do seu usuario: Account ID XXXX-XXXX-XXXX."
    Read-Host "Pressione [ENTER] quando tiver o ID de 12 digitos..."
    $acc = Read-Host "Digite o ID da conta (apenas numeros)"
    if (-not $acc) { Write-VErr "ID obrigatorio."; exit }

    Write-VStep "ETAPA 1.3b: Identificando a Role SSO"
    Write-Host "Siga no Identity Center:"
    Write-Host "1. Multi-account permissions"
    Write-Host "2. AWS accounts"
    Write-Host "3. Clique na sua conta"
    Write-Host "4. Clique na aba 'Permission set'"
    Write-Host "5. Copie o nome (Ex: AdministratorAccess)"
    Read-Host "Pressione [ENTER] para abrir a lista de contas..."
    Start-Process "https://console.aws.amazon.com/singlesignon/home#/aws-accounts"
    $rol = Read-Host "Digite o nome da Permission Set / Role"
    if (-not $rol) { Write-VErr "Role obrigatoria."; exit }

    Write-VLog "Salvando configuracoes..."
    if (-not (Test-Path "$Home\.aws")) { New-Item -ItemType Directory -Path "$Home\.aws" | Out-Null }
    
    $p = ""
    $p += "`r`n[profile Vulneri_Setup]"
    $p += "`r`nsso_start_url = $url"
    $p += "`r`nsso_region = $reg"
    $p += "`r`nsso_account_id = $acc"
    $p += "`r`nsso_role_name = $rol"
    $p += "`r`nregion = $reg"
    $p += "`r`noutput = json"
    
    Add-Content $configPath $p
}

# --- ETAPA 1.5: LOGIN ---
Write-Host ""
Write-Host "[ACAO NO NAVEGADOR]" -ForegroundColor Yellow
Write-Host "Sera aberta uma aba. Clique em 'Allow access'."
Read-Host "Pressione [ENTER] para logar"

aws sso login --profile Vulneri_Setup
if ($LASTEXITCODE -ne 0) { Write-VErr "Falha no login."; exit }

$env:AWS_PROFILE = "Vulneri_Setup"
Write-VLog "Conectado com sucesso!"

# --- ETAPA 2: CONFIGURACAO ---
$u = "Vulneri-RO-Key"
if (-not (aws iam get-user --user-name $u 2>$null)) {
    aws iam create-user --user-name $u | Out-Null
    Write-VLog "Usuario tecnico criado."
}

$pn = "Vulneri-CSPM-FinOps-Policy"
$pa = aws iam list-policies --scope Local --query "Policies[?PolicyName=='$pn'].Arn" --output text 2>$null

if ($pa -eq "None" -or -not $pa) {
    Write-VLog "Criando política..."
    $j = @'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowInventory",
      "Effect": "Allow",
      "Action": [
        "account:Get*", "ce:Get*", "ec2:Describe*", "rds:Describe*", "s3:ListAllMyBuckets", 
        "iam:Get*", "iam:List*", "organizations:Describe*", "bedrock:List*", "backup:List*",
        "apigateway:GET", "ce:Describe*", "ce:List*", "cur:Describe*", "budgets:ViewBudget"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenySensitive",
      "Effect": "Deny",
      "Action": ["s3:GetObject", "secretsmanager:GetSecretValue", "kms:Decrypt"],
      "Resource": "*"
    }
  ]
}
'@
    $j | Set-Content "v-pol.json" -Encoding UTF8
    $pa = aws iam create-policy --policy-name $pn --policy-document file://v-pol.json --query 'Policy.Arn' --output text
    Remove-Item "v-pol.json"
}

aws iam attach-user-policy --user-name $u --policy-arn "arn:aws:iam::aws:policy/ReadOnlyAccess"
aws iam attach-user-policy --user-name $u --policy-arn "arn:aws:iam::aws:policy/SecurityAudit"
aws iam attach-user-policy --user-name $u --policy-arn $pa
Write-VLog "Permissoes configuradas."

# --- ETAPA 3: CHAVES ---
Write-VLog "Gerando chaves tecnicas..."
$kRaw = aws iam create-access-key --user-name $u --output json
$k = $kRaw | ConvertFrom-Json
$ak = $k.AccessKey.AccessKeyId
$sk = $k.AccessKey.SecretAccessKey

$res = "AWS_ACCESS_KEY_ID=$ak`r`nAWS_SECRET_ACCESS_KEY=$sk`r`nAWS_REGION=$reg"
$res | Set-Content "vulneri_credentials.env" -Encoding UTF8

Write-Host ""
Write-Host "VERIFICACAO FINAL:" -ForegroundColor Green
aws sts get-caller-identity | Out-Null
if ($LASTEXITCODE -eq 0) { Write-VLog "Validado!" }

Write-Host ""
Write-Host "CONCLUIDO COM SUCESSO!" -ForegroundColor Blue
Write-Host "Arquivo: vulneri_credentials.env"
Write-Host ""

Remove-Item env:AWS_PROFILE
Read-Host "Pressione [ENTER] para sair"
