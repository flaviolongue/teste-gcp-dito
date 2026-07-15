# Desafio DevOps — Dito

Provisionamento da infraestrutura inicial de uma API interna que roda em
Kubernetes, é entregue via CI/CD + GitOps, acessa um Postgres gerenciado e tem
seus segredos gerenciados de forma segura.

> **Nota sobre execução:** o objetivo é qualidade e coerência do código, não a
> execução real. Não existe projeto GCP ativo por trás disto. Ainda assim, todo
> o Terraform passa em `fmt` + `validate` e os dois overlays Kustomize passam em
> `kustomize build` (ver seção [Validação](#validação-local)).

---

## Índice

- [Arquitetura em uma imagem](#arquitetura-em-uma-imagem)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Pré-requisitos](#pré-requisitos)
- [Como rodar localmente](#como-rodar-localmente)
- [Validação local](#validação-local)
- [Decisões técnicas](#decisões-técnicas)
- [Segurança de segredos](#segurança-de-segredos)
- [GitOps: promoção staging → production](#gitops-promoção-staging--production)
- [CI/CD](#cicd)
- [Validação de manifests (abordagem recomendada)](#validação-de-manifests-abordagem-recomendada)
- [O que eu faria diferente / adicionaria com mais tempo](#o-que-eu-faria-diferente--adicionaria-com-mais-tempo)
- [Riscos e limitações conhecidos](#riscos-e-limitações-conhecidos)

---

## Arquitetura em uma imagem

```
                          GitHub (main)
   ┌───────────────┬───────────────────────┬────────────────────────┐
   │  iac/         │  app/                 │  manifests/            │
   │  (Terraform)  │  (Dockerfile/código)  │  (Kustomize)           │
   └──────┬────────┴───────────┬───────────┴───────────┬────────────┘
          │ workflow terraform  │ workflow app          │ (Git = fonte da verdade)
          ▼                     ▼                       ▼
   plan em PR /          build+push imagem        ArgoCD observa o repo
   apply em main         (Artifact Registry)      ├─ staging: sync AUTOMÁTICO
   (prod = aprovação)    + bump da tag no          └─ production: sync MANUAL
                          overlay de staging          (aprovação humana)
          │                                              │
          ▼                                              ▼
  ┌────────────────────────────────────────────────────────────────┐
  │  GCP (projeto por ambiente: dito-staging / dito-production)     │
  │                                                                 │
  │   VPC ── subnet privada ── Cloud NAT                            │
  │    │                                                            │
  │    ├── GKE regional (multi-zona, nós privados, Workload Id.)    │
  │    │     └── Deployment (2+ réplicas espalhadas por zona)       │
  │    │           ├── container app (nginx)                        │
  │    │           └── sidecar cloud-sql-auth-proxy ──┐             │
  │    │                                              ▼             │
  │    ├── Cloud SQL Postgres (IP privado, HA em prod)              │
  │    ├── Secret Manager ──(External Secrets Operator)──► Secret K8s│
  │    └── Artifact Registry (imagens Docker)                       │
  └────────────────────────────────────────────────────────────────┘
```

## Estrutura do repositório

```
.
├── iac/                        # Infraestrutura como Código (Terraform)
│   ├── bootstrap/              # cria o bucket GCS do state remoto (roda 1x)
│   ├── modules/
│   │   └── platform/           #   umbrella: compõe os MÓDULOS OFICIAIS do registry
│   │                           #   (network, cloud-nat, kubernetes-engine, sql-db,
│   │                           #    secret-manager, artifact-registry, workload-identity)
│   └── environments/           # 1 diretório por ambiente (state isolado)
│       ├── staging/
│       └── production/
├── app/                        # aplicação de exemplo + Dockerfile
├── manifests/                  # Kubernetes (Kustomize base + overlays)
│   ├── base/
│   └── overlays/{staging,production}/
├── gitops/                     # ArgoCD instalado via Kustomize (install/) + Applications (apps/)
└── .github/workflows/          # pipelines (terraform.yml, app.yml)
```

## Pré-requisitos

Para explorar e validar localmente (não é preciso conta GCP):

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.6
- [kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/) >= 5
- [Docker](https://docs.docker.com/get-docker/) (para buildar a app)
- `kubectl`, `gcloud` e `python3`+`pyyaml` (opcionais, para checagens extras)

Para aplicar de verdade seriam necessários: dois projetos GCP
(`dito-staging`, `dito-production`), um Workload Identity Provider para o GitHub
Actions e um cluster com ArgoCD + External Secrets Operator instalados.

## Como rodar localmente

### 1. Aplicação

```bash
docker build -t dito-internal-api:local ./app
docker run --rm -p 8080:8080 dito-internal-api:local
curl localhost:8080/healthz     # -> ok
```

### 2. Terraform (validação sem aplicar)

```bash
cd iac
terraform fmt -check -recursive

# valida um ambiente sem precisar de credenciais nem backend
terraform -chdir=environments/staging init -backend=false
terraform -chdir=environments/staging validate
```

Fluxo real de aplicação (exigiria credenciais GCP):

```bash
# 0. uma única vez: cria o bucket do state remoto
terraform -chdir=iac/bootstrap init
terraform -chdir=iac/bootstrap apply -var project_id=dito-staging

# 1. inicializa o backend remoto apontando para o bucket criado
terraform -chdir=iac/environments/staging init \
  -backend-config="bucket=dito-staging-tfstate"

# 2. plan/apply
terraform -chdir=iac/environments/staging plan
terraform -chdir=iac/environments/staging apply
```

### 3. Manifests (render local)

```bash
kustomize build manifests/overlays/staging
kustomize build manifests/overlays/production
```

## Validação local

Tudo neste repositório foi verificado com:

| Verificação                        | Comando                                             | Resultado |
|-----------------------------------|-----------------------------------------------------|-----------|
| Formatação Terraform              | `terraform fmt -check -recursive`                   | ✅ ok     |
| Init (baixa os módulos oficiais)  | `terraform init` em staging e production            | ✅ ok     |
| Validação Terraform (2 ambientes) | `terraform validate` em staging e production        | ✅ ok     |
| Render Kustomize (app)            | `kustomize build overlays/{staging,production}`     | ✅ 11 recursos cada |
| Render Kustomize (ArgoCD install) | `kustomize build gitops/install`                    | ✅ 61 recursos |
| Sintaxe YAML (todos os arquivos)  | `yaml.safe_load_all`                                | ✅ ok     |

---

## Decisões técnicas

Onde havia mais de uma opção válida, registrei o porquê da escolha.

### Cloud: **GCP**
O ambiente interno da Dito é majoritariamente GCP. Ir de GCP reduz atrito
operacional e aproveita integrações nativas (Workload Identity ↔ GKE ↔ Secret
Manager). Região **`southamerica-east1`** (São Paulo) pela latência e por ser
uma empresa brasileira.

### Kubernetes gerenciado: **GKE Standard, regional**
- **GKE** em vez de EKS/AKS: alinhamento com a stack da Dito e melhor
  integração com o resto do GCP.
- **Regional** (control plane e nós em 3 zonas) em vez de zonal: atende
  diretamente o requisito de *multi zone* e sobrevive à queda de uma zona.
- **Standard** em vez de **Autopilot**: o desafio pede decisões explícitas de
  escalabilidade/disponibilidade (tamanho de nó, autoscaling, taints). Standard
  dá esse controle. Em um cenário onde o time quer menos operação, Autopilot
  seria uma troca válida — menos controle, menos toil.

### Estrutura Terraform: **módulos oficiais + umbrella + wrappers por ambiente**
A escolha central foi **usar os módulos oficiais do registry** (mantidos por
Google/HashiCorp) em vez de escrever os recursos na mão. É o que se faz em
produção: são testados em escala, trazem defaults seguros e reduzem MUITO a
quantidade de código para manter. Módulos usados:

| Recurso | Módulo oficial | Versão |
|---|---|---|
| VPC + subnet + ranges secundários | `terraform-google-modules/network/google` | ~> 9.3 |
| Cloud NAT + Router | `terraform-google-modules/cloud-nat/google` | ~> 5.3 |
| GKE regional privado | `terraform-google-modules/kubernetes-engine/google//modules/private-cluster` | ~> 30.3 |
| Workload Identity (GSA + binding) | `.../kubernetes-engine/google//modules/workload-identity` | ~> 30.3 |
| Private Service Access (peering) | `GoogleCloudPlatform/sql-db/google//modules/private_service_access` | ~> 20.0 |
| Cloud SQL Postgres | `GoogleCloudPlatform/sql-db/google//modules/postgresql` | ~> 20.0 |
| Secret Manager | `GoogleCloudPlatform/secret-manager/google` | ~> 0.9 |
| Artifact Registry | `GoogleCloudPlatform/artifact-registry/google` | ~> 0.8 |

Sobre eles, apenas duas camadas próprias e finas:
1. `modules/platform` — *umbrella* que compõe os módulos oficiais e faz a fiação
   entre eles (rede → GKE → SQL → secrets → registry), mais um punhado de
   recursos crus onde faz sentido (ex.: `google_secret_manager_secret_iam_member`
   para o acesso granular por secret).
2. `environments/{staging,production}` — wrappers finos que só passam variáveis e
   definem o backend/state.

Isso evita copiar/colar a fiação em cada ambiente: a lógica vive num lugar só e
o que muda entre ambientes fica pequeno (os tfvars). **State isolado por
ambiente** (um `prefix` por ambiente no mesmo bucket) reduz o raio de explosão.

> O `bootstrap/` (bucket de state) é mantido com recurso cru de propósito: ele
> roda **antes** de tudo, com backend local, e não deve depender de download de
> módulos do registry.

#### Modelo de projetos e state (alvo de produção vs. teste)

O **alvo de produção** é o padrão do blueprint oficial do Google
(`terraform-example-foundation`): **um projeto GCP por ambiente** (isolamento de
IAM, billing, quota e org policies) e um **projeto "seed"/automação dedicado**
que hospeda o **bucket de state central** (nome neutro, ex.: `dito-tfstate-*`),
com o state dos 3 ambientes separado por `prefix`. O CI roda com uma SA no seed
que **impersona** SAs de menor privilégio em cada projeto de ambiente.

```
prj-seed        -> bucket dito-tfstate-*  (prefixes: developer/ staging/ production/)  + WIF/CI
dito-app-dev    -> workloads de dev
dito-app-staging-> workloads de staging
dito-app-prod   -> workloads de produção
```

Neste desafio, o **ambiente `developer` de teste** roda num único projeto por
pragmatismo (validar a esteira sem pagar 3× a infra), mas o bucket de state já
usa **nome neutro** para não acoplar o state a um workload — pronto para virar o
seed do modelo acima.

### Banco: **Cloud SQL Postgres com IP privado + Cloud SQL Auth Proxy**
- **IP privado** (sem IP público) via Private Service Access: o banco nunca é
  exposto à internet.
- Acesso a partir do Pod por **sidecar `cloud-sql-auth-proxy`**, que autentica
  via IAM/Workload Identity e cria um túnel TLS. A aplicação conecta em
  `127.0.0.1:5432` sem conhecer IP nem gerenciar certificado. Alternativa
  seria conectar direto no IP privado — funciona, mas o proxy dá IAM + TLS de
  graça e é o padrão recomendado no GKE.
- **HA (`REGIONAL`) só em produção**; staging fica `ZONAL` para economizar.

### Segredos: **Secret Manager + External Secrets Operator (ESO)**
Ver seção dedicada abaixo. Em resumo: a fonte da verdade é o Secret Manager; o
ESO materializa um `Secret` do Kubernetes; o Pod consome como env. Nenhum
segredo em texto plano no Git.

### Namespaces: **`apps` / `argocd` / `tools`**

| Namespace | O que roda |
|---|---|
| `apps` | as aplicações (Deployment, Service, KSA, ExternalSecret) |
| `argocd` | o ArgoCD |
| `tools` | ferramentas de cluster (External Secrets Operator, etc.) |

O namespace da aplicação **não** carrega o nome do ambiente (não é
`developer`/`staging`/`production`): como o modelo é **um cluster por ambiente**,
o próprio cluster já define o ambiente — repetir isso no namespace seria
redundante e criaria complexidade sem ganho. O mesmo manifesto vale em qualquer
cluster; o que muda é o overlay (imagem, projeto, secrets).

### GitOps: **ArgoCD + overlays por diretório**
Escolhi **ArgoCD** (vs FluxCD) pela UI/RBAC madura para o requisito de
**aprovação manual em produção**, e **promoção por overlay/diretório** (vs
branch por ambiente) para ter uma única fonte da verdade e promoções auditáveis
por PR. Justificativa completa em [`gitops/README.md`](gitops/README.md).

### CI/CD: **GitHub Actions + Workload Identity Federation (keyless)**
Autenticação no GCP **sem chave JSON** — o runner troca um token OIDC do GitHub
por credenciais de curta duração. Elimina a classe inteira de incidentes de
"chave de service account vazada no repositório".

---

## Segurança de segredos

Camadas, do provider até o Pod:

1. **Fonte da verdade: GCP Secret Manager.** O Terraform cria os *containers*
   dos secrets e concede acesso de leitura **por secret** (não em escopo de
   projeto) apenas à Service Account do workload — menor privilégio.
2. **Senha do banco** é gerada por `random_password` e gravada no Secret
   Manager; ela nunca aparece em texto no código. Secrets de aplicação reais
   entram com valor *placeholder* e são populados fora do Terraform (via CI ou
   console), para não vazarem no state/código.
3. **Do Secret Manager para o cluster:** o **External Secrets Operator** lê o
   Secret Manager (usando a própria Workload Identity, sem chave) e materializa
   um `Secret` nativo do Kubernetes.
4. **Do Secret para o Pod:** o Deployment injeta as chaves sensíveis como
   variáveis de ambiente (`DB_PASSWORD`, `APP_API_KEY`), separadas das
   não-sensíveis, que vêm de um `ConfigMap`.
5. **Segredos da pipeline** (WIF provider, SA, PAT) ficam em *GitHub
   Environment secrets*, referenciados como `${{ secrets.* }}`. O uso de WIF
   evita credenciais de longa duração; nada é ecoado em log.

Resultado: **nenhum segredo em texto plano** no Git, nos manifests versionados
ou nos logs de pipeline.

---

## GitOps: promoção staging → production

Resumo (detalhes em [`gitops/README.md`](gitops/README.md)):

- **Estratégia:** overlays por diretório na branch `main`
  (`manifests/overlays/staging` e `.../production`), não branch por ambiente.
  Uma fonte da verdade, promoção = um PR que copia a tag (SHA) de staging para
  produção — diff pequeno e auditável.
- **Staging = automático:** `Application` com `syncPolicy.automated`
  (`prune` + `selfHeal`). Entrega contínua.
- **Production = manual:** `Application` **sem** `automated`. O ArgoCD detecta
  o drift e espera um **Sync** aprovado por um operador. Esse é o gate humano de
  produção.

---

## CI/CD

Dois workflows, disparados por caminho:

### `terraform.yml` (dispara em `iac/**`)
- **Em PR:** `fmt -check` → `init` → `validate` → `plan` para **staging e
  production** (matrix), com o resultado comentado no PR.
- **Em merge para `main`:** `apply`. Staging aplica direto; **production usa um
  GitHub Environment com *required reviewers*** — o job fica pendente até
  aprovação manual. É esse Environment que implementa o "aprovação manual
  obrigatória antes do apply em production".

### `app.yml` (dispara em `app/**`)
- **Em PR:** build da imagem (validação, sem push).
- **Em merge para `main`:** build + push para o Artifact Registry com tag
  imutável (SHA curto) e, em seguida, `kustomize edit set image` no overlay de
  **staging** + commit de volta no Git. Esse commit é o gatilho do ArgoCD de
  staging (fecha o loop GitOps).
- Os comandos de `docker push` podem ser simulados com `echo` caso não haja
  registry no ambiente de avaliação — a lógica da pipeline é idêntica.

Ambos usam **WIF (keyless)** e segredos via *Environment secrets* — nada
sensível vai para o log.

---

## Validação de manifests (abordagem recomendada)

> O desafio pede para **descrever**, não implementar, o workflow de validação
> da pasta `manifests/`.

Eu configuraria um workflow disparado em PRs que tocam `manifests/**`, com estes
estágios, do mais barato/rápido para o mais caro:

1. **Render determinístico** — `kustomize build overlays/staging` e
   `.../production`. Falha cedo se algum overlay/patch estiver quebrado. Todos
   os passos seguintes rodam sobre a saída renderizada.
2. **Validação de schema contra a API do Kubernetes** —
   [`kubeconform`](https://github.com/yannh/kubeconform) com `-strict` e schemas
   de CRDs (ExternalSecret, ArgoCD). Pega campos inválidos, typos de `apiVersion`
   e recursos malformados sem precisar de cluster.
3. **Políticas organizacionais (policy-as-code)** —
   [`conftest`/OPA](https://www.conftest.dev/) ou
   [`kyverno test`](https://kyverno.io/docs/kyverno-cli/): impõe regras como
   "todo container tem limits", "`runAsNonRoot: true`", "proibido `:latest` em
   produção", "imagem só do nosso Artifact Registry", "PDB obrigatório".
4. **Boas práticas / segurança** — [`kube-linter`](https://docs.kubelinter.io/)
   ou [`kube-score`](https://kube-score.com/) para achar anti-padrões
   (sem probes, sem anti-affinity, requests ausentes).
5. **Diff de GitOps (opcional, mais poderoso)** — `argocd app diff` contra o
   estado vivo do cluster para mostrar, no PR, exatamente o que vai mudar antes
   do merge.

Colocaria (1)–(4) como *required checks* de merge; nenhum deles precisa de
acesso ao cluster, então rodam rápido e sem credenciais sensíveis.

---

## O que eu faria diferente / adicionaria com mais tempo

- **`terraform-docs` + pre-commit hooks** (`fmt`, `validate`, `tflint`,
  `checkov`/`tfsec`) para padronizar e pegar problemas de segurança de IaC no
  commit.
- **Ambientes = projetos GCP separados** já está previsto; eu adicionaria uma
  camada de `folders`/org policies e um módulo de *project factory*.
- **Observabilidade:** Prometheus/Managed Prometheus + Grafana, dashboards e
  alertas (SLO de latência/erro), além de `PodMonitor` para a app.
- **Ingress + TLS gerenciado** caso o serviço precise de exposição controlada
  (hoje é `ClusterIP`, interno por requisito), com Gateway API + certificados.
- **DR e backups testados:** políticas de retenção do Cloud SQL com restore
  ensaiado; export do state; runbook de recuperação.
- **Progressive delivery:** Argo Rollouts (canary/blue-green) em vez de
  RollingUpdate puro em produção.
- **Segurança de supply chain:** assinatura de imagem (cosign) + verificação de
  assinatura por admission controller; scan de imagem (Trivy) no pipeline.
- **Restringir `master_authorized_networks` e egress** de fato (hoje deixei
  documentado/aberto por simplicidade — ver riscos abaixo).
- **Testes de infra:** `terraform plan` em PR já existe; eu somaria
  `terratest`/`terraform test` para os módulos.

## Riscos e limitações conhecidos

- **Valores de exemplo hard-coded nos overlays** (project IDs, e-mails de SA,
  connection names). Num cenário real eu geraria esses valores a partir dos
  *outputs* do Terraform (por exemplo, um passo que renderiza os overlays com os
  outputs, ou o Config Connector) para eliminar divergência manual.
- **`master_authorized_networks` vazio** e **egress `0.0.0.0/0`** na
  NetworkPolicy: deixei permissivo para o exemplo ser legível. Em produção o
  control plane deve ser restrito às redes corporativas/CI e o egress limitado
  aos CIDRs do Secret Manager/Cloud SQL.
- **Endpoint do control plane público** (`enable_private_endpoint = false`)
  para facilitar acesso do CI. Um hardening maior usaria endpoint privado +
  bastion/túnel ou runners dentro da VPC.
- **State remoto "simulado":** o backend GCS está configurado mas depende do
  bucket do bootstrap existir; nada é aplicado de verdade (conforme o desafio).
- **ArgoCD e ESO via GitOps:** o ArgoCD é instalado pelo Terraform (stack
  `iac/environments/<env>-bootstrap`, provider `kbst/kustomization`) a partir de
  `gitops/clusters/<env>`, que já registra o **root app-of-apps** do cluster. O
  **External Secrets Operator** é gerenciado pelo próprio ArgoCD (Application
  Helm em `gitops/apps/base`). Modelo: **um ArgoCD por cluster** — cada cluster
  registra apenas as Applications do seu ambiente.
- **Sem testes de aplicação real:** a app é um nginx de exemplo; a esteira é o
  foco. Migrations de banco (ex.: um Job/initContainer) não estão modeladas.
- **Custo:** as configs de produção (GKE regional + Cloud SQL HA) têm custo
  relevante; os tiers são conservadores e devem ser ajustados à carga real.
```
