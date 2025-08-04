# AWS – Integração com a Plataforma Vulneri

Este diretório contém os scripts para configuração da conta AWS para integração com a plataforma da Vulneri, permitindo a coleta de dados de segurança e custo.

## Arquivos disponíveis

- `cspm_aws.sh` – Script em shell para criação de roles e políticas IAM com permissões mínimas necessárias.

## Pré-requisitos

- AWS CLI configurado e autenticado (via `aws configure`)
- Permissões para criação de funções e políticas IAM

## Execução

```bash
chmod +x cspm_aws.sh
./cspm_aws.sh

