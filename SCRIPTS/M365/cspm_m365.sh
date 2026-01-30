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

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Iniciando CSPM_M365: Configuracao automatizada (Bash) ===${NC}"

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
        echo "Por favor faca login na sua conta Azure/M365."
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
            echo -e "${YELLOW}[AVISO] Nenhuma licenca de seguranca avancada (P1/P2/E3/E5) detectada.${NC}"
        else
            echo -e "${GREEN}[OK] Licencas de seguranca detectadas.${NC}"
        fi
    else
        echo -e "${YELLOW}[AVISO] Nao foi possivel validar SKUs.${NC}"
    fi
}

# 4. Helper para GUIDs
get_guid() {
    local sp_id=$1
    local perm_name=$2
    az ad sp show --id "$sp_id" | jq -r ".appRoles[] | select(.value==\"$perm_name\") | .id"
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
    echo -e "${RED}[ERRO] Falha ao criar aplicacao.${NC}"
    exit 1
fi

TENANT_ID=$(az account show | jq -r '.tenantId')

echo -e "${YELLOW}[INFO] Gerando segredo de cliente...${NC}"
SECRET_VALUE=$(az ad app credential reset --id "$APP_ID" --append --display-name "$SECRET_NAME" | jq -r '.password')

# Permissoes
echo -e "${YELLOW}[INFO] Configurando permissoes...${NC}"
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

echo -e "${YELLOW}[INFO] Solicitando consentimento administrativo...${NC}"
az ad app permission admin-consent --id "$APP_ID" || echo -e "${YELLOW}[AVISO] Consentimento automatico falhou.${NC}"

echo -e "${YELLOW}[INFO] Atribuindo papeis 'Global Reader' e 'Billing Reader' via RBAC...${NC}"
az ad sp create --id "$APP_ID" > /dev/null 2>&1 || true
SP_OBJ_ID=$(az ad sp show --id "$APP_ID" | jq -r '.id')
az role assignment create --assignee "$SP_OBJ_ID" --role "Global Reader" --scope "/" > /dev/null || echo -e "${YELLOW}[AVISO] Falha na atribuicao de Global Reader.${NC}"
az role assignment create --assignee "$SP_OBJ_ID" --role "Billing Reader" --scope "/" > /dev/null || echo -e "${YELLOW}[AVISO] Falha na atribuicao de Billing Reader.${NC}"

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
