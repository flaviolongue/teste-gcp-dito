# Desafio DevOps — Dito

Infraestrutura de uma API interna que roda em Kubernetes, é entregue via CI/CD +
GitOps, acessa um Postgres gerenciado e tem seus segredos gerenciados de forma
segura — na GCP, com Terraform, ArgoCD e GitHub Actions.

> **Este ambiente foi realmente aplicado.** O desafio dizia que não era
> necessário rodar de verdade, mas eu subi tudo numa conta GCP real para validar
> o procedimento ponta a ponta. Isso revelou **7 problemas que nenhum
> `terraform validate` pegaria** — eles estão documentados em
> [Aprendizados](#-aprendizados-o-que-só-apareceu-aplicando-de-verdade), e são,
> honestamente, a parte mais interessante deste repositório.

---

## Índice

- [O que está rodando](#o-que-está-rodando)
- [Arquitetura](#arquitetura)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Como as camadas se conectam](#como-as-camadas-se-conectam)
- [Pré-requisitos](#pré-requisitos)
- [Como rodar](#como-rodar)
- [Decisões técnicas](#decisões-técnicas)
- [Segurança de segredos](#segurança-de-segredos)
- [GitOps: promoção staging → production](#gitops-promoção-staging--production)
- [CI/CD](#cicd)
- [Validação de manifests (abordagem recomendada)](#validação-de-manifests-abordagem-recomendada)
- [🔎 Aprendizados: o que só apareceu aplicando de verdade](#-aprendizados-o-que-só-apareceu-aplicando-de-verdade)
- [O que eu faria diferente / adicionaria com mais tempo](#o-que-eu-faria-diferente--adicionaria-com-mais-tempo)
- [Riscos e limitações conhecidos](#riscos-e-limitações-conhecidos)

---

## O que está rodando

Um ambiente `developer` completo, aplicado numa conta GCP real:

| Camada | O que subiu |
|---|---|
| **Infra** | VPC + subnet privada + Cloud NAT, GKE (nós privados), Cloud SQL Postgres com IP privado, Secret Manager, Artifact Registry, Workload Identity |
| **GitOps** | ArgoCD instalado **pelo Terraform**, que então gerencia tudo o mais via app-of-apps |
| **Rede** | Gateway API → Application Load Balancer do Google (**zero pods**), 1 IP roteando 2 hostnames |
| **Segredos** | Secret Manager → External Secrets Operator (via Workload Identity) → Secret K8s → env do Pod |
| **CI/CD** | GitHub Actions → **WIF keyless** → build/push no Artifact Registry → bump da tag → ArgoCD deploya |

Resultado final: `dito-api 2/2 Running`, as 4 Applications `Synced/Healthy`, e a
app respondendo `HTTP 200` através do Load Balancer.

## Arquitetura

```
                          GitHub (main)
   ┌───────────────┬───────────────────────┬────────────────────────┐
   │  iac/         │  app/                 │  manifests/ + gitops/  │
   │  (Terraform)  │  (Dockerfile/código)  │  (Kustomize)           │
   └──────┬────────┴───────────┬───────────┴───────────┬────────────┘
          │ workflow terraform  │ workflow app          │ (Git = fonte da verdade)
          ▼                     ▼                       ▼
   plan em PR /          build+push imagem        ArgoCD observa o repo
   apply em main         (Artifact Registry)      ├─ developer/staging: sync AUTOMÁTICO
   (prod = aprovação)    + bump da tag no          └─ production: sync MANUAL (aprovação)
                          overlay do ambiente
          │                                              │
          ▼                                              ▼
  ┌────────────────────────────────────────────────────────────────────┐
  │  GCP — um projeto por ambiente                                      │
  │                                                                     │
  │   Cloudflare ──► IP estático ──► Gateway (Application LB, gerenciado)│
  │                                    ├─ HTTPRoute [ns apps]   → app   │
  │                                    └─ HTTPRoute [ns argocd] → ArgoCD│
  │                                                                     │
  │   VPC ── subnet privada ── Cloud NAT                                │
  │    │                                                                │
  │    ├── GKE (nós privados, Workload Identity)                        │
  │    │     ├── ns apps    → Deployment (app + sidecar cloud-sql-proxy)│
  │    │     ├── ns argocd  → ArgoCD                                    │
  │    │     └── ns tools   → External Secrets Operator, Gateway        │
  │    │                                                                │
  │    ├── Cloud SQL Postgres (IP privado, HA em prod)                  │
  │    ├── Secret Manager ──(ESO via Workload Identity)──► Secret K8s   │
  │    └── Artifact Registry (imagens Docker)                           │
  └────────────────────────────────────────────────────────────────────┘
```

## Estrutura do repositório

```
.
├── iac/                          # Infraestrutura como Código (Terraform)
│   ├── bootstrap/                # cria o bucket GCS do state (roda 1x, backend local)
│   ├── modules/
│   │   ├── platform/             #   umbrella: compõe os MÓDULOS OFICIAIS do registry
│   │   ├── argocd/               #   aplica o Kustomize do ArgoCD (provider kustomization)
│   │   └── cicd/                 #   Workload Identity Federation p/ o GitHub Actions
│   └── environments/             # 2 camadas por ambiente, cada uma com state próprio
│       ├── developer/            #   Layer 1: infra (VPC, GKE, SQL...)
│       ├── developer-bootstrap/  #   Layer 2: ArgoCD naquele cluster
│       ├── staging/  staging-bootstrap/
│       └── production/  production-bootstrap/
├── app/                          # aplicação de exemplo + Dockerfile
├── manifests/                    # Kubernetes (Kustomize)
│   ├── base/                     #   a app: Deployment, Service, HPA, PDB, HTTPRoute...
│   ├── overlays/{developer,staging,production}/
│   └── platform/                 #   namespace tools, Gateway, HTTPRoute do ArgoCD
│       ├── base/  overlays/{developer,staging,production}/
├── gitops/                       # ArgoCD (app-of-apps por cluster)
│   ├── install/                  #   o ArgoCD em si (base remota oficial pinada + config)
│   ├── apps/base/                #   AppProjects + ESO (comum aos clusters)
│   ├── apps/{developer,staging,production}/   # base + a Application daquele ambiente
│   └── clusters/{developer,staging,production}/ # install + root app-of-apps ← Terraform aplica
└── .github/workflows/            # terraform.yml, app.yml
```

## Como as camadas se conectam

Esta é a parte que costuma confundir, então vale explicitar **quem chama quem**:

```
1. bootstrap/                  cria o bucket de state
        │
2. environments/<env>/         cria a infra (VPC, GKE, SQL, secrets, registry, WIF)
        │  outputs: gke_cluster_name, gke_location, gateway_ip...
        ▼
3. environments/<env>-bootstrap/   lê os outputs acima via terraform_remote_state,
        │                          e aplica gitops/clusters/<env> (ArgoCD + root app)
        ▼
4. ArgoCD (já rodando)         sincroniza gitops/apps/<env>, que declara:
        ├─ AppProjects                        (sync-wave -1)
        ├─ External Secrets Operator          (sync-wave  0)
        ├─ platform-<env> (Gateway/HTTPRoute) (sync-wave  0)
        └─ dito-api-<env> (a aplicação)       (sync-wave  1)
```

**Por que 2 stacks de Terraform por ambiente** (`<env>` e `<env>-bootstrap`)? Porque
a config do provider `kustomization` depende do cluster (endpoint, CA). No
Terraform, **a configuração de um provider não pode depender de algo criado no
mesmo apply** — daria `"Provider configuration depends on values that cannot be
determined until apply"`. Separando em camadas, quando a Layer 2 roda o cluster
já existe e o data source lê limpo. É o mesmo motivo pelo qual os blueprints de
produção separam "infra" de "cluster bootstrap".

Na prática você não decora a ordem: a pipeline (ou o Terragrunt) encadeia os
dois — `needs: infra` no CI, ou `dependency` no Terragrunt.

## Pré-requisitos

Para explorar e validar localmente (não precisa de conta GCP):

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.6
- [kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/) >= 5
- [Docker](https://docs.docker.com/get-docker/)

Para aplicar de verdade: `gcloud` autenticado (`gcloud auth application-default
login`), um projeto GCP com billing, e permissão de Owner.

## Como rodar

### Aplicação, local

```bash
docker build -t dito-internal-api:local ./app
docker run --rm -p 8080:8080 dito-internal-api:local
curl localhost:8080/healthz     # -> ok
```

### Validar o Terraform sem aplicar

```bash
terraform fmt -check -recursive iac
terraform -chdir=iac/environments/developer init -backend=false
terraform -chdir=iac/environments/developer validate
```

### Render dos manifests

```bash
kustomize build manifests/overlays/developer     # a app
kustomize build manifests/platform/overlays/developer  # Gateway + rota do ArgoCD
kustomize build gitops/clusters/developer        # ArgoCD + root app-of-apps
```

### Aplicar de verdade (a sequência completa)

```bash
# 0. Autenticar
gcloud auth login
gcloud config set project <SEU_PROJECT_ID>
gcloud auth application-default login

# 1. Bucket de state (uma vez)
terraform -chdir=iac/bootstrap init
terraform -chdir=iac/bootstrap apply \
  -var project_id=<SEU_PROJECT_ID> -var state_bucket_name=<NOME_UNICO_DO_BUCKET>

# 2. Layer 1 — infra
terraform -chdir=iac/environments/developer init -backend-config="bucket=<NOME_DO_BUCKET>"
terraform -chdir=iac/environments/developer apply

# 3. Layer 2 — ArgoCD (só depois que a Layer 1 terminou)
terraform -chdir=iac/environments/developer-bootstrap init -backend-config="bucket=<NOME_DO_BUCKET>"
terraform -chdir=iac/environments/developer-bootstrap apply

# 4. A app: nada de Terraform — o ArgoCD sincroniza do Git
kubectl -n argocd get applications
```

Depois do passo 2, `terraform output gateway_ip` te dá o IP para apontar no DNS.
Depois do passo 3, a senha inicial do ArgoCD:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

---

## Decisões técnicas

Onde havia mais de uma opção válida, registrei o porquê.

### Cloud: **GCP**
O ambiente interno da Dito é majoritariamente GCP. Região
**`southamerica-east1`** (São Paulo) por latência.

### Kubernetes gerenciado: **GKE**
Alinhamento com a stack da Dito e integração nativa com o resto (Workload
Identity ↔ Secret Manager ↔ Cloud SQL). **Standard** em vez de Autopilot para ter
controle explícito de node pool, tamanho de máquina e autoscaling — o desafio
pede decisões de escalabilidade/disponibilidade. Em `staging`/`production` o
cluster é **regional** (control plane e nós em 3 zonas, atende o requisito de
*multi zone*); em `developer` é **zonal** por custo.

### Terraform: **módulos oficiais + umbrella + wrappers por ambiente**
A escolha central foi **usar os módulos oficiais do registry** (mantidos por
Google/HashiCorp) em vez de escrever os recursos na mão. É o que se faz em
produção: testados em escala, defaults seguros, muito menos código para manter.

| Recurso | Módulo oficial | Versão |
|---|---|---|
| VPC + subnet + ranges secundários | `terraform-google-modules/network/google` | ~> 9.3 |
| Cloud NAT + Router | `terraform-google-modules/cloud-nat/google` | ~> 5.3 |
| GKE privado | `terraform-google-modules/kubernetes-engine/google//modules/private-cluster` | ~> 30.3 |
| Workload Identity (GSA + binding) | `.../kubernetes-engine/google//modules/workload-identity` | ~> 30.3 |
| Private Service Access (peering) | `GoogleCloudPlatform/sql-db/google//modules/private_service_access` | ~> 20.0 |
| Cloud SQL Postgres | `GoogleCloudPlatform/sql-db/google//modules/postgresql` | ~> 20.0 |
| Secret Manager | `GoogleCloudPlatform/secret-manager/google` | ~> 0.9 |
| Artifact Registry | `GoogleCloudPlatform/artifact-registry/google` | ~> 0.8 |
| WIF para GitHub Actions | `terraform-google-modules/github-actions-runners/google//modules/gh-oidc` | ~> 3.1 |
| Kustomize dentro do Terraform | provider `kbst/kustomization` | ~> 0.9 |

Sobre eles, duas camadas próprias e finas: `modules/platform` (umbrella que faz a
fiação) e `environments/*` (wrappers que só passam variáveis e definem o state).
Uns poucos recursos crus aparecem onde o módulo não cobre bem — por exemplo
`google_secret_manager_secret_iam_member`, para acesso **granular por secret**.

> O `bootstrap/` (bucket de state) é mantido com recurso cru de propósito: roda
> **antes** de tudo, com backend local, e não deve depender de download de
> módulos do registry.

#### Modelo de projetos e state

O **alvo de produção** é o padrão do blueprint oficial do Google
(`terraform-example-foundation`): **um projeto GCP por ambiente** (isolamento de
IAM, billing, quota e org policies) e um **projeto "seed"/automação** que hospeda
o **bucket de state central** (nome neutro) e o WIF/CI, com o state dos ambientes
separado por `prefix`.

```
prj-seed          -> bucket de state (prefixes: developer/ staging/ production/) + WIF/CI
dito-app-dev      -> workloads de dev
dito-app-staging  -> workloads de staging
dito-app-prod     -> workloads de produção
```

Neste desafio, o ambiente `developer` roda num único projeto por pragmatismo
(validar a esteira sem pagar 3× a infra), mas o bucket de state já usa **nome
neutro**, não acoplado a nenhum workload — pronto para virar o seed do modelo
acima.

### Namespaces: **`apps` / `argocd` / `tools`**

| Namespace | O que roda |
|---|---|
| `apps` | as aplicações (Deployment, Service, KSA, ExternalSecret, HTTPRoute) |
| `argocd` | o ArgoCD |
| `tools` | ferramentas de cluster (External Secrets Operator, Gateway) |

O namespace da app **não** carrega o nome do ambiente: como o modelo é **um
cluster por ambiente**, o próprio cluster já define o ambiente — repetir isso no
namespace seria redundante. O mesmo manifesto vale em qualquer cluster; o que
muda é o overlay (imagem, projeto, secrets, hostname).

### Exposição: **Gateway API** (Application LB do Google)

Comparando com a AWS, para não haver confusão:

| AWS | GCP equivalente |
|---|---|
| **ALB** (L7, roteia por host/path) | **Application Load Balancer** (o antigo "HTTP(S) LB") |
| aws-load-balancer-controller | **nativo do GKE** — não se instala nada |
| ACM (cert gerenciado) | Google-managed SSL certificate |
| ingress-nginx | ≈ NLB + nginx **nos seus pods** — *não* é o ALB |

Escolhi **Gateway API** e não Ingress por um motivo concreto: um `Ingress` é
**por namespace**, então não consegue rotear para `apps` **e** `argocd` no mesmo
LB — daria 2 LBs e 2 IPs. Na AWS isso se resolve com `IngressGroup`; a GCP não
tem equivalente, e a resposta nativa é o Gateway API: **um `Gateway` (1 LB, 1 IP)
com `HTTPRoute`s de vários namespaces se anexando a ele** (via
`allowedRoutes.namespaces.from: All`).

**Não sobe nenhum pod**: o controller do Gateway roda no control plane do GKE
(basta a flag `gateway_api_channel` no cluster) e o tráfego vai do LB **direto
para os Pods** via NEG.

Cada `HTTPRoute` fica **no namespace do seu Service** (`apps` e `argocd`), para o
`backendRef` ser local — `backendRef` cross-namespace exigiria `ReferenceGrant`.

### Banco: **Cloud SQL Postgres com IP privado + Cloud SQL Auth Proxy**
- **IP privado** via Private Service Access: o banco nunca é exposto à internet.
- Acesso a partir do Pod por **sidecar `cloud-sql-auth-proxy`**, que autentica
  via IAM/Workload Identity e cria um túnel TLS. A aplicação conecta em
  `127.0.0.1:5432` sem conhecer IP nem gerenciar certificado.
- **HA (`REGIONAL`) só em produção**; developer/staging ficam `ZONAL`.

### GitOps: **ArgoCD, app-of-apps por cluster**
**ArgoCD** (vs FluxCD) pela UI/RBAC madura, que atende bem o requisito de
**aprovação manual em produção**. Modelo **um ArgoCD por cluster**: cada cluster
registra só as Applications do seu ambiente (detalhes em
[`gitops/README.md`](gitops/README.md)).

### CI/CD: **GitHub Actions + Workload Identity Federation (keyless)**
Autenticação no GCP **sem chave JSON**: o runner troca um token OIDC do GitHub
por credenciais de curta duração. Elimina a classe inteira de incidentes de
"chave de service account vazada".

---

## Segurança de segredos

Camadas, do provider até o Pod — **e isto foi validado rodando**:

1. **Fonte da verdade: GCP Secret Manager.** O Terraform cria os secrets e
   concede leitura **por secret** (não em escopo de projeto) apenas à SA do
   workload.
2. A **senha do banco** é gerada por `random_password` e gravada no Secret
   Manager; nunca aparece em código. Secrets de aplicação entram com placeholder
   e são populados fora do Terraform.
3. **Do Secret Manager para o cluster:** o **External Secrets Operator** lê o
   Secret Manager usando a própria **Workload Identity** (sem chave) e materializa
   um `Secret` nativo do Kubernetes.
4. **Do Secret para o Pod:** variáveis sensíveis (`DB_PASSWORD`, `APP_API_KEY`)
   vêm do Secret; as não-sensíveis, de um `ConfigMap`.
5. **Segredos da pipeline:** WIF — nada de credencial de longa duração.

Verificação real no cluster:
```
kubectl -n apps get secret dito-api-secrets -o jsonpath='{.data}'
→ chaves: ['APP_API_KEY', 'DB_PASSWORD']     # vindas do Secret Manager, sem nenhuma chave
```

---

## GitOps: promoção staging → production

- **Estratégia:** overlays por diretório na branch `main`, não branch por
  ambiente. Uma fonte da verdade; promoção = um PR que copia a tag (SHA) de
  staging para produção — diff pequeno e auditável.
- **developer/staging = automático:** `syncPolicy.automated` (prune + selfHeal).
- **Production = manual:** Application **sem** `automated`. O ArgoCD detecta o
  drift e espera um **Sync** aprovado. Reforçado no **RBAC**: só o papel
  `prod-approver` pode sincronizar produção (`gitops/install/argocd-rbac-cm.yaml`).

---

## CI/CD

São dois workflows, e ambos foram **exercitados de verdade** neste repositório
(ver os runs em Actions e os PRs #1/#2).

### Autenticação: Workload Identity Federation (keyless)

Nenhum dos workflows usa chave JSON. O GitHub emite um token OIDC e a GCP o
troca por credenciais de curta duração, impersonando uma Service Account. O
provider OIDC tem `attribute_condition = "assertion.repository ==
'<owner/repo>'"`, então **só workflows deste repositório** conseguem assumir as
SAs. Há duas SAs, com papéis distintos:

| SA | Usada por | Permissão |
|---|---|---|
| `<env>-gh-actions` | `app.yml` (build/push) | **só** `artifactregistry.writer` no repo de imagens |
| `<env>-tf` | `terraform.yml` (plan/apply) | ampla (marcada `TEST-ONLY` como `owner`; curar em produção) |

Configuração no GitHub (feita uma vez, com valores vindos de `terraform output`):
`WIF_PROVIDER`, `TF_SERVICE_ACCOUNT`, `APP_DEPLOYER_SERVICE_ACCOUNT` (secrets) e
`ARTIFACT_REGISTRY`, `TF_STATE_BUCKET` (variables).

### `terraform.yml` — infraestrutura (dispara em `iac/**`)

**Matrix dinâmico por path.** Um job `changes` roda um `git diff` e decide quais
ambientes são afetados, para não rodar os três à toa:

| Mudou | Roda |
|---|---|
| `iac/modules/**` ou `iac/bootstrap/**` (compartilhado) | **os 3 ambientes** |
| `iac/environments/developer/**` | **só developer** |
| `iac/environments/staging/**` | **só staging** |

**Fluxo de uso (o dia a dia):**

1. Você abre um **PR** com uma mudança em `iac/`. O job `plan` roda `fmt` +
   `validate` nos ambientes afetados e **comenta o resumo do plan no PR**
   (ex.: `Plan: 0 to add, 4 to change, 0 to destroy`). **Não aplica nada.**
2. Revisa o plan no PR e faz **merge para `main`**.
3. O job `apply` roda nos ambientes afetados:
   - **developer** → aplica automaticamente;
   - **production** → o job entra em **`waiting`** e só prossegue após
     **aprovação manual** (GitHub Environment `production` com *required
     reviewers*). É esse Environment — não um passo no YAML — que implementa o
     gate obrigatório antes do apply em produção;
   - **staging** → aqui também gated (só para o teste não tentar aplicar num
     projeto inexistente); num cenário multi-projeto real seria automático.

> **Validado:** o PR #1 (mudança em `environments/developer/`) rodou só o
> developer e aplicou; um merge que tocou `modules/` expandiu o matrix para os 3
> e production ficou aguardando aprovação.

### `app.yml` — aplicação (dispara em `app/**`)

**Fluxo de uso:**

1. **Em PR:** build da imagem (validação, sem push).
2. **Em merge para `main`:** autentica via WIF → build + push no Artifact
   Registry com **tag imutável (SHA curto**, nunca `:latest`) → `kustomize edit
   set image` no overlay do ambiente → **commit** da nova tag.
3. Esse commit é o gatilho do **ArgoCD**, que faz o deploy — fecha o loop GitOps.

O commit da tag usa o `GITHUB_TOKEN` padrão (sem PAT); commits feitos com ele
não disparam workflows, evitando loop.

> **Validado:** um push em `app/` buildou, deu push da imagem, atualizou o
> overlay e o ArgoCD subiu a nova versão sozinho.

### Como um novo ambiente entra no pipeline

Nada muda no YAML — é só criar `iac/environments/<env>/` e o Environment
correspondente no GitHub (com ou sem required reviewers). O matrix dinâmico
passa a considerá-lo automaticamente quando arquivos dele mudarem.

---

## Validação de manifests (abordagem recomendada)

> O desafio pede para **descrever**, não implementar.

Workflow em PRs que tocam `manifests/**`, do mais barato ao mais caro:

1. **Render determinístico** — `kustomize build` de cada overlay. Falha cedo.
2. **Schema contra a API** — [`kubeconform`](https://github.com/yannh/kubeconform)
   `-strict` com schemas de CRDs (Gateway API, ExternalSecret, ArgoCD).
3. **Policy-as-code** — [`conftest`/OPA](https://www.conftest.dev/) ou Kyverno:
   "todo container tem limits", "`runAsNonRoot: true`", "proibido `:latest` em
   produção", "imagem só do nosso Artifact Registry".
4. **Boas práticas** — [`kube-linter`](https://docs.kubelinter.io/) /
   `kube-score` para anti-padrões.
5. **Diff de GitOps** — `argocd app diff` contra o cluster, mostrando no PR o que
   muda antes do merge.

(1)–(4) como *required checks*; nenhum precisa de acesso ao cluster.

---

## 🔎 Aprendizados: o que só apareceu aplicando de verdade

Esta seção é o coração do repositório. **Nenhum destes 7 problemas é pego por
`terraform validate` ou `kustomize build`** — todos apareceram no apply real, e
cada um virou uma correção no código.

### 1. Módulo oficial do Artifact Registry quebra o `plan` (`for_each` apply-time)
O módulo itera `for_each` sobre a **lista de membros** do IAM. Como o membro era
o e-mail de uma SA criada no mesmo apply, o valor só existe **depois** — e o
Terraform não consegue calcular as chaves do `for_each` no plan:
> `Invalid for_each argument … values derived from resource attributes that cannot be determined until apply`

**Correção:** não passar o membro pelo módulo; conceder o IAM com um **recurso
avulso** (`google_artifact_registry_repository_iam_member`). Um recurso único
aceita valor apply-time sem problema — o limite é só do `for_each`.

### 2. Race do Workload Identity: o pool não existe ainda
O binding de WI falhou no primeiro apply:
> `Error 400: Identity Pool does not exist (PROJECT.svc.id.goog)`

O pool `PROJECT.svc.id.goog` **só passa a existir depois** que um cluster com
Workload Identity é criado. O módulo referenciava só o *nome* do cluster (que é
conhecido cedo), então o binding rodou antes da hora.

**Correção:** `depends_on = [module.gke]` no módulo de workload-identity.

### 3. `--region` quebra em cluster zonal
O output `gke_get_credentials_command` usava `--region` fixo:
> `Could not find [dito-developer-gke] in [southamerica-east1]. Did you mean … in [southamerica-east1-a]?`

**Correção:** usar `--location` (que serve para regional **e** zonal) e tirá-lo do
output do módulo, não de uma variável.

### 4. Spot + nó único = indisponibilidade
Com um único nó Spot, a GCP preemptou a máquina e **todo o cluster ficou sem
capacidade** — vimos os pods de sistema em `NodeShutdown`. Ótimo para lote,
péssimo para um ambiente que precisa ficar de pé.

**Correção:** `developer` passou a usar nós **on-demand**. O knob `gke_spot`
continua no módulo para quem quiser.

### 5. Universal SSL da Cloudflare não cobre subdomínio de 2 níveis
`argocd-developer.dito.dev4cloud.online` dava `ERR_SSL_VERSION_OR_CIPHER_MISMATCH`.
Não era o GCP: o certificado **gratuito** da Cloudflare cobre só o apex e
`*.dev4cloud.online` — e **um curinga TLS casa um único label**. Dois níveis
(`…​.dito.dev4cloud.online`) ficam descobertos, e a Cloudflare não tinha cert para
apresentar:
```
openssl s_client … → sslv3 alert handshake failure / no peer certificate available
```

**Correção:** trocar o ponto por hífen — `argocd-developer-dito.dev4cloud.online`
(um nível, coberto). As alternativas seriam o Advanced Certificate Manager (pago)
ou um cert próprio.

### 6. Defaults do API server + ServerSideApply = `OutOfSync` eterno
A Application do Gateway ficava `OutOfSync` **mesmo depois de sincronizar**. O
motivo: o API server preenche defaults que o nosso manifesto omitia —
`parentRefs[].group/kind` e `backendRefs[].group/kind/weight`. Com
`ServerSideApply`, o ArgoCD compara campo a campo e enxerga diferença, mesmo o
objeto sendo funcionalmente idêntico.

**Correção:** declarar os defaults explicitamente, para o desejado bater com o
armazenado. (Alternativa: `ignoreDifferences`, mas isso esconde o problema.)

### 7. `readOnlyRootFilesystem` sem `/run`: o nginx não sobe
O container subia e morria:
> `[emerg] open() "/run/nginx.pid" failed (30: Read-only file system)`

Eu tinha montado `emptyDir` em `/var/cache/nginx` e `/tmp`, mas esqueci que o
nginx escreve o **PID em `/run/nginx.pid`** (diretiva do `nginx.conf` principal —
o arquivo que eu customizei é um *server block*, que não controla isso).

**Correção:** montar `emptyDir` em `/run` também.

### Meta-aprendizado
Os problemas 5, 6 e 7 **não eram de infraestrutura de nuvem** — eram de TLS,
de semântica de diff e de sistema de arquivos. Aplicar de verdade é o que
transforma "o código está correto" em "o sistema funciona".

---

## O que eu faria diferente / adicionaria com mais tempo

- **Scan de imagem no pipeline (Trivy)** — a base `nginx:1.27-alpine` acusa
  vulnerabilidades críticas/altas. Somaria assinatura (cosign) + verificação por
  admission controller.
- **TLS ponta a ponta** — hoje o listener do Gateway é HTTP e a Cloudflare termina
  o TLS (modo `Flexible`). Eu adicionaria um listener HTTPS com
  Google-managed certificate ou cert-manager, e passaria a Cloudflare para
  `Full (strict)`.
- **`terraform-docs` + pre-commit** (`fmt`, `validate`, `tflint`, `checkov`/`tfsec`).
- **Modelo multi-projeto de verdade** — projeto seed + um projeto por ambiente,
  com folders e org policies.
- **Observabilidade** — Managed Prometheus + Grafana, dashboards e alertas de SLO.
- **Progressive delivery** — Argo Rollouts (canary/blue-green) em produção.
- **DR testado** — restore do Cloud SQL ensaiado, não só backup configurado.
- **Testes de infra** — `terratest`/`terraform test` nos módulos.
- **Migrations de banco** — Job/initContainer versionado (a app de exemplo não tem).

## Riscos e limitações conhecidos

- **Valores de ambiente hard-coded nos overlays** (project IDs, e-mails de SA,
  connection names, IP name). Num cenário real eu geraria isso a partir dos
  outputs do Terraform (renderizando os overlays, ou via Config Connector) para
  eliminar divergência manual. Hoje, mudar de projeto exige editar overlay.
- **`master_authorized_networks` vazio** e **egress `0.0.0.0/0`** na
  NetworkPolicy: permissivo para o exemplo ser legível. Em produção, restringir o
  control plane às redes corporativas/CI e o egress aos CIDRs necessários.
- **Endpoint do control plane público** (`enable_private_endpoint = false`) para
  facilitar o acesso do CI. Hardening maior: endpoint privado + bastion/túnel, ou
  runners dentro da VPC.
- **TLS terminando na Cloudflare** (modo `Flexible`): a perna Cloudflare→origem
  vai em HTTP. Aceitável para teste, não para produção.
- **`developer` é zonal e single-node** por custo — não sobrevive à queda da zona.
  `staging`/`production` estão configurados como regionais, mas **não foram
  aplicados** (só validados).
- **staging/production nunca foram aplicados** — o código é o mesmo caminho que o
  developer exercitou de verdade, mas os gaps específicos deles (ex.: quota
  regional) só apareceriam aplicando.
- **Custo:** as configs de produção (GKE regional + Cloud SQL HA) têm custo
  relevante; os tiers são conservadores e devem ser ajustados à carga real.
