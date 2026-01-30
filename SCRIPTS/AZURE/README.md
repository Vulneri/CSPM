# Azure Setup Tools (CSPM & FinOps)

Este repositório contém scripts de automação para facilitar a concessão de permissões de auditoria (Segurança e Operação Financeira) no ambiente **Microsoft Azure**.

O objetivo destes scripts é automatizar a criação de um **Service Principal** (identidade de aplicativo) e a atribuição dos papéis de leitura necessários em **todas as suas assinaturas (Subscriptions)** de forma centralizada.

## 🚀 O que estes scripts fazem?

Ao executar os scripts, os seguintes itens serão configurados automaticamente em seu tenant:

1.  **Criação de Service Principal:** Registra uma identidade segura para a integração com a plataforma Vulneri.
2.  **Configuração de Permissões de API (Microsoft Graph):**
    *   Leitura de diretório, faturamento e eventos de segurança no nível do tenant.
3.  **Atribuição de Papéis RBAC (Nível de Assinatura):**
    O script identifica todas as assinaturas ativas e atribui os seguintes papéis à aplicação:
    *   **Reader (Leitor):** Permite o inventário de recursos (VMs, Redes, Storage, etc).
    *   **Security Reader (Leitor de Segurança):** Permite a leitura de conformidade e recomendações do Microsoft Defender for Cloud.
    *   **Cost Management Reader:** Permite a análise de custos e faturamento da infraestrutura.
    *   **Billing Reader:** Permite a leitura de faturas e detalhes de faturamento.

---

## 💻 Como utilizar

Escolha o script de acordo com o seu sistema operacional:

### No Windows (PowerShell)
Recomendado abrir o PowerShell como **Administrador**.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; .\cspm_azure.ps1
```

### No Linux / macOS (Bash)
Certifique-se de ter o `jq` instalado e dar permissão de execução ao arquivo.

```bash
chmod +x cspm_azure.sh
./cspm_azure.sh
```

---

## 🛡️ Segurança e Transparência

*   **Visibilidade Multi-Assinatura:** O script facilita o trabalho ao aplicar as permissões em massa, garantindo que nenhuma subscrição fique fora da auditoria.
*   **Acesso Somente Leitura:** Todas as permissões concedidas são de leitura. O script não altera nenhuma configuração de recurso ou deleta dados.
*   **Controle Total:** Você pode revogar as credenciais ou deletar o Service Principal no portal do Azure a qualquer momento.

## 📦 Saída do Script

Ao final da execução, será gerado um arquivo chamado `vulneri_cspm_azure_env.txt`. Este arquivo contém as credenciais (`Client ID`, `Client Secret` e `Tenant ID`) que devem ser fornecidas para o início da consultoria.

---
> [!IMPORTANT]
> Para executar este script com sucesso, o usuário deve possuir o papel de **Owner** (Proprietário) ou **User Access Administrator** nas assinaturas, além de permissão para criar aplicativos no Entra ID.

