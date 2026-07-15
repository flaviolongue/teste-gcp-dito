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

  # Liga o repositório à SA: só workflows deste repo assumem esta identidade.
  sa_mapping = {
    (google_service_account.gh_actions.account_id) = {
      sa_name   = google_service_account.gh_actions.name
      attribute = "attribute.repository/${var.github_repo}"
    }
  }
}
