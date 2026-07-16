# gitops/

GitOps com **ArgoCD**, no modelo **app-of-apps por cluster**: cada cluster tem o
seu próprio ArgoCD, que registra **apenas** as Applications do seu ambiente.

```
gitops/
├── install/                       # o ArgoCD em si (Kustomize)
│   ├── kustomization.yaml         #   base remota oficial pinada (install.yaml v3.4.5) + patches
│   ├── repositories.yaml          #   Secret "repository" apontando p/ o repo Git
│   ├── argocd-cm.yaml             #   URL + contas de usuários
│   ├── argocd-rbac-cm.yaml        #   papéis/RBAC (gate de sync de produção)
│   └── argocd-cmd-params-cm.yaml  #   server.insecure=true (TLS termina no LB/Cloudflare)
├── apps/
│   ├── base/                      # comum a todo cluster (compartilhado via Kustomize)
│   │   ├── project.yaml           #   AppProject da app
│   │   ├── project-addons.yaml    #   AppProject dos add-ons (ESO, plataforma)
│   │   └── external-secrets.yaml  #   Application do ESO (Helm) → namespace tools
│   ├── developer/                 # base + Application da app + Application da plataforma
│   ├── staging/
│   └── production/                # (a Application da app é sync MANUAL)
└── clusters/
    ├── developer/                 # install + root app-of-apps  ← o Terraform aplica ESTE path
    ├── staging/
    └── production/
```

## Quem instala o ArgoCD? O Terraform.

O bootstrap **não é manual**. Cada ambiente tem um stack
`iac/environments/<env>-bootstrap` que usa o provider `kbst/kustomization` para
aplicar `gitops/clusters/<env>`. Esse path junta:

1. **`install/`** — o ArgoCD (baixa a base oficial pinada + aplica a config);
2. **`root.yaml`** — o **root Application (app-of-apps)** daquele cluster,
   apontando para `apps/<env>`.

```bash
terraform -chdir=iac/environments/developer-bootstrap apply
```

Daí em diante o ArgoCD se auto-gerencia: o root sincroniza `apps/<env>`, que
declara os AppProjects, o ESO, a plataforma (Gateway) e a app — nessa ordem, via
`sync-wave`:

```
sync-wave -1 : AppProjects
sync-wave  0 : External Secrets Operator  +  platform-<env> (Gateway + HTTPRoutes)
sync-wave  1 : dito-api-<env> (a aplicação)
```

A ordem importa: o ESO instala os CRDs que a app usa (`ExternalSecret`), e o
Gateway precisa existir antes dos `HTTPRoute` da app se anexarem a ele.

## Por que app-of-apps POR CLUSTER

Modelo escolhido: **um ArgoCD por cluster**. Cada cluster registra só o seu
ambiente. `apps/developer` referencia apenas a Application `dito-api-developer` —
então o ArgoCD do cluster developer **nunca** tenta deployar os overlays de
staging/production (que mirariam o mesmo namespace `apps`, gerando conflito).

A `base/` (AppProjects + ESO) é compartilhada via Kustomize entre os três
ambientes, evitando duplicação; só a Application da app muda por ambiente.

> **Alternativa:** um ArgoCD **central** (hub) gerenciando os 3 clusters remotos,
> com ApplicationSet + cluster generator. Reaproveita mais, mas cria um ponto
> único e exige que o hub alcance todos os clusters. Para produção sensível, o
> "por cluster" isola melhor. Escolhemos o por cluster.

## Comandos úteis (após o ArgoCD subir)

```bash
# senha inicial do admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

# acesso local sem depender de DNS/LB
kubectl -n argocd port-forward svc/argocd-server 8080:80   # http://localhost:8080

# estado das Applications
kubectl -n argocd get applications
```

> Contas nomeadas (não o admin) ficam no Secret `argocd-secret` com hash bcrypt,
> aplicado fora do Git (`argocd account bcrypt --password '<senha>'`). O ideal em
> produção é SSO/OIDC (exemplo comentado em `install/argocd-cm.yaml`) e desabilitar
> o admin local.

---

## Modelo de promoção (staging → production)

Estratégia **por diretório/overlay na mesma branch (`main`)**, não por branch:

1. Merge em `app/` gera imagem nova; a pipeline atualiza a tag no overlay do
   ambiente. O ArgoCD (developer/staging) sincroniza **automaticamente**.
2. Validado, um PR copia a mesma tag (SHA) para o overlay de **production**.
3. Após o merge, a Application de produção fica `OutOfSync`. Um usuário com o
   papel `prod-approver` aprova o **Sync** — o gate humano.

**Automático em developer/staging, manual em produção:** as Applications de
developer/staging têm `syncPolicy.automated`; a de produção **não** — o ArgoCD
espera aprovação. Reforço no RBAC (`prod-approver`), em `install/argocd-rbac-cm.yaml`.
