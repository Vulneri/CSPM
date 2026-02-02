# AWS Setup Tools (CSPM & FinOps)

Este repositório contém scripts de automação para facilitar a concessão de permissões de auditoria (Segurança e Operação Financeira) no ambiente **Amazon Web Services (AWS)**.

O diferencial destes scripts é o suporte nativo ao **AWS IAM Identity Center (SSO)**, guiando o usuário passo a passo através do portal de acesso para configurar uma integração segura e profissional.

## 🚀 O que estes scripts fazem?

Ao executar os scripts, os seguintes itens serão configurados automaticamente em sua conta:

1.  **Configuração de Perfil SSO:** Orienta a coleta da Start URL e Account ID, realizando o login seguro via navegador.
2.  **Criação de Usuário IAM Técnico:** Cria o usuário `Vulneri-RO-Key` para acesso programático.
3.  **Atribuição da Política Unificada (Vulneri-CSPM-FinOps-Policy):**
    *   **Inventário Completo (CSPM):** Leitura de EC2, RDS, S3, IAM, Organizations, Bedrock, Backup, etc.
    *   **Análise Financeira (FinOps):** Acesso ao Cost Explorer (`ce:*`), Cost and Usage Reports (`cur:*`) e Budgets.
4.  **Políticas Gerenciadas AWS:** Anexa `ReadOnlyAccess` e `SecurityAudit` para cobertura total.
5.  **Geração de Chaves de Acesso:** Cria as chaves permanentes necessárias para a plataforma Vulneri.

---

## 💻 Como utilizar

Escolha o script de acordo com o seu sistema operacional. Certifique-se de estar logado com uma conta com permissões de **Administrador**.

### No Windows (PowerShell)
Abra o PowerShell como **Administrador** para permitir a instalação automática de dependências (se necessário).

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; .\aws22.ps1
```

### No Linux / macOS (Bash)
Certifique-se de ter o `jq` instalado e dar permissão de execução ao arquivo.

```bash
chmod +x aws22.sh
./aws22.sh
```

---

## 🛡️ Segurança e Transparência

*   **Identidade Center (SSO):** O script utiliza o fluxo oficial de login da AWS, nunca solicitando ou armazenando suas senhas pessoais.
*   **Acesso Somente Leitura:** Todas as permissões são de auditoria e leitura.
*   **Blindagem de Dados Sensíveis:** A política customizada possui um bloco `Deny` explícito para `s3:GetObject` e `SecretsManager`, garantindo que a Vulneri **não consiga ler** o conteúdo dos seus arquivos ou segredos.
*   **Controle Total:** O acesso é feito via um usuário IAM dedicado que pode ser desativado ou deletado por você a qualquer momento.

## 📦 Saída do Script

Ao final, será gerado o arquivo `vulneri_credentials.env`. Ele contém a `Access Key`, `Secret Key` e a `Região` que devem ser fornecidas para a plataforma da Vulneri.

---
> [!IMPORTANT]
> Para o sucesso da configuração, é necessário ter em mãos a **URL do Portal de Acesso AWS** e o **ID de 12 dígitos** da conta onde a auditoria será realizada.
