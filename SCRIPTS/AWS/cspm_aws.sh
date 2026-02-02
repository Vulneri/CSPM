#!/usr/bin/env bash

# Cores e Estilo Amigável
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

open_url() {
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$1" >/dev/null 2>&1 &
  elif command -v open >/dev/null 2>&1; then
    open "$1" >/dev/null 2>&1 &
  else
    echo -e "${YELLOW}Não consegui abrir o navegador automaticamente. Acesse:${NC} $1"
  fi
}

log() { echo -e "${GREEN}[VULNERI]${NC} $1"; }
err() { echo -e "${RED}[ERRO]${NC} $1"; }

# --- BANNER INICIAL ---
clear
echo -e "${BLUE}==========================================================${NC}"
echo -e "${BLUE} ASSISTENTE DE CONFIGURAÇÃO VULNERI (CSPM) ${NC}"
echo -e "${BLUE}==========================================================${NC}"
echo -e "Vou guiar você passo a passo para conectar sua AWS à Vulneri.\n"

# --- ETAPA 0: DEPENDÊNCIAS ---
if ! command -v jq &>/dev/null; then
  log "Instalando ferramenta 'jq' necessária..."
  if ! sudo apt update -y && sudo apt install -y jq; then
    err "Não foi possível instalar o jq. Instale manualmente e rode o script novamente."
    exit 1
  fi
fi

if ! command -v aws &>/dev/null; then
  err "AWS CLI não encontrado. Instale o awscli antes de continuar."
  exit 1
fi

# --- ETAPA 0.5: DETECTAR PERFIL EXISTENTE ---
if [[ -f ~/.aws/config ]] && grep -q "\[profile Vulneri_Setup\]" ~/.aws/config; then
  echo -e "\n${YELLOW}🔍 DETECTADO:${NC} Perfil 'Vulneri_Setup' já existe em ~/.aws/config"
  echo -e "${CYAN}O que você quer fazer?${NC}"
  echo "1) ${GREEN}Reutilizar e só fazer login SSO novamente${NC}"
  echo "2) ${YELLOW}Apagar e configurar do zero${NC}"
  echo "3) ${RED}Sair${NC}"
  read -p "Escolha [1-3]: " CHOICE
  
  case $CHOICE in
    1)
      log "Reutilizando perfil existente. Só faremos login SSO."
      # Pular para login SSO direto
      SKIP_CONFIG=true
      ;;
    2)
      log "Apagando perfil antigo..."
      sed -i '/\[profile Vulneri_Setup\]/,/output = json/d' ~/.aws/config
      log "Perfil removido. Continuando configuração do zero."
      ;;
    3)
      echo "Saindo..."
      exit 0
      ;;
    *)
      err "Opção inválida. Saindo."
      exit 1
      ;;
  esac
fi

# --- ETAPA 1: COLETA DE INFORMAÇÕES (se não pulou) ---
if [[ "$SKIP_CONFIG" != "true" ]]; then
  # --- ETAPA 1.1: AWS ACCESS PORTAL URL ---
  echo -e "\n${CYAN}>>> ETAPA 1.1: Localizando o Portal de Acesso${NC}"
  echo -e "DICA: Geralmente ele começa com ${BLUE}https://d-${NC} (ex: https://d-847594...) Fica em AWS access portal URLs --> Default IPv4 only ."
  read -p "Pressione [ENTER] para abrir o navegador..." _
  open_url "https://console.aws.amazon.com/singlesignon/home#/dashboard"

  read -p "Cole o link do portal aqui: " START_URL
  if [[ -z "$START_URL" ]]; then
    err "START URL não informado."
    exit 1
  fi

  # --- ETAPA 1.2: REGION ---
  echo -e "\n${CYAN}>>> ETAPA 1.2: Localizando a Região${NC}"
  read -p "Pressione [ENTER] para abrir as configurações..." _
  open_url "https://console.aws.amazon.com/singlesignon/home#/settings"
  echo -e "Vá em '${BLUE}Settings${NC}' -> '${BLUE}Details${NC}' e procure por '${BLUE}Region${NC}'."
  read -p "Região [us-east-1]: " REGION
  REGION=${REGION:-us-east-1}

  # --- ETAPA 1.3a: ID DA CONTA ---
  echo -e "\n${CYAN}>>> ETAPA 1.3a: Localizando ID da Conta AWS${NC}"
  echo -e "No console AWS já aberto, procure no topo direito logo abaixo do seu usuário que voce se logou --> Account ID XXXX-XXXX-XXXX:"
  echo -e "${YELLOW}XXXX-XXXX-XXXX${NC} (12 dígitos que aparecem ali)."
  echo -e "Copie exatamente esses 12 números."
  read -p "Pressione [ENTER] quando tiver o ID da conta..." _

  read -p "ID da conta AWS (12 dígitos): " ACCOUNT_ID
  if [[ -z "$ACCOUNT_ID" ]]; then
    err "Account ID não informado."
    exit 1
  fi

  # --- ETAPA 1.3b: ROLE SSO ---
  echo -e "\n${CYAN}>>> ETAPA 1.3b: Localizando Role/Permission Set SSO${NC}"
  echo -e "Agora vamos abrir o IAM Identity Center."
  echo -e "Siga exatamente estes passos:"
  echo -e "1) Clique em '${BLUE}Multi-account permissions${NC}'"
  echo -e "2) Clique em '${BLUE}AWS accounts${NC}'"
  echo -e "3) Clique na sua conta (ou no seu grupo)"
  echo -e "4) Clique em '${BLUE}Permission set${NC}'"
  echo -e "5) Selecione a permission set que você utiliza"
  echo -e "   (copie o nome dela, ex: AdministratorAccess, Vulneri-Admin...)"
  read -p "Pressione [ENTER] para abrir o IAM Identity Center..." _
  open_url "https://console.aws.amazon.com/singlesignon/home#/aws-accounts"

  read -p "Nome da permission set/role que você usa: " ROLE_NAME
  if [[ -z "$ROLE_NAME" ]]; then
    err "Role SSO não informada."
    exit 1
  fi

  # --- CONFIGURAÇÃO DE PERFIL ---
  log "Configurando perfil 'Vulneri_Setup'..."
  mkdir -p ~/.aws

  cat > ~/.aws/config <<EOF
[profile Vulneri_Setup]
sso_start_url = $START_URL
sso_region = $REGION
sso_account_id = $ACCOUNT_ID
sso_role_name = $ROLE_NAME
region = $REGION
output = json
EOF
fi

# --- LOGIN SSO ---
echo -e "\n${YELLOW}[AÇÃO NO NAVEGADOR]${NC}"
echo -e "1) Vá no navegador já aberto com o portal SSO"
echo -e "2) Clique no botão laranja '${YELLOW}Allow access${NC}' para autorizar este terminal."
read -p "Pressione [ENTER] APÓS autorizar no navegador..." _

aws sso login --profile Vulneri_Setup
if [[ $? -ne 0 ]]; then
  err "Falha ao realizar login SSO. Verifique o START URL, a conta e a role, depois tente novamente."
  exit 1
fi

export AWS_PROFILE="Vulneri_Setup"
sleep 2

# --- ETAPA 2: CRIAÇÃO DO USUÁRIO ---
log "Iniciando criação na AWS..."
USER_NAME="Vulneri-RO-Key"

if ! aws iam get-user --user-name "$USER_NAME" &>/dev/null; then
  if aws iam create-user --user-name "$USER_NAME" >/dev/null; then
    log "✅ Usuário técnico criado com sucesso."
  else
    err "❌ Não foi possível criar o usuário IAM '$USER_NAME'. Verifique se a role SSO possui permissão de IAM."
    exit 1
  fi
else
  log "ℹ️ Usuário já existe, prosseguindo..."
fi

# --- Política de segurança COMPLETA (CSPM + FinOps) ---
POLICY_ARN=$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='Vulneri-CSPM-FinOps-Policy'].Arn" \
  --output text 2>/dev/null)

if [[ -z "$POLICY_ARN" || "$POLICY_ARN" == "None" ]]; then
  log "Enviando política de segurança completa (CSPM + FinOps)..."
  cat > vulneri_cspm_finops.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowInventory",
      "Effect": "Allow",
      "Action": [
        "account:Get*",
        "appstream:Describe*",
        "appstream:List*",
        "backup:List*",
        "backup:Get*",
        "bedrock:List*",
        "bedrock:Get*",
        "ce:Get*",
        "ce:Describe*",
        "ce:List*",
        "cloudtrail:GetInsightSelectors",
        "codeartifact:List*",
        "codebuild:BatchGet*",
        "codebuild:ListReportGroups",
        "cognito-idp:GetUserPoolMfaConfig",
        "dlm:Get*",
        "drs:Describe*",
        "ds:Get*",
        "ds:Describe*",
        "ds:List*",
        "dynamodb:GetResourcePolicy",
        "ec2:Describe*",
        "ec2:GetEbsEncryptionByDefault",
        "ec2:GetSnapshotBlockPublicAccessState",
        "ec2:GetInstanceMetadataDefaults",
        "ecr:Describe*",
        "ecr:GetRegistryScanningConfiguration",
        "elasticfilesystem:DescribeBackupPolicy",
        "glue:GetConnections",
        "glue:GetSecurityConfiguration*",
        "glue:SearchTables",
        "glue:GetMLTransforms",
        "iam:Get*",
        "iam:List*",
        "lambda:GetFunction*",
        "logs:FilterLogEvents",
        "lightsail:GetRelationalDatabases",
        "macie2:GetMacieSession",
        "macie2:GetAutomatedDiscoveryConfiguration",
        "organizations:Describe*",
        "pricing:DescribeServices",
        "pricing:GetAttributeValues",
        "pricing:GetProducts",
        "rds:Describe*",
        "s3:ListAllMyBuckets",
        "s3:GetAccountPublicAccessBlock",
        "shield:DescribeProtection",
        "shield:GetSubscriptionState",
        "securityhub:GetFindings",
        "servicecatalog:Describe*",
        "servicecatalog:List*",
        "ssm:GetDocument",
        "ssm-incidents:List*",
        "states:ListTagsForResource",
        "support:Describe*",
        "tag:GetTagKeys",
        "wellarchitected:List*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowAPIGatewayReadOnly",
      "Effect": "Allow",
      "Action": [
        "apigateway:GET"
      ],
      "Resource": [
        "arn:*:apigateway:*::/restapis/*",
        "arn:*:apigateway:*::/apis/*"
      ]
    },
    {
      "Sid": "DenySensitive",
      "Effect": "Deny",
      "Action": [
        "s3:GetObject",
        "secretsmanager:GetSecretValue",
        "kms:Decrypt"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  POLICY_ARN=$(aws iam create-policy \
    --policy-name "Vulneri-CSPM-FinOps-Policy" \
    --policy-document file://vulneri_cspm_finops.json \
    --query 'Policy.Arn' --output text 2>/dev/null)

  if [[ -z "$POLICY_ARN" || "$POLICY_ARN" == "None" ]]; then
    err "❌ Falha ao criar a política 'Vulneri-CSPM-FinOps-Policy'."
    exit 1
  fi
  log "✅ Política de segurança criada."
else
  log "ℹ️ Política 'Vulneri-CSPM-FinOps-Policy' já existe."
fi

aws iam attach-user-policy --user-name "$USER_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/ReadOnlyAccess" >/dev/null
aws iam attach-user-policy --user-name "$USER_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/SecurityAudit" >/dev/null
aws iam attach-user-policy --user-name "$USER_NAME" \
  --policy-arn "$POLICY_ARN" >/dev/null

log "✅ Políticas anexadas ao usuário."

# --- ETAPA 3: GERAR CHAVES FINAIS ---
log "Gerando Access Keys permanentes..."
KEYS=$(aws iam create-access-key --user-name "$USER_NAME" --output json 2>/dev/null)
if [[ -z "$KEYS" ]]; then
  err "❌ Não foi possível criar Access Keys. Verifique limites de chaves do usuário ou permissões."
  exit 1
fi

ACCESS_KEY=$(echo "$KEYS" | jq -r '.AccessKey.AccessKeyId')
SECRET_KEY=$(echo "$KEYS" | jq -r '.AccessKey.SecretAccessKey')

cat > vulneri_credentials.env <<EOF
export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
export AWS_DEFAULT_REGION="${REGION:-us-east-1}"
EOF

# --- VERIFICAÇÃO FINAL ---
log "✅ VERIFICAÇÃO FINAL:"
if aws sts get-caller-identity >/dev/null 2>&1; then
  log "✅ Credenciais funcionando perfeitamente!"
else
  err "⚠️ Credenciais geradas mas teste falhou. Use manualmente com 'source vulneri_credentials.env'"
fi

echo -e "\n${BLUE}🎉 CONFIGURAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
echo -e "${CYAN}Próximos passos:${NC}"
echo -e "1) ${YELLOW}cat vulneri_credentials.env${NC}"
echo -e "3) Agora cole essas credenciais no painel da Vulneri!"

unset AWS_PROFILE
rm -f vulneri_cspm_finops.json

echo -e "\n${GREEN}Pressione [ENTER] para sair.${NC}"
read
