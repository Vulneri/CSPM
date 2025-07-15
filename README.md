# CSPM
# README - Criacao de Usuario IAM com Perfil SSO

## Visao Geral
Este script automatiza todo o processo de:

1. Instalacao de dependencias necessárias (curl, unzip, jq, python3, etc.)
2. Instalacao da AWS CLI v2 (caso nao esteja instalada)
3. Verificacao do perfil SSO `Vulneri`
4. Verificacao de autenticacao com `aws sso login`
5. Criacao de um usuario IAM com nome `ReadOnly-Key-To-Vulneri`
6. Geracao de uma nova access key (limitada a 2 por usuario)
7. Atribuicao das politicas `ReadOnlyAccess` e `SecurityAudit`
8. Salvamento das credenciais em um arquivo `.csv`
9. Exibicao do conteudo do arquivo `.csv` ao final

---

## Pre-requisitos

- Ter acesso administrativo a uma conta AWS com permissao para:
  - Criar usuarios IAM
  - Criar access keys
  - Atribuir politicas

- Ter o perfil `Vulneri` previamente configurado com:

```bash
/usr/local/bin/aws configure sso --profile Vulneri
```

Durante essa configuracao, voce devera inserir:
- SSO start URL (ex: https://d-xxxxxxxxxx.awsapps.com/start)
- SSO region (ex: us-east-1)
- SSO registration scopes (ex: sso:account:access)

- Autenticar-se com:

```bash
/usr/local/bin/aws sso login --profile Vulneri
```

---

## Como executar

1. Dê permissao de execucao ao script:

```bash
chmod +x criar-usuario-vulneri.sh
```

2. Execute o script:

```bash
./criar-usuario-vulneri.sh
```

---

## Resultado Esperado

- Um usuario IAM chamado `ReadOnly-Key-To-Vulneri` sera criado (caso ainda nao exista).
- Uma nova access key sera gerada (desde que o usuario tenha menos de 2 keys ativas).
- As politicas `ReadOnlyAccess` e `SecurityAudit` serao aplicadas ao usuario.
- As credenciais serao salvas no arquivo:

```bash
ReadOnly-Key-To-Vulneri_accessKeys.csv
```

- O script exibira automaticamente o conteudo do `.csv` na tela:

```csv
Access Key ID,Secret Access Key
AKIAxxxxxxxxxxxxxxxx,xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

---

## Observacoes de Seguranca

- O script nao sobrescreve nenhuma key existente.
- Caso o limite de 2 access keys ja tenha sido atingido, o script ira abortar com uma mensagem clara.
- Nenhuma credencial e enviada por rede ou armazenada fora do arquivo `.csv` local.

---

## Suporte

Em caso de duvidas ou problemas, envie o arquivo `.csv` gerado para:

```
security@vulneri.io
```

---

**Fim do README**
