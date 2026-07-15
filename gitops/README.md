# gitops/

Configuração GitOps (ArgoCD) no modelo **app-of-apps por cluster**: cada cluster
tem seu próprio ArgoCD, que registra **apenas** as Applications daquele ambiente.

```
gitops/
├── install/                       # ArgoCD via Kustomize (base remota oficial pinada + config)
│   ├── kustomization.yaml         #   resources: install.yaml v3.4.5 + patches
│   ├── repositories.yaml          #   Secret "repository" apontando p/ o repo Git
│   ├── argocd-cm.yaml             #   URL + contas de usuários
│   ├── argocd-rbac-cm.yaml        #   papéis/RBAC (gate de sync de produção)
│   └── ...
├── apps/
│   ├── base/                      # comum a todo cluster (DRY)
│   │   ├── project.yaml           #   AppProject da app
│   │   ├── project-addons.yaml    #   AppProject dos add-ons
│   │   └── external-secrets.yaml  #   Application do ESO (Helm)
│   ├── developer/                 # base + Application da app (developer)
│   ├── staging/                   # base + Application da app (staging)
│   └── production/                # base + Application da app (production, sync manual)
└── clusters/
    ├── developer/                 # install + root app-of-apps  ← Terraform aplica este path
    ├── staging/
    └── production/
```

## Como o bootstrap acontece (via Terraform)

O bootstrap **não é manual** — quem instala o ArgoCD é o Terraform, no stack
`iac/environments/<env>-bootstrap`, usando o provider `kbst/kustomization` para
aplicar `gitops/clusters/<env>`. Esse path junta duas coisas:

1. **`install/`** — instala o ArgoCD (baixa a base oficial pinada + aplica a config).
2. **`root.yaml`** — o **root Application (app-of-apps)** daquele cluster, que
   aponta para `apps/<env>`.

A partir daí o ArgoCD assume: o root sincroniza `apps/<env>`, que contém os
AppProjects, o ESO e a Application da app — tudo com `sync-wave` para ordenar
(projects → ESO → app).

```bash
# o comando real é o do Terraform (ex.: developer):
terraform -chdir=iac/environments/developer-bootstrap apply
```

## Por que app-of-apps POR CLUSTER

Modelo escolhido: **um ArgoCD por cluster**. Cada cluster registra só o seu
ambiente. O `apps/developer` referencia apenas a Application `dito-api-developer`
— então o ArgoCD do cluster developer **nunca** tenta deployar os overlays de
staging/production. Isso evita conflito (todos os overlays miram o mesmo
namespace `dito-app`) e mantém o blast-radius por cluster.

A `base/` (AppProjects + ESO) é compartilhada via Kustomize entre os três
ambientes, evitando duplicação; só a Application da app muda por ambiente.

## Comandos úteis (após o ArgoCD subir)

```bash
# senha inicial do admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

# acessar a UI em https://localhost:8080
kubectl -n argocd port-forward svc/argocd-server 8080:443

# ver o estado das Applications
kubectl -n argocd get applications
```

> As contas/senhas nomeadas (não o admin) ficam no Secret `argocd-secret` com
> hash bcrypt, aplicado fora do Git. Gere com
> `argocd account bcrypt --password '<senha>'`. O ideal em produção é SSO/OIDC
> (exemplo comentado em `install/argocd-cm.yaml`) e desabilitar o admin local.

---

## Modelo de promoção (staging -> production)

Estratégia **por diretório/overlay na mesma branch (`main`)**, não por branch:

- `manifests/overlays/staging` — estado desejado de staging.
- `manifests/overlays/production` — estado desejado de produção.

**Fluxo:**

1. Merge em `app/` gera imagem nova; a pipeline atualiza a tag no overlay de
   **staging**. O ArgoCD de staging sincroniza **automaticamente**.
2. Validado, um PR copia a mesma tag (SHA) para o overlay de **production**.
3. Após o merge, a Application de produção fica `OutOfSync`. Um usuário com o
   papel `prod-approver` aprova o **Sync** — o gate humano.

## Automático em staging/developer, manual em produção

- **developer/staging** (`apps/*/app.yaml`): `syncPolicy.automated` (prune +
  selfHeal). Entrega contínua.
- **production** (`apps/production/app.yaml`): **sem** `automated`. O ArgoCD
  detecta o drift e espera aprovação manual. Reforço extra no RBAC
  (`prod-approver`) — ver `install/argocd-rbac-cm.yaml`.
