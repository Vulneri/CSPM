#!/usr/bin/env bash

# -----------------------------------------------------------
# Script: criar-usuario-vulneri.sh
# Objetivo: Instala dependencias, verifica perfil SSO,
# cria usuario IAM, gera access key e aplica politicas.
# Dependencias:
# 1 - Configurar perfil AWSCLI - /usr/local/bin/aws configure sso --profile Vulneri
# SSO session name (Recommended): Vulneri
# SSO start URL [None]: https://d-9XXXXX6XX.awsapps.com/start
# SSO region [None]: us-east-1
# SSO registration scopes [sso:account:access]: sso:account:access
# Attempting to automatically open the SSO authorization page in your default browser.
# If the browser does not open or you wish to use a different device to authorize this request, open the following URL:
 
# https://oidc.us-east-1.amazonaws.com/authorize?response_type=code&client_id=XXXXXXXXXXXXXXXXXXXXX...........
# Gtk-Message: 15:31:14.239: Not loading module "atk-bridge": The functionality is provided by GTK natively. Please try to not load it.
# Using the account ID 3XXXXXXX6542
# The only role available to you is: AdministratorAccess
# Using the role name "AdministratorAccess"
# Default client Region [None]:
# CLI default output format (json if not specified) [None]:
# To use this profile, specify the profile name using --profile, as shown:

# 2 - Testar - aws sts get-caller-identity --profile Vulneri
# aws sts get-caller-identity --profile Vulneri
# {
#    "UserId": "XXXXXXXXXXXXXXXXXXXXXX:email@vulneri.io",
#    "Account": "3XXXXXXX6542",
#    "Arn": "arn:aws:sts::3XXXXXXX6542:assumed-role/AWSReservedSSO_AdministratorAccess_234456678234fer7/email@vulneri.io"
# }

# 3 - Fazer login AWSCLI - /usr/local/bin/aws sso login --profile Vulneri
# Attempting to automatically open the SSO authorization page in your default browser.
# If the browser does not open or you wish to use a different device to authorize this request, open the following URL:

# https://oidc.us-east-1.amazonaws.com/authorize?response_type=code&client_id=XXXXXXXXXXXXXXXXXXXXX...........
# Gtk-Message: 15:32:16.824: Not loading module "atk-bridge": The functionality is provided by GTK natively. Please try to not load it.
# Successfully logged into Start URL: https://d-9XXXXX6XX.awsapps.com/start



# 4 - Rodar o script para criar usuario e atribuir as permissoes - bash criar-usuario-vulneri.sh
# [INFO] Iniciando criacao de usuario IAM com perfil 'Vulneri'...
# [INFO] Instalando dependencias: curl, unzip, jq, python3...
# [INFO] Verificando existencia do perfil 'Vulneri' no ~/.aws/config...
# [INFO] Verificando autenticacao com perfil 'Vulneri'...
# [INFO] Autenticacao bem-sucedida.
# [INFO] Criando usuario IAM 'ReadOnly-Key-To-Vulneri'...
# {
#    "User": {
#        "Path": "/",
#        "UserName": "ReadOnly-Key-To-Vulneri",
#        "UserId": "XXXXXXXXXXXXXXXXXXXXX",
#        "Arn": "arn:aws:iam::3XXXXXXX6542:user/ReadOnly-Key-To-Vulneri",
#        "CreateDate": "2025-07-15T18:36:01+00:00"
#    }
# }
# [INFO] Usuario criado com sucesso.
# [INFO] Verificando numero de access keys...
# [INFO] Criando nova access key...
# [INFO] Access key salva no arquivo: ReadOnly-Key-To-Vulneri_accessKeys.csv
# [INFO] Anexando politica 'ReadOnlyAccess' ao usuario 'ReadOnly-Key-To-Vulneri'...
# [INFO] Anexando politica 'SecurityAudit' ao usuario 'ReadOnly-Key-To-Vulneri'...
# [INFO] Todas as politicas foram atribuidas com sucesso.
# [INFO] Script finalizado com sucesso.
# Envie o arquivo ReadOnly-Key-To-Vulneri_accessKeys.csv para security@vulneri.io




# -----------------------------------------------------------

set -euo pipefail

# ------------------ VARIAVEIS ------------------

AWS_PROFILE="Vulneri"
AWS="/usr/local/bin/aws"
AWS_CMD="$AWS --profile $AWS_PROFILE"
IAM_USERNAME="ReadOnly-Key-To-Vulneri"
CREDENTIALS_FILE="${IAM_USERNAME}_accessKeys.csv"
POLICIES=("ReadOnlyAccess" "SecurityAudit")

# ------------------ FUNCOES ------------------

log() {
    echo -e "[INFO] $1"
}

warn() {
    echo -e "[ATENCAO] $1"
}

error_exit() {
    echo -e "[ERRO] $1"
    exit 1
}

instalar_dependencias() {
    log "Instalando dependencias: curl, unzip, jq, python3..."

    sudo apt update -y
    sudo apt install -y curl unzip jq python3 python3-pip python3-venv

    if [ ! -f "$AWS" ]; then
        log "Instalando AWS CLI v2 via curl..."
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
        rm -rf aws awscliv2.zip
        log "AWS CLI instalada em $AWS"
    fi
}

verificar_perfil_sso() {
    log "Verificando existencia do perfil '$AWS_PROFILE' no ~/.aws/config..."

    if ! grep -q "\[profile $AWS_PROFILE\]" ~/.aws/config 2>/dev/null; then
        error_exit "Perfil '$AWS_PROFILE' nao encontrado. Configure-o com:
$AWS configure sso --profile $AWS_PROFILE"
    fi
}

verificar_autenticacao() {
    log "Verificando autenticacao com perfil '$AWS_PROFILE'..."
    if ! $AWS_CMD sts get-caller-identity >/dev/null 2>&1; then
        error_exit "Falha de autenticacao. Execute:
$AWS sso login --profile $AWS_PROFILE"
    fi
    log "Autenticacao bem-sucedida."
}

criar_usuario_iam() {
    log "Criando usuario IAM '$IAM_USERNAME'..."
    if $AWS_CMD iam get-user --user-name "$IAM_USERNAME" &>/dev/null; then
        warn "Usuario ja existe. Pulando criacao."
    else
        $AWS_CMD iam create-user --user-name "$IAM_USERNAME"
        log "Usuario criado com sucesso."
    fi
}

criar_access_key() {
    log "Verificando numero de access keys..."
    EXISTING_KEYS=$($AWS_CMD iam list-access-keys --user-name "$IAM_USERNAME"         --query 'AccessKeyMetadata' --output json)

    TOTAL_KEYS=$(echo "$EXISTING_KEYS" | jq '. | length')

    if (( TOTAL_KEYS >= 2 )); then
        error_exit "Usuario ja possui 2 access keys. Apague uma manualmente antes de continuar."
    fi

    log "Criando nova access key..."
    ACCESS_KEY_JSON=$($AWS_CMD iam create-access-key --user-name "$IAM_USERNAME")

    ACCESS_KEY_ID=$(echo "$ACCESS_KEY_JSON" | jq -r '.AccessKey.AccessKeyId')
    SECRET_ACCESS_KEY=$(echo "$ACCESS_KEY_JSON" | jq -r '.AccessKey.SecretAccessKey')

    echo "Access Key ID,Secret Access Key" > "$CREDENTIALS_FILE"
    echo "$ACCESS_KEY_ID,$SECRET_ACCESS_KEY" >> "$CREDENTIALS_FILE"

    log "Access key salva no arquivo: $CREDENTIALS_FILE"
}

atribuir_politicas() {
    for policy in "${POLICIES[@]}"; do
        log "Anexando politica '$policy' ao usuario '$IAM_USERNAME'..."
        $AWS_CMD iam attach-user-policy             --user-name "$IAM_USERNAME"             --policy-arn "arn:aws:iam::aws:policy/$policy"
    done
    log "Todas as politicas foram atribuidas com sucesso."
}

# ------------------ EXECUCAO ------------------

log "Iniciando criacao de usuario IAM com perfil '$AWS_PROFILE'..."

instalar_dependencias
verificar_perfil_sso
verificar_autenticacao
criar_usuario_iam
criar_access_key
atribuir_politicas

log "Script finalizado com sucesso."
echo "Credenciais geradas:"
cat "$CREDENTIALS_FILE"
echo ""
echo "Envie o arquivo $CREDENTIALS_FILE para security@vulneri.io"
