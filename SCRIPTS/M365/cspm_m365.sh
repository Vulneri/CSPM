#!/bin/bash

### CSPM_M365.sh
### Script para automatizar criação de aplicação e permissões para rodar vulneri_cspm_m365 no Microsoft 365 (M365)
### Inclui Microsoft Graph, Exchange Online, Skype and Teams Tenant Admin API, lembrete para roles administrativas
set -e

echo "=== Iniciando CSPM_M365: Configuração automatizada para Vulneri_CSPM_M365 ==="

# Funções para instalar dependências
install_azure_cli() {
  echo "[INFO] Azure CLI não encontrada. Instalando Azure CLI..."
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  echo "[OK] Azure CLI instalada com sucesso."
}

install_jq() {
  echo "[INFO] jq não encontrado. Instalando jq..."
  sudo apt-get update
  sudo apt-get install -y jq
  echo "[OK] jq instalado com sucesso."
}

# Verificações e instalações obrigatórias
if ! command -v az >/dev/null 2>&1; then
  install_azure_cli
else
  echo "[OK] Azure CLI já instalada."
fi

if ! command -v jq >/dev/null 2>&1; then
  install_jq
else
  echo "[OK] jq já instalado."
fi

echo ""
echo "--- Login Azure/Microsoft 365 ---"
echo "Por favor, faça login na sua conta Azure/M365."
az account show >/dev/null 2>&1 || az login --allow-no-subscriptions

echo ""
APP_NAME="Vulneri_CSPM_M365_$(date +%s)"
SECRET_NAME="Vulneri_CSPM_M365Secret"

echo "[INFO] Criando aplicação Azure AD (Entra ID) com nome: $APP_NAME"
APP_JSON=$(az ad app create --display-name "$APP_NAME")
APP_ID=$(echo "$APP_JSON" | jq -r '.appId')
OBJECT_ID=$(echo "$APP_JSON" | jq -r '.id')

if [[ -z "$APP_ID" || "$APP_ID" == "null" ]]; then
  echo "[ERRO] Falha ao criar a aplicação Azure AD."
  exit 1
fi

TENANT_ID=$(az account show | jq -r '.tenantId')

echo "[INFO] Registrando segredo de cliente da aplicação..."
SECRET_JSON=$(az ad app credential reset --id "$APP_ID" --append --display-name "$SECRET_NAME")
SECRET_VALUE=$(echo "$SECRET_JSON" | jq -r '.password')

if [[ -z "$SECRET_VALUE" || "$SECRET_VALUE" == "null" ]]; then
  echo "[ERRO] Falha ao gerar o segredo da aplicação."
  exit 1
fi

echo ""
echo "[INFO] Resolvendo GUIDs das permissões necessárias para o vulneri_cspm_m365..."

# GUIDs das APIs
MS_GRAPH_API="00000003-0000-0000-c000-000000000000"
EXCHANGE_API="00000002-0000-0ff1-ce00-000000000000"
TEAMS_API="48ac35b8-9aa8-4d74-927d-1f4a14a0b239"    # Corrigido conforme você mencionou

# Permissões Microsoft Graph (Application Role)
GRAPH_PERMISSIONS=(
  "AuditLog.Read.All"
  "Directory.Read.All"
  "Policy.Read.All"
  "SharePointTenantSettings.Read.All"
  "Organization.Read.All"
  "Domain.Read.All"
)

# Permissão delegada User.Read (opcional, para user authentication)
# Não adicionamos no script pelas limitações de app-only, mas deixamos o aviso abaixo

declare -a GRAPH_PERMISSION_GUIDS=()
for PERM in "${GRAPH_PERMISSIONS[@]}"
do
  GUID=$(az ad sp show --id $MS_GRAPH_API | jq -r --arg val "$PERM" '.appRoles[] | select(.value==$val) | .id')
  if [[ -z "$GUID" ]]; then
    echo "[ERRO] GUID para permissão '$PERM' não encontrado no Microsoft Graph."
    exit 1
  else
    echo "[OK] Permissão '$PERM' (Microsoft Graph) -> GUID: $GUID"
    GRAPH_PERMISSION_GUIDS+=("$GUID")
  fi
done

# Permissão Exchange.ManageAsApp
EXCHANGE_GUID=$(az ad sp show --id $EXCHANGE_API | jq -r '.appRoles[] | select(.value=="Exchange.ManageAsApp") | .id')
if [[ -z "$EXCHANGE_GUID" ]]; then
  echo "[ERRO] GUID para permissão 'Exchange.ManageAsApp' não encontrado no Exchange Online."
  exit 1
else
  echo "[OK] Permissão 'Exchange.ManageAsApp' (Exchange Online) -> GUID: $EXCHANGE_GUID"
fi

# Permissão application_access - Skype and Teams Tenant Admin API
TEAMS_GUID=$(az ad sp show --id $TEAMS_API | jq -r '.appRoles[] | select(.value=="application_access") | .id')
if [[ -z "$TEAMS_GUID" ]]; then
  echo "[ERRO] GUID para permissão 'application_access' não encontrado no Skype and Teams Tenant Admin API."
  exit 1
else
  echo "[OK] Permissão 'application_access' (Teams API) -> GUID: $TEAMS_GUID"
fi

echo ""
echo "[INFO] Adicionando permissões à aplicação..."

for GUID in "${GRAPH_PERMISSION_GUIDS[@]}"
do
  echo "[INFO] Adicionando permissão GUID $GUID (Microsoft Graph)..."
  az ad app permission add --id "$APP_ID" --api "$MS_GRAPH_API" --api-permissions "${GUID}=Role"
done

echo "[INFO] Adicionando permissão GUID $EXCHANGE_GUID (Exchange Online)..."
az ad app permission add --id "$APP_ID" --api "$EXCHANGE_API" --api-permissions "${EXCHANGE_GUID}=Role"

echo "[INFO] Adicionando permissão GUID $TEAMS_GUID (Teams API)..."
az ad app permission add --id "$APP_ID" --api "$TEAMS_API" --api-permissions "${TEAMS_GUID}=Role"

echo "[INFO] Tentando conceder consentimento administrativo para todas as permissões..."
if az ad app permission admin-consent --id "$APP_ID"; then
  echo "[OK] Consentimento administrativo concedido com sucesso para todas as permissões."
else
  echo "[AVISO] Consentimento administrativo NÃO pôde ser concedido automaticamente."
fi

echo ""
echo "[INFO] Salvando variáveis de ambiente em 'vulneri_cspm_m365_env.txt'..."

cat > vulneri_cspm_m365_env.txt <<EOF
export AZURE_CLIENT_ID='$APP_ID'
export AZURE_CLIENT_SECRET='$SECRET_VALUE'
export AZURE_TENANT_ID='$TENANT_ID'
EOF

chmod 600 vulneri_cspm_m365_env.txt
echo "Exibe o conteudo de vulneri_cspm_m365_env.txt" 
cat vulneri_cspm_m365_env.txt

echo ""
echo "=============================================================="
echo "Processo concluído!"

echo ""
echo "IMPORTANTE:"
echo "O consentimento administrativo não foi concedido automaticamente,"
echo "conceda manualmente no portal do Entra ID:"
echo "  https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationsListBlade"
echo "  Localize o app, vá em Manage e 'Permissões de API' ou 'API Permissions'" 
echo "  e clique 'Conceder consentimento do administrador para <tenant>' ou 'Grand admin consent for<tenant>'."
echo ""
echo "Variáveis de ambiente criadas no arquivo vulneri_cspm_m365_env.txt"
echo "=============================================================="
