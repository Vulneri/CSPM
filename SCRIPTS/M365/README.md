# Microsoft 365 Setup Tools (CSPM & FinOps)

Este repositório contém scripts de automação para facilitar a concessão de permissões de auditoria (Segurança e Operação Financeira) no ambiente **Microsoft 365**.

O objetivo destes scripts é automatizar a criação de uma aplicação no **Microsoft Entra ID** (antigo Azure AD) com os privilégios mínimos necessários para que a plataforma **Vulneri** possa realizar o inventário e a avaliação de segurança/custos do seu tenant.

## 🚀 O que estes scripts fazem?

Ao executar os scripts, os seguintes itens serão configurados automaticamente:

1.  **Criação de Aplicativo (Service Principal):** Registra uma aplicação segura para integração.
2.  **Configuração de Permissões de API (Microsoft Graph):**
    *   **Segurança:** Leitura de logs de auditoria, políticas de acesso condicional e eventos de segurança.
    *   **Identidade:** Inventário de usuários, grupos e papéis administrativos.
    *   **FinOps & Billing:** Acesso a detalhes de faturamento, faturas e licenciamento (SKUs).
3.  **Acesso a APIs Legadas:** Configuração do Office 365 Management API para leitura do Activity Feed (logs de atividade).
4.  **Atribuição de Papéis RBAC:** Adiciona a aplicação aos papéis de **Global Reader** (Leitor Global) e **Billing Reader** (Leitor de Faturamento) para visibilidade total sem permissão de escrita.

---

## 💻 Como utilizar

Escolha o script de acordo com o seu sistema operacional:

### No Windows (PowerShell)
Recomendado abrir o PowerShell como **Administrador**.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; .\capm_m365.ps1
```

### No Linux / macOS (Bash)
Certifique-se de dar permissão de execução ao arquivo.

```bash
chmod +x capm_m365.sh
./capm_m365.sh
```

---

## 🛡️ Segurança e Transparência

*   **Acesso Somente Leitura:** Os scripts configuram permissões de leitura (Read). Nenhuma alteração de configuração ou exclusão de dados é realizada no seu ambiente.
*   **Controle Total:** Você pode revogar o segredo gerado ou excluir a aplicação no portal do Microsoft Entra ID a qualquer momento.
*   **Validação de Licenciamento:** O script verifica automaticamente se o seu tenant possui licenças de segurança (como Azure AD P1/P2) para garantir que as auditorias avançadas funcionem corretamente.

## 📦 Saída do Script

Ao final da execução, será gerado um arquivo chamado `vulneri_cspm_m365_env.txt`. Este arquivo contém as credenciais (`Client ID`, `Client Secret` e `Tenant ID`) que deverão ser fornecidas para a plataforma de avaliação começar o trabalho.

---
> [!IMPORTANT]
> A conta utilizada para rodar os scripts deve possuir privilégios de **Global Administrator** ou **Privileged Role Administrator** para conceder o consentimento administrativo e atribuir os papéis de RBAC.

