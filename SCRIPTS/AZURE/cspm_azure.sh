#!/usr/bin/env bash

# -----------------------------------------------------------
# Script: cspm_azure.sh
# Objetivo: Automatiza o registro de uma aplicacao no Azure AD,
# gera client secret, atribui permissoes no Microsoft Graph
# e concede Reader na subscription.
# -----------------------------------------------------------
#
#
# $./cspm_azure.sh
# [INFO] Iniciando processo de criacao de aplicacao no Azure...
# [INFO] Instalando dependencias: azure-cli, jq...
# [INFO] Autenticando no Azure CLI...
# [INFO] Tenant autenticado: 7c143294-9172-41b3-82a5-ecf9768dbb29
# [INFO] Subscription ativa: Pago pelo Uso (4b4236db-8121-4695-bf57-41a852941748)
# [INFO] Registrando aplicacao 'vulneri_7'...
# [INFO] Aplicacao registrada com App ID: 43334812-d65f-4a84-8745-d8c2a6b37271
# [INFO] Criando client secret...
# WARNING: The output includes credentials that you must protect. Be sure that you do not include these credentials in your code or check the credentials into your source control. For more information, see https://aka.ms/azadsp-cli
# [INFO] Client secret criado.
# [INFO] Atribuindo permissoes Microsoft Graph...
# Invoking `az ad app permission grant --id 43334812-d65f-4a84-8745-d8c2a6b37271 --api 00000003-0000-0000-c000-000000000000` is needed to make the change effective
# Invoking `az ad app permission grant --id 43334812-d65f-4a84-8745-d8c2a6b37271 --api 00000003-0000-0000-c000-000000000000` is needed to make the change effective
# Invoking `az ad app permission grant --id 43334812-d65f-4a84-8745-d8c2a6b37271 --api 00000003-0000-0000-c000-000000000000` is needed to make the change effective
# [INFO] Consentindo permissoes no Microsoft Graph...
# [INFO] Permissoes aplicadas e consentidas.
# [INFO] Criando service principal para a aplicacao...
# [INFO] Atribuindo role 'Reader' na subscription '4b4236db-8121-4695-bf57-41a852941748'...
# {
#  "condition": null,
#  "conditionVersion": null,
#  "createdBy": null,
#  "createdOn": "2025-07-16T20:19:43.616697+00:00",
#  "delegatedManagedIdentityResourceId": null,
#  "description": null,
#  "id": "/subscriptions/4b4236db-8121-4695-bf57-41a852941748/providers/Microsoft.Authorization/roleAssignments/7a5c23ba-8d4e-4ae3-a7b3-3c87311a1a9b",
#  "name": "7a5c23ba-8d4e-4ae3-a7b3-3c87311a1a9b",
#  "principalId": "c5d1dd10-3919-41f5-af6a-5b8fc4338fc1",
#  "principalType": "ServicePrincipal",
#  "roleDefinitionId": "/subscriptions/4b4236db-8121-4695-bf57-41a852941748/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7",
#  "scope": "/subscriptions/4b4236db-8121-4695-bf57-41a852941748",
#  "type": "Microsoft.Authorization/roleAssignments",
#  "updatedBy": "242c64bb-d997-4ffd-b1ae-4fc67de582cb",
#  "updatedOn": "2025-07-16T20:19:44.243556+00:00"
# }
# [INFO] Permissao atribuida na subscription.
# [INFO] Credenciais salvas em: vulneri_7_azure_credentials.csv
# [INFO] Script concluido com sucesso.
# Credenciais geradas:
#Client ID,Client Secret,Tenant ID
#43334812-d65f-4a84-8745-d8c2a6b37271,PcY8Q~qTed9-lQut_gKn1XIzsnOA5m34EyjPObao,7c143294-9172-41b3-82a5-ecf9768dbb29
#
#Envie o arquivo vulneri_7_azure_credentials.csv para security@vulneri.io
##################################################################################################



set -euo pipefail

# ------------------ VARIAVEIS ------------------

APP_NAME="vulneri_cspm_25"
CSV_FILE="${APP_NAME}_azure_credentials.csv"
# GUIDs reais das permissoes Microsoft Graph (Application)
GRAPH_PERMISSIONS=(
  "7ab1d382-f21e-4acd-a863-ba3e13f7da61"  # Directory.Read.All
  "5d6b6bb7-de71-4623-b4af-96380a352509"  # Policy.Read.All
  "df021288-bdef-4463-88db-98f22de89214"  # UserAuthenticationMethod.Read.All
)
AZURE_ROLE="Reader"

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
    log "Instalando dependencias: azure-cli, jq..."
    sudo apt update -y
    sudo apt install -y jq curl apt-transport-https lsb-release gnupg

    if ! command -v az >/dev/null 2>&1; then
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
        log "Azure CLI instalada com sucesso."
    fi
}

autenticar_azure() {
    log "Autenticando no Azure CLI..."
    az account show >/dev/null 2>&1 || az login
}

verificar_subscription() {
    SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null || true)

    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        error_exit "Nao ha subscription ativa. Verifique se voce esta autenticado no tenant correto. Use: az login --tenant <TENANT_ID>"
    fi

    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    TENANT_ID=$(az account show --query tenantId -o tsv)

    log "Tenant autenticado: $TENANT_ID"
    log "Subscription ativa: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
}

registrar_aplicacao() {
    log "Registrando aplicacao '$APP_NAME'..."
    APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
    TENANT_ID=$(az account show --query tenantId -o tsv)
    OBJECT_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)

    # Torna a aplicacao multitenant
    az ad app update --id "$APP_ID" --set signInAudience="AzureADMultipleOrgs"

    log "Aplicacao registrada com App ID: $APP_ID"
}

criar_secret() {
    log "Criando client secret..."
    SECRET_VALUE=$(az ad app credential reset --id "$APP_ID" --append --display-name "Vulneri" --years 1 --query password -o tsv)
    log "Client secret criado."
}

atribuir_permissoes() {
    log "Atribuindo permissoes Microsoft Graph..."
    for perm in "${GRAPH_PERMISSIONS[@]}"; do
        az ad app permission add --id "$APP_ID" \
            --api 00000003-0000-0000-c000-000000000000 \
            --api-permissions "${perm}=Role"
    done

    # Consentimento administrativo (requer permissao do admin global)
    log "Consentindo permissoes no Microsoft Graph..."
    az ad app permission admin-consent --id "$APP_ID"
    log "Permissoes aplicadas e consentidas."
}

atribuir_role_subscription() {
    log "Criando service principal para a aplicacao..."
    az ad sp create --id "$APP_ID" >/dev/null

    for i in {1..12}; do
        SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || true)
        [[ -n "$SP_OBJECT_ID" ]] && break
        log "Aguardando propagacao do Service Principal... ($i/12)"
        sleep 5
    done

    if [[ -z "$SP_OBJECT_ID" ]]; then
        error_exit "Timeout ao tentar obter o objectId do Service Principal"
    fi

    log "Atribuindo role '$AZURE_ROLE' na subscription '$SUBSCRIPTION_ID'..."
    az role assignment create --assignee-object-id "$SP_OBJECT_ID" \
        --assignee-principal-type ServicePrincipal \
        --role "$AZURE_ROLE" \
        --scope "/subscriptions/$SUBSCRIPTION_ID"

    log "Permissao atribuida na subscription."
}

gerar_csv() {
    echo "Client ID,Client Secret,Tenant ID" > "$CSV_FILE"
    echo "$APP_ID,$SECRET_VALUE,$TENANT_ID" >> "$CSV_FILE"
    log "Credenciais salvas em: $CSV_FILE"
}

# ------------------ EXECUCAO ------------------

log "Iniciando processo de criacao de aplicacao no Azure..."

instalar_dependencias
autenticar_azure
verificar_subscription
registrar_aplicacao
criar_secret
atribuir_permissoes
atribuir_role_subscription
gerar_csv

log "Script concluido com sucesso."
echo "Credenciais geradas:"
cat "$CSV_FILE"
echo ""
echo "Envie o arquivo $CSV_FILE para security@vulneri.io"
