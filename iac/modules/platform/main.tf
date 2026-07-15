# ---------------------------------------------------------------------------
# Módulo: platform (umbrella)
# Compõe a plataforma usando os MÓDULOS OFICIAIS do registry (mantidos pelo
# Google/HashiCorp). Cada ambiente (staging/production) instancia este módulo
# com suas variáveis e seu próprio state.
# ---------------------------------------------------------------------------

locals {
  name_prefix = "dito-${var.environment}"
  subnet_name = "dito-${var.environment}-private"
}

# Habilita as APIs necessárias no projeto.
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# --- Rede: VPC + subnet privada (ranges secundários p/ pods e services) ------
module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 9.3"

  project_id   = var.project_id
  network_name = "${local.name_prefix}-vpc"
  routing_mode = "REGIONAL"

  subnets = [{
    subnet_name           = local.subnet_name
    subnet_ip             = var.subnet_cidr
    subnet_region         = var.region
    subnet_private_access = "true"
    subnet_flow_logs      = "true"
  }]

  secondary_ranges = {
    (local.subnet_name) = [
      { range_name = "pods", ip_cidr_range = var.pods_cidr },
      { range_name = "services", ip_cidr_range = var.services_cidr },
    ]
  }

  depends_on = [google_project_service.apis]
}

# --- NAT: saída de internet para os nós privados ----------------------------
module "cloud_nat" {
  source  = "terraform-google-modules/cloud-nat/google"
  version = "~> 5.3"

  project_id    = var.project_id
  region        = var.region
  name          = "${local.name_prefix}-nat"
  router        = "${local.name_prefix}-router"
  network       = module.vpc.network_self_link
  create_router = true
}

# --- GKE regional (multi-zona), nós privados, Workload Identity --------------
module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  version = "~> 30.3"

  project_id = var.project_id
  name       = "${local.name_prefix}-gke"
  region     = var.region
  regional   = var.gke_regional # true = 3 zonas (prod); false = zonal (barato).
  zones      = var.gke_zones

  network           = module.vpc.network_name
  subnetwork        = local.subnet_name
  ip_range_pods     = "pods"
  ip_range_services = "services"

  enable_private_nodes       = true
  enable_private_endpoint    = false
  master_ipv4_cidr_block     = var.master_ipv4_cidr
  master_authorized_networks = var.master_authorized_networks

  release_channel          = "REGULAR"
  deletion_protection      = var.deletion_protection
  remove_default_node_pool = true

  # Gateway API gerenciado: o Google instala os CRDs e reconcilia Gateway/
  # HTTPRoute no control plane, provisionando um Application Load Balancer.
  # Não sobe nenhum pod de controller no cluster.
  gateway_api_channel = var.gateway_api_channel

  node_pools = [{
    name         = "primary"
    machine_type = var.gke_machine_type
    min_count    = var.gke_min_nodes_per_zone
    max_count    = var.gke_max_nodes_per_zone
    disk_size_gb = 50
    disk_type    = "pd-standard"
    spot         = var.gke_spot
    auto_repair  = true
    auto_upgrade = true
  }]

  node_pools_oauth_scopes = {
    all = ["https://www.googleapis.com/auth/cloud-platform"]
  }
  node_pools_labels = {
    all = { env = var.environment }
  }
}

# --- IP estático do Gateway (Application LB) --------------------------------
# IP GLOBAL porque o gatewayClass gke-l7-global-external-managed provisiona um
# Application LB global. É este IP que recebe o A record no DNS (Cloudflare).
# O Gateway referencia o IP pelo NOME (NamedAddress), não pelo valor.
resource "google_compute_global_address" "gateway" {
  count        = var.create_gateway_ip ? 1 : 0
  name         = "${local.name_prefix}-gateway-ip"
  project      = var.project_id
  address_type = "EXTERNAL"

  depends_on = [google_project_service.apis]
}

# --- Workload Identity: GSA da app + binding com a KSA (sem chave) -----------
# A KSA é criada pelo Kustomize (manifests/), então aqui só criamos a GSA e o
# binding (annotate_k8s_sa = false evita depender do provider kubernetes).
module "workload_identity" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version = "~> 30.3"

  project_id          = var.project_id
  name                = "${local.name_prefix}-app"
  cluster_name        = module.gke.name
  location            = var.region
  namespace           = var.k8s_namespace
  k8s_sa_name         = var.k8s_service_account
  use_existing_k8s_sa = true
  annotate_k8s_sa     = false

  # roles/cloudsql.client não é por-recurso; fica no nível de projeto.
  roles = ["roles/cloudsql.client"]

  # O binding de Workload Identity precisa do Identity Pool, que só existe
  # depois que o cluster (com WI habilitado) termina de ser criado. Sem este
  # depends_on, o binding roda cedo demais e falha com "Identity Pool does not
  # exist".
  depends_on = [module.gke]
}

# --- Private Service Access: peering para o Cloud SQL com IP privado ---------
module "private_service_access" {
  source  = "GoogleCloudPlatform/sql-db/google//modules/private_service_access"
  version = "~> 20.0"

  project_id  = var.project_id
  vpc_network = module.vpc.network_name

  depends_on = [google_project_service.apis]
}

# --- Senha do banco: gerada e guardada no Secret Manager --------------------
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%*-_=+"
}

# --- Cloud SQL Postgres com IP privado --------------------------------------
module "postgres" {
  source  = "GoogleCloudPlatform/sql-db/google//modules/postgresql"
  version = "~> 20.0"

  project_id       = var.project_id
  name             = "${local.name_prefix}-pg"
  database_version = "POSTGRES_15"
  region           = var.region
  zone             = "${var.region}-a"

  tier                = var.db_tier
  availability_type   = var.db_availability_type
  disk_size           = var.db_disk_size
  disk_autoresize     = true
  deletion_protection = var.deletion_protection

  ip_configuration = {
    ipv4_enabled                                  = false
    private_network                               = module.vpc.network_self_link
    allocated_ip_range                            = module.private_service_access.google_compute_global_address_name
    ssl_mode                                      = "ENCRYPTED_ONLY"
    authorized_networks                           = []
    enable_private_path_for_google_cloud_services = true
  }

  db_name       = "app"
  user_name     = "app"
  user_password = random_password.db.result

  module_depends_on = [module.private_service_access.peering_completed]
}

# --- Secret Manager: cria os secrets e versões ------------------------------
module "secret_manager" {
  source  = "GoogleCloudPlatform/secret-manager/google"
  version = "~> 0.9"

  project_id = var.project_id
  secrets = [
    {
      name                  = "${local.name_prefix}-db-password"
      automatic_replication = true
      secret_data           = random_password.db.result
    },
    {
      name                  = "${local.name_prefix}-app-api-key"
      automatic_replication = true
      secret_data           = var.app_api_key_placeholder
    },
  ]

  depends_on = [google_project_service.apis]
}

# Acesso de leitura aos secrets APENAS para a GSA do workload (menor privilégio,
# concedido por secret e não no projeto inteiro).
resource "google_secret_manager_secret_iam_member" "accessors" {
  for_each = toset([
    "${local.name_prefix}-db-password",
    "${local.name_prefix}-app-api-key",
  ])
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.workload_identity.gcp_service_account_email}"

  depends_on = [module.secret_manager]
}

# --- Artifact Registry: repositório Docker ----------------------------------
module "artifact_registry" {
  source  = "GoogleCloudPlatform/artifact-registry/google"
  version = "~> 0.8"

  project_id    = var.project_id
  location      = var.region
  repository_id = "${local.name_prefix}-docker"
  format        = "DOCKER"
  description   = "Imagens Docker da aplicação (${var.environment})."

  depends_on = [google_project_service.apis]
}

# Leitura das imagens pela SA dos nós. Feito como recurso avulso (e não via
# `members` do módulo) porque o módulo usa for_each sobre o e-mail da SA, que
# só é conhecido após o apply — o que quebra o plan. Um único recurso IAM
# aceita valor apply-time sem problema.
resource "google_artifact_registry_repository_iam_member" "node_reader" {
  project    = var.project_id
  location   = var.region
  repository = "${local.name_prefix}-docker"
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${module.gke.service_account}"

  depends_on = [module.artifact_registry]
}
