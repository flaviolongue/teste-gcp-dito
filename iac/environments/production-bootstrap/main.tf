# ---------------------------------------------------------------------------
# Stack: production-bootstrap (Layer 2)
# Instala o ArgoCD NO cluster de production (modelo: um ArgoCD por cluster).
# Roda DEPOIS do stack de infra ("production").
#
# O cluster já existe quando este stack roda, então apenas o LEMOS (via remote
# state + data source). Sem chicken-egg: a config do provider kustomization vem
# de um cluster que já existe.
# ---------------------------------------------------------------------------

data "terraform_remote_state" "infra" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "production"
  }
}

data "google_client_config" "current" {}

data "google_container_cluster" "gke" {
  name     = data.terraform_remote_state.infra.outputs.gke_cluster_name
  location = data.terraform_remote_state.infra.outputs.gke_location
  project  = var.project_id
}

provider "kustomization" {
  # kubeconfig em memória, a partir do cluster + token de curta duração do ADC.
  kubeconfig_raw = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "gke"
    clusters = [{
      name = "gke"
      cluster = {
        server                     = "https://${data.google_container_cluster.gke.endpoint}"
        certificate-authority-data = data.google_container_cluster.gke.master_auth[0].cluster_ca_certificate
      }
    }]
    users = [{
      name = "gke"
      user = { token = data.google_client_config.current.access_token }
    }]
    contexts = [{
      name    = "gke"
      context = { cluster = "gke", user = "gke" }
    }]
  })
}

module "argocd" {
  source = "../../modules/argocd"
  # Path por-cluster: instala o ArgoCD + registra o root app-of-apps de production
  # (que puxa só as Applications deste cluster).
  manifests_path = "${path.root}/../../../gitops/clusters/production"
}
