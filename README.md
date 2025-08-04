# Vulneri CSPM – Scripts de Integração para AWS, Azure e Microsoft 365

Este repositório contém scripts de integração com os principais provedores de nuvem para habilitar a coleta de dados pela plataforma da Vulneri, incluindo:

- Cloud Security Posture Management (CSPM)
- FinOps (gestão de custos em nuvem)

## Estrutura do Repositório

Os scripts estão organizados por provedor na pasta `/SCRIPTS`, conforme abaixo:

SCRIPTS/
├── AWS/
│ ├── cspm_aws.sh
│ └── README.md
├── AZURE/
│ ├── cspm_azure.sh
│ ├── cspm_azure.ps1
│ └── README.md
├── M365/
│ ├── cspm_m365.sh
│ ├── cspm_m365.ps1
│ └── README.md

Cada diretório contém os scripts e instruções específicas de uso para o ambiente correspondente.

## Finalidade

Estes scripts têm como objetivo facilitar a configuração das permissões necessárias para que a plataforma Vulneri possa acessar dados de segurança e consumo nos ambientes em nuvem dos clientes.

## Pré-requisitos

- Permissões administrativas nas contas configuradas
- Instalação prévia das ferramentas de linha de comando (AWS CLI, Azure CLI, PowerShell)
- Conhecimento básico sobre execução de scripts em shell ou PowerShell

## Segurança

Todos os scripts são auditáveis e não enviam dados sensíveis para fora do ambiente do cliente sem consentimento. É recomendável a execução em ambiente controlado e por pessoal autorizado.

## Contato

Dúvidas, sugestões ou problemas podem ser encaminhados para: contato@vulneri.com.br

© 2025 Vulneri Segurança Digital
