#!/usr/bin/env bash
#
# SYNOPSIS
#   Script para automatizar a criacao de aplicacao no Entra ID e configuracao de permissoes 
#   para rodar vulneri_cspm_m365 no Microsoft 365 (M365).
#
# DESCRIPTION
#   Realiza:
#   - Verificacao de dependencias (az, jq)
#   - Verificacao de licenciamento (SKUs)
#   - Criacao da aplicacao e client secret
#   - Adicao de permissoes (Graph, Exchange, Teams, O365 Management)
#   - Consentimento administrativo e atribuicao de papel 'Global Reader'
#

set -e

# ------------------ CORES ------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO] $1${NC}"; }
warn() { echo -e "${YELLOW}[AVISO] $1${NC}"; }
error_exit() { echo -e "${RED}[ERRO] $1${NC}"; exit 1; }

log "=== Iniciando CSPM_M365: Configuracao automatizada (Bash) ==="

# 1. Instalacao do Azure CLI (Auto)
install_azcli() {
    echo -e "${YELLOW}[INFO] Azure CLI nao detectada. Deseja instalar agora? (s/n)${NC}"
    read -r response
    if [[ "$response" =~ ^([sS][iI]|[sS])$ ]]; then
        echo -e "${YELLOW}[INFO] Iniciando instalacao oficial da Microsoft...${NC}"
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
        echo -e "${GREEN}[OK] Instalacao concluida. Reinicie o terminal ou rode 'exec bash' para usar o comando 'az'.${NC}"
        exit 0
    else
        echo -e "${RED}[ERRO] Azure CLI eh obrigatoria para este script.${NC}"
        exit 1
    fi
}

# 2. Verificacao de dependencias
check_dependencies() {
    if ! command -v az &> /dev/null; then
        install_azcli
    fi
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}[INFO] jq nao encontrado. Tentando instalar...${NC}"
        sudo apt update && sudo apt install -y jq
    fi
    echo -e "${GREEN}[OK] Dependencias verificadas.${NC}"
}

# 2. Login
start_login() {
    if ! az account show > /dev/null 2>&1; then
        echo -e "${YELLOW}--- Login Azure/Microsoft 365 ---${NC}"
        log "Por favor faca login na sua conta Azure/M365."
        az login --allow-no-subscriptions > /dev/null
    fi
}

# 3. Verificacao de Licenciamento
check_licensing() {
    echo -e "${YELLOW}[INFO] Verificando licenciamento do tenant (SKUs)...${NC}"
    SKUS=$(az rest --method get --url https://graph.microsoft.com/v1.0/subscribedSkus 2>/dev/null || echo "")
    
    if [ -n "$SKUS" ]; then
        echo "### Licencas Encontradas ###"
        SECURITY_FOUND=false
        # Itera via jq
        while read -r line; do
            echo "  - $line"
            if [[ "$line" =~ AAD_PREMIUM|SPE_E3|SPE_E5|ENTERPRISEPREMIUM|AAD_PREMIUM_V2 ]]; then
                SECURITY_FOUND=true
            fi
        done < <(echo "$SKUS" | jq -r '.value[] | "\(.skuPartNumber) (Total: \(.prepaidUnits.enabled))"')
        
        if [ "$SECURITY_FOUND" = false ]; then
            warn "Nenhuma licenca de seguranca avancada (P1/P2/E3/E5) detectada."
        else
            log "Licencas de seguranca detectadas."
        fi
    else
        warn "Nao foi possivel validar SKUs."
    fi
}

# 4. Helper para GUIDs
get_guid() {
    local sp_id=$1
    local perm_name=$2
    
    # Tenta criar o SP caso nao exista (necessario para APIs como O365 Management)
    az ad sp create --id "$sp_id" > /dev/null 2>&1 || true
    
    # Busca dinamica
    local res
    res=$(az ad sp show --id "$sp_id" --query "appRoles[?value=='$perm_name'].id" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$res" ]; then
        echo "$res"
    else
        # Fallback Hardcoded para Microsoft Graph
        if [ "$sp_id" == "00000003-0000-0000-c000-000000000000" ]; then
            case "$perm_name" in
                "AuditLog.Read.All") echo "b0afded3-3588-46d8-8b3d-9842eff778da" ;;
                "Directory.Read.All") echo "7ab1d382-f21e-4acd-a863-ba3e13f7da61" ;;
                "Policy.Read.All") echo "246dd0d5-5bd0-4def-940b-0421030a5b68" ;;
                "SharePointTenantSettings.Read.All") echo "83d4163d-a2d8-4d3b-9695-4ae3ca98f888" ;;
                "Organization.Read.All") echo "498476ce-e0fe-48b0-801-37ba7e2685c6" ;;
                "Domain.Read.All") echo "dbb9058a-0e50-45d7-ae91-66909b5d4664" ;;
                "SecurityEvents.Read.All") echo "bf394140-e372-4bf9-a898-299cfc7564e5" ;;
                "RoleManagement.Read.Directory") echo "483bed4a-2ad3-4361-a73b-c83ccdbdc53c" ;;
                "Policy.Read.ConditionalAccess") echo "37730810-e9ba-4e46-b07e-8ca78d182097" ;;
                "IdentityRiskEvent.Read.All") echo "6e472fd1-ad78-48da-a0f0-97ab2c6b769e" ;;
                "Reports.Read.All") echo "230claed-a721-4c5d-9cb4-a90514e508ef" ;;
                "Billing.Read.All") echo "b8964574-aaa4-4efd-ad07-062e078ea873" ;;
                "SubscribedSkus.Read.All") echo "f3796328-9177-4401-b687-d16ad56ed3e4" ;;
            esac
        # Fallback para Exchange Online
        elif [ "$sp_id" == "00000002-0000-0ff1-ce00-000000000000" ]; then
            [ "$perm_name" == "Exchange.ManageAsApp" ] && echo "dc50a0fb-09a3-4afb-8abc-f050f4205512"
        # Fallback para O365 Management API
        elif [ "$sp_id" == "ff74b927-94b6-45bc-9171-47fed879668d" ]; then
            case "$perm_name" in
                "ActivityFeed.Read") echo "c5301311-66d4-4530-90fe-431835773177" ;;
                "ActivityFeed.ReadDlp") echo "e1136b36-508b-49fc-9eac-62423e85934f" ;;
                "ServiceHealth.Read") echo "656bb153-61ce-427c-9b16-52bb664c1206" ;;
            esac
        fi
    fi
}

check_dependencies
start_login
check_licensing

TIMESTAMP=$(date +%s)
APP_NAME="Vulneri_CSPM_M365_$TIMESTAMP"
SECRET_NAME="Vulneri_CSPM_M365Secret"

echo -e "${YELLOW}[INFO] Criando aplicacao Entra ID: $APP_NAME...${NC}"
APP_JSON=$(az ad app create --display-name "$APP_NAME")
APP_ID=$(echo "$APP_JSON" | jq -r '.appId')
OBJ_ID=$(echo "$APP_JSON" | jq -r '.id')

if [ -z "$APP_ID" ] || [ "$APP_ID" == "null" ]; then
    error_exit "Falha ao criar aplicacao."
fi

TENANT_ID=$(az account show --query tenantId -o tsv)

log "Gerando segredo de cliente..."
SECRET_VALUE=$(az ad app credential reset --id "$APP_ID" --append --display-name "$SECRET_NAME" --query password -o tsv)

# Espera propagacao
log "Aguardando propagacao inicial do App (10s)..."
sleep 10

# Permissoes
log "Configurando permissoes..."
MS_GRAPH="00000003-0000-0000-c000-000000000000"
EXCHANGE="00000002-0000-0ff1-ce00-000000000000"
TEAMS="48ac35b8-9aa8-4d74-927d-1f4a14a0b239"
O365_MGMT="ff74b927-94b6-45bc-9171-47fed879668d"

# Graph
GRAPH_PERMS=("AuditLog.Read.All" "Directory.Read.All" "Policy.Read.All" "SharePointTenantSettings.Read.All" "Organization.Read.All" "Domain.Read.All" "SecurityEvents.Read.All" "RoleManagement.Read.Directory" "Policy.Read.ConditionalAccess" "IdentityRiskEvent.Read.All" "Reports.Read.All" "Billing.Read.All" "SubscribedSkus.Read.All")
for perm in "${GRAPH_PERMS[@]}"; do
    GUID=$(get_guid "$MS_GRAPH" "$perm")
    [ -n "$GUID" ] && az ad app permission add --id "$APP_ID" --api "$MS_GRAPH" --api-permissions "$GUID=Role" > /dev/null
done

# Exchange
GUID=$(get_guid "$EXCHANGE" "Exchange.ManageAsApp")
[ -n "$GUID" ] && az ad app permission add --id "$APP_ID" --api "$EXCHANGE" --api-permissions "$GUID=Role" > /dev/null

# O365 Management
MGMT_PERMS=("ActivityFeed.Read" "ActivityFeed.ReadDlp" "ServiceHealth.Read")
for perm in "${MGMT_PERMS[@]}"; do
    GUID=$(get_guid "$O365_MGMT" "$perm")
    [ -n "$GUID" ] && az ad app permission add --id "$APP_ID" --api "$O365_MGMT" --api-permissions "$GUID=Role" > /dev/null
done

log "Solicitando consentimento administrativo..."
az ad app permission admin-consent --id "$APP_ID" > /dev/null 2>&1 || {
    warn "Consentimento automatico falhou (comum em tenants M365)."
    echo -e "${YELLOW}[ACAO NECESSARIA] Clique no link abaixo e clique em 'Conceder Consentimento' para finalizar:${NC}"
    echo -e "${GREEN}https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/CallAnAPI/appId/$APP_ID/isRedirect~/true/isMSAApp~/false/showInServiceTree~/false${NC}"
}

echo -e "${YELLOW}[INFO] Atribuindo papeis 'Global Reader' e 'Billing Reader' via RBAC...${NC}"
az ad sp create --id "$APP_ID" > /dev/null 2>&1 || true

SP_OBJ_ID=""
for i in {1..6}; do
    SP_OBJ_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || echo "")
    [ -n "$SP_OBJ_ID" ] && break
    echo -e "${YELLOW}[INFO] Aguardando propagacao do SP... ($i/6)${NC}"
    sleep 5
done

if [ -z "$SP_OBJ_ID" ]; then
    warn "Falha ao obter Object ID do Service Principal. Pule a etapa de RBAC manual se necessario."
else
    az role assignment create --assignee "$SP_OBJ_ID" --role "Global Reader" --scope "/" > /dev/null 2>&1 || warn "Falha na atribuicao de Global Reader."
    az role assignment create --assignee "$SP_OBJ_ID" --role "Billing Reader" --scope "/" > /dev/null 2>&1 || warn "Falha na atribuicao de Billing Reader."
fi

# Export
ENV_FILE="vulneri_cspm_m365_env.txt"
cat <<EOF > "$ENV_FILE"
export AZURE_CLIENT_ID='$APP_ID'
export AZURE_CLIENT_SECRET='$SECRET_VALUE'
export AZURE_TENANT_ID='$TENANT_ID'
EOF

echo -e "${GREEN}"
echo "=============================================================="
echo "Sucesso! Arquivo gerado: $ENV_FILE"
echo "Use 'source $ENV_FILE' antes de rodar seu scanner."
echo "=============================================================="
echo -e "${NC}"
