# ---------------------------------------------------------------------------
# Módulo: cicd
# Workload Identity Federation para o GitHub Actions — autenticação KEYLESS.
#
# Como funciona: o GitHub Actions emite um token OIDC; a GCP valida esse token
# contra o pool/provider abaixo e, se o repositório bater com o autorizado,
# permite impersonar a Service Account. Nenhuma chave JSON é criada, baixada ou
# guardada em secret do GitHub.
#
# Em um cenário multi-projeto, isto viveria no projeto "seed"/CI, e a SA
# impersonaria SAs de menor privilégio em cada projeto de ambiente.
# ---------------------------------------------------------------------------

# SA usada pelo pipeline de build/push da imagem.
resource "google_service_account" "gh_actions" {
  account_id   = "${var.name_prefix}-gh-actions"
  display_name = "GitHub Actions - build e push de imagem"
  project      = var.project_id
}

# Permissão MÍNIMA: escrever apenas no repositório de imagens deste ambiente.
# Não é roles/editor nem escopo de projeto — é por-repositório.
resource "google_artifact_registry_repository_iam_member" "writer" {
  project    = var.project_id
  location   = var.region
  repository = var.artifact_registry_repo
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.gh_actions.email}"
}

# SA usada pelo pipeline de Terraform (plan/apply da infra).
resource "google_service_account" "terraform" {
  account_id   = "${var.name_prefix}-tf"
  display_name = "GitHub Actions - Terraform plan/apply"
  project      = var.project_id
}

# ATENÇÃO / TEST-ONLY: roles/owner para o Terraform gerenciar tudo sem esbarrar
# em permissão faltando no meio de um apply em CI. Em PRODUÇÃO isto DEVE ser um
# conjunto curado de menor privilégio, algo como:
#   roles/editor, roles/resourcemanager.projectIamAdmin,
#   roles/iam.serviceAccountAdmin, roles/iam.workloadIdentityPoolAdmin,
#   roles/secretmanager.admin, roles/artifactregistry.admin
resource "google_project_iam_member" "terraform_owner" {
  project = var.project_id
  role    = "roles/owner"
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

# Pool + provider OIDC do GitHub.
module "gh_oidc" {
  source  = "terraform-google-modules/github-actions-runners/google//modules/gh-oidc"
  version = "~> 3.1"

  project_id  = var.project_id
  pool_id     = "${var.name_prefix}-gh-pool"
  provider_id = "${var.name_prefix}-gh-provider"

  # Trava o provider no NOSSO repositório. Sem esta condição, qualquer
  # repositório do GitHub poderia trocar um token pelo acesso.
  attribute_condition = "assertion.repository == '${var.github_repo}'"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Liga o repositório às SAs: só workflows deste repo assumem estas identidades.
  sa_mapping = {
    (google_service_account.gh_actions.account_id) = {
      sa_name   = google_service_account.gh_actions.name
      attribute = "attribute.repository/${var.github_repo}"
    }
    (google_service_account.terraform.account_id) = {
      sa_name   = google_service_account.terraform.name
      attribute = "attribute.repository/${var.github_repo}"
    }
  }
}
