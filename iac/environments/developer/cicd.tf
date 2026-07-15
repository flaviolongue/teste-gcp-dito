# CI/CD: Workload Identity Federation para o GitHub Actions (keyless).
#
# Nota de arquitetura: no modelo multi-projeto (produção), isto viveria no
# projeto "seed"/CI, e a SA de lá impersonaria SAs de menor privilégio em cada
# projeto de ambiente. Aqui, como o teste roda num projeto só, fica junto.

# APIs necessárias para o WIF.
resource "google_project_service" "cicd_apis" {
  for_each = toset([
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

module "cicd" {
  source = "../../modules/cicd"

  project_id             = var.project_id
  region                 = var.region
  name_prefix            = "dito-developer"
  github_repo            = var.github_repo
  artifact_registry_repo = "dito-developer-docker"

  depends_on = [module.platform, google_project_service.cicd_apis]
}
