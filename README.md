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

## As saidas do script são as seguintes:
## 1 - Configurar perfil AWSCLI
 **/usr/local/bin/aws configure sso --profile Vulneri**

 SSO session name (Recommended): Vulneri- SSO start URL [None]: https://d-9XXXXX6XX.awsapps.com/start
 SSO region [None]: us-east-1
 SSO registration scopes [sso:account:access]: sso:account:access
 Attempting to automatically open the SSO authorization page in your default browser.
 If the browser does not open or you wish to use a different device to authorize this request, open the following URL:
 
 https://oidc.us-east-1.amazonaws.com/authorize?response_type=code&client_id=XXXXXXXXXXXXXXXXXXXXX...........
 Gtk-Message: 15:31:14.239: Not loading module "atk-bridge": The functionality is provided by GTK natively. Please try to not load it.
 Using the account ID 3XXXXXXX6542
 The only role available to you is: AdministratorAccess
 Using the role name "AdministratorAccess"
 Default client Region [None]:
 CLI default output format (json if not specified) [None]:
 To use this profile, specify the profile name using --profile, as shown:

## 2 - Testar 
 **aws sts get-caller-identity --profile Vulneri**
 
 {
    "UserId": "XXXXXXXXXXXXXXXXXXXXXX:email@vulneri.io",
    "Account": "3XXXXXXX6542",
    "Arn": "arn:aws:sts::3XXXXXXX6542:assumed-role/AWSReservedSSO_AdministratorAccess_234456678234fer7/email@vulneri.io"
  }

## 3 - Fazer login AWSCLI
 **/usr/local/bin/aws sso login --profile Vulneri**
 
 Attempting to automatically open the SSO authorization page in your default browser.
 If the browser does not open or you wish to use a different device to authorize this request, open the following URL:

 https://oidc.us-east-1.amazonaws.com/authorize?response_type=code&client_id=XXXXXXXXXXXXXXXXXXXXX...........
 Gtk-Message: 15:32:16.824: Not loading module "atk-bridge": The functionality is provided by GTK natively. Please try to not load it.
 Successfully logged into Start URL: https://d-9XXXXX6XX.awsapps.com/start



## 4 - Rodar o script para criar usuario e atribuir as permissoes
 **bash criar-usuario-vulneri.sh**
 
 [INFO] Iniciando criacao de usuario IAM com perfil 'Vulneri'...

 [INFO] Instalando dependencias: curl, unzip, jq, python3...

 [INFO] Verificando existencia do perfil 'Vulneri' no ~/.aws/config...


 [INFO] Verificando autenticacao com perfil 'Vulneri'...

 [INFO] Autenticacao bem-sucedida.

 [INFO] Criando usuario IAM 'ReadOnly-Key-To-Vulneri'...

 {
    "User": {
        "Path": "/",
        "UserName": "ReadOnly-Key-To-Vulneri",
        "UserId": "XXXXXXXXXXXXXXXXXXXXX",
        "Arn": "arn:aws:iam::3XXXXXXX6542:user/ReadOnly-Key-To-Vulneri",
        "CreateDate": "2025-07-15T18:36:01+00:00"
    }
 }

 [INFO] Usuario criado com sucesso.

 [INFO] Verificando numero de access keys...

 [INFO] Criando nova access key...

 [INFO] Access key salva no arquivo: ReadOnly-Key-To-Vulneri_accessKeys.csv

 [INFO] Anexando politica 'ReadOnlyAccess' ao usuario 'ReadOnly-Key-To-Vulneri'...

 [INFO] Anexando politica 'SecurityAudit' ao usuario 'ReadOnly-Key-To-Vulneri'...

 [INFO] Todas as politicas foram atribuidas com sucesso.

 [INFO] Script finalizado com sucesso.

 Envie o arquivo ReadOnly-Key-To-Vulneri_accessKeys.csv para security@vulneri.io


**Fim do README**
