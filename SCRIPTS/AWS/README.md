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
1 - Configurar perfil AWSCLI - /usr/local/bin/aws configure sso --profile Vulneri
SSO session name (Recommended): Vulneri
SSO start URL [None]: https://d-9XXXXX6XX.awsapps.com/start
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

2 - Testar - aws sts get-caller-identity --profile Vulneri
aws sts get-caller-identity --profile Vulneri
{
   "UserId": "XXXXXXXXXXXXXXXXXXXXXX:email@vulneri.io",
   "Account": "3XXXXXXX6542",
   "Arn": "arn:aws:sts::3XXXXXXX6542:assumed-role/AWSReservedSSO_AdministratorAccess_234456678234fer7/email@vulneri.io"
}

3 - Fazer login AWSCLI - /usr/local/bin/aws sso login --profile Vulneri
Attempting to automatically open the SSO authorization page in your default browser.
If the browser does not open or you wish to use a different device to authorize this request, open the following URL:

https://oidc.us-east-1.amazonaws.com/authorize?response_type=code&client_id=XXXXXXXXXXXXXXXXXXXXX...........
Gtk-Message: 15:32:16.824: Not loading module "atk-bridge": The functionality is provided by GTK natively. Please try to not load it.
Successfully logged into Start URL: https://d-9XXXXX6XX.awsapps.com/start



4 - Rodar o script para criar usuario e atribuir as permissoes - bash criar-usuario-vulneri.sh
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
