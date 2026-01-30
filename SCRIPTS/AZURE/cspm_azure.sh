#!/usr/bin/env bash

set -euo pipefail

# ------------------ VARIAVEIS ------------------

TIMESTAMP=$(date +%s)
APP_NAME="vulneri_azure_cspm_$TIMESTAMP"
ENV_FILE="vulneri_cspm_azure_env.txt"

# GUIDs das permissoes Microsoft Graph
GRAPH_PERMISSIONS=(
  "7ab1d382-f21e-4acd-a863-ba3e13f7da61"  # Directory.Read.All
  "5d6b6bb7-de71-4623-b4af-96380a352509"  # Policy.Read.All
  "012133ce-4467-4f61-b44d-585ee912e95a"  # Reports.Read.All
  "350df2c0-82a9-4621-9311-53b019199d25"  # SecurityEvents.Read.All
  "b8964574-aaa4-4efd-ad07-062e078ea873"  # Billing.Read.All
)

AZURE_ROLES=("Reader" "Security Reader" "Cost Management Reader" "Billing Reader")

# ------------------ CORES ------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO] $1${NC}"; }
warn() { echo -e "${YELLOW}[AVISO] $1${NC}"; }
error_exit() { echo -e "${RED}[ERRO] $1${NC}"; exit 1; }

instalar_dependencias() {
    if ! command -v az &> /dev/null; then
        log "Azure CLI nao encontrada. Instalando..."
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    fi
    if ! command -v jq &> /dev/null; then
        log "jq nao encontrado. Instalando..."
        sudo apt update && sudo apt install -y jq
    fi
}

autenticar_azure() {
    log "Autenticando no Azure CLI..."
    az account show >/dev/null 2>&1 || az login --allow-no-subscriptions
}

mapear_assinaturas() {
    log "Mapeando assinaturas disponiveis..."
    SUBS_JSON=$(az account list --query "[].{name:name, id:id, tenantId:tenantId}" -o json)
    NUM_SUBS=$(echo "$SUBS_JSON" | jq '. | length')
    
    if [ "$NUM_SUBS" -eq 0 ]; then
        error_exit "Nenhuma assinatura encontrada."
    fi

    TENANT_ID=$(echo "$SUBS_JSON" | jq -r '.[0].tenantId')
    log "Tenant: $TENANT_ID | Assinaturas encontradas: $NUM_SUBS"
}

registrar_aplicacao() {
    log "Registrando aplicacao '$APP_NAME'..."
    APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
    OBJECT_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)
    log "App ID: $APP_ID"
}

criar_secret() {
    log "Criando client secret..."
    SECRET_VALUE=$(az ad app credential reset --id "$APP_ID" --append --display-name "VulneriSecret" --query password -o tsv)
}

set_graph_permissions() {
    log "Atribuindo permissoes Microsoft Graph..."
    for perm in "${GRAPH_PERMISSIONS[@]}"; do
        az ad app permission add --id "$APP_ID" \
            --api 00000003-0000-0000-c000-000000000000 \
            --api-permissions "${perm}=Role" > /dev/null
    done
    log "Aguardando consistência do Azure (10s) antes do consentimento..."
    sleep 10
    az ad app permission admin-consent --id "$APP_ID" || {
        warn "Consentimento automatico falhou por politicas do tenant."
        portal_url="https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/CallAnAPI/appId/$APP_ID/isRedirect~/true/isMSAApp~/false/showInServiceTree~/false"
        echo -e "${YELLOW}[ACAO NECESSARIA] Clique no link abaixo e clique em 'Conceder Consentimento' para finalizar:${NC}"
        echo -e "${GREEN}$portal_url${NC}"
        
        # Tenta abrir o navegador automaticamente
        if command -v xdg-open &> /dev/null; then
            xdg-open "$portal_url" > /dev/null 2>&1 &
        elif command -v gio &> /dev/null; then
            gio open "$portal_url" > /dev/null 2>&1 &
        fi
    }
}

set_rbac_permissions() {
    log "Criando Service Principal..."
    az ad sp create --id "$APP_ID" >/dev/null 2>&1 || true
    
    SP_OBJECT_ID=""
    for i in {1..6}; do
        SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || echo "")
        [ -n "$SP_OBJECT_ID" ] && break
        log "Aguardando propagacao... ($i/6)"
        sleep 5
    done

    if [ -z "$SP_OBJECT_ID" ]; then error_exit "Falha ao obter Object ID do SP."; fi

    # Itera sobre todas as assinaturas
    while read -r sub_id sub_name; do
        log "Processando assinatura: $sub_name ($sub_id)"
        for role in "${AZURE_ROLES[@]}"; do
            az role assignment create --assignee-object-id "$SP_OBJECT_ID" \
                --assignee-principal-type ServicePrincipal \
                --role "$role" \
                --scope "/subscriptions/$sub_id" >/dev/null 2>&1 && log "  [OK] $role" || warn "  [FALHA] $role"
        done
    done < <(echo "$SUBS_JSON" | jq -r '.[] | "\(.id) \(.name)"')
}

gerar_output() {
    cat <<EOF > "$ENV_FILE"
export AZURE_CLIENT_ID='$APP_ID'
export AZURE_CLIENT_SECRET='$SECRET_VALUE'
export AZURE_TENANT_ID='$TENANT_ID'
EOF
    echo ""
    echo -e "${YELLOW}IMPORTANTE:${NC}"
    echo "O consentimento administrativo pode nao ter sido concedido automaticamente."
    echo "Caso necessario, conceda manualmente no portal do Entra ID:"
    echo "  https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationsListBlade"
    echo "Localize o app, va em 'API Permissions' e clique em 'Grant admin consent'."
    echo ""
    log "Configuracao concluida! Credenciais salvas em: $ENV_FILE"
}

# ------------------ EXECUCAO ------------------
log "=== Iniciando Azure CSPM/FinOps Setup Tool ==="
instalar_dependencias
autenticar_azure
mapear_assinaturas
registrar_aplicacao
criar_secret
set_graph_permissions
set_rbac_permissions
gerar_output
