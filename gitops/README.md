# gitops/

Instalação e configuração do ArgoCD **via Kustomize** (base remota + overlay de
config) e as Applications que ele gerencia.

```
gitops/
├── install/                       # instala + configura o ArgoCD (via Kustomize)
│   ├── kustomization.yaml         #   base REMOTA pinada (install.yaml oficial) + patches
│   ├── namespace.yaml
│   ├── repositories.yaml          #   Secret "repository" apontando p/ o repo Git
│   ├── argocd-cm.yaml             #   URL + contas de usuários (devops, viewer)
│   ├── argocd-rbac-cm.yaml        #   papéis e RBAC (gate de sync de produção)
│   └── argocd-cmd-params-cm.yaml  #   parâmetros dos componentes
├── apps/                          # o que o ArgoCD gerencia (aplicado após o install)
│   ├── kustomization.yaml
│   ├── appproject.yaml            #   AppProject (restringe repos/destinos)
│   ├── application-staging.yaml   #   sync AUTOMÁTICO -> cluster de staging
│   └── application-production.yaml#   sync MANUAL (aprovação) -> cluster de produção
└── Makefile                       # bootstrap em duas fases
```

## Como o ArgoCD é instalado (via Kustomize)

`install/kustomization.yaml` referencia o **manifesto oficial de instalação
como base remota, pinado por versão**:

```yaml
resources:
  - https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.5/manifests/install.yaml
```

O Kustomize **baixa** esse manifesto no momento do `build` e nós sobrepomos a
nossa configuração por cima, via `patches` (strategic merge) nos ConfigMaps que
já vêm no install (`argocd-cm`, `argocd-rbac-cm`, `argocd-cmd-params-cm`) e
adicionando o Secret de repositório. Vantagens:

- **Reprodutível**: a versão é fixa; atualizar o ArgoCD é bumpar a tag e revisar
  o diff (`make diff`).
- **Declarativo e versionado**: repositório, usuários e RBAC ficam em Git, não
  em cliques na UI.

## Configuração que já aponta para o repo e os usuários

- **Repositório** (`repositories.yaml`): Secret com a label
  `argocd.argoproj.io/secret-type: repository` e a `url` do repo. As Applications
  em `apps/` referenciam essa mesma `repoURL`.
- **Usuários** (`argocd-cm.yaml`): contas locais `devops` (login + API key) e
  `viewer` (login). O ideal em produção é **SSO/OIDC** (exemplo comentado no
  arquivo) e desabilitar contas locais.
- **RBAC** (`argocd-rbac-cm.yaml`): papéis `devops` (opera staging + gerencia
  Applications) e `prod-approver` (**único que pode dar Sync em produção**).
  Isso reforça o gate de produção também no controle de acesso.

> As **senhas** das contas não ficam no Git. Elas vão no Secret `argocd-secret`
> (hash bcrypt), aplicado fora do repositório. Gere o hash com:
> `argocd account bcrypt --password '<senha>'` e faça `kubectl patch secret
> argocd-secret -n argocd -p '{"stringData":{"accounts.devops.password":"<hash>"}}'`.

## Bootstrap

Pré-requisitos: `kubectl` apontando para o cluster + `kustomize`.

```bash
cd gitops
make bootstrap      # instala o ArgoCD (fase 1), espera subir, aplica as Apps (fase 2)
make password       # senha inicial do admin (para o primeiro login)
```

Por que **duas fases**? Os CRDs `Application`/`AppProject` são criados no
install; as Applications em `apps/` só podem ser aplicadas depois que esses CRDs
existem. O `Makefile` faz `install` → `rollout status` → `apps` nessa ordem.
(O install usa `kubectl apply --server-side` porque os CRDs do ArgoCD têm
anotações grandes demais para o apply client-side.)

Alternativa mais idiomática (não incluída para manter o exemplo enxuto):
**app-of-apps** — após o install, uma única "root Application" apontando para
`gitops/apps` faz o próprio ArgoCD gerenciar as demais Applications.

---

## Modelo de promoção (staging -> production)

A estratégia é **por diretório/overlay na mesma branch (`main`)**, não por
branch de longa duração:

- `manifests/overlays/staging` — estado desejado de staging.
- `manifests/overlays/production` — estado desejado de produção.

**Fluxo de promoção:**

1. Um merge em `app/` gera uma imagem nova e a pipeline atualiza a tag no overlay
   de **staging**. O ArgoCD de staging sincroniza **automaticamente**.
2. Validado em staging, abre-se um PR copiando a mesma tag (SHA) para o overlay
   de **production**. O PR é revisado/aprovado (code review).
3. Após o merge, o ArgoCD marca a Application de produção como `OutOfSync`. Um
   usuário com papel `prod-approver` aprova clicando em **Sync** — o gate humano.

### Por que overlay/diretório em vez de branch por ambiente?

- **Uma fonte da verdade**: o estado dos dois ambientes fica visível na mesma
  branch; a promoção é um PR simples e auditável.
- **Sem merges entre branches de ambiente**, que acumulam divergência.
- **Imagens imutáveis por SHA**: promover é mudar uma tag; o que foi testado em
  staging é bit-a-bit o que vai para produção.

## Automático em staging, manual em produção

- **Staging** (`apps/application-staging.yaml`): `syncPolicy.automated` com
  `prune` e `selfHeal`. Entrega contínua, sem intervenção.
- **Produção** (`apps/application-production.yaml`): **sem** bloco `automated`.
  O ArgoCD detecta o drift mas espera aprovação manual (`Sync`). Reforços extras:
  RBAC (`prod-approver`) e possibilidade de **Sync Windows** para restringir
  janelas de deploy.
