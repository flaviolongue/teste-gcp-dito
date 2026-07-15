# ---------------------------------------------------------------------------
# Stack: developer-bootstrap (Layer 2)
# Instala o ArgoCD NO cluster do ambiente developer (modelo: um ArgoCD por
# cluster). Roda DEPOIS do stack de infra ("developer").
#
# Como o cluster já foi criado pela Layer 1, aqui apenas o LEMOS (via remote
# state + data source). Não há chicken-egg: a config do provider kustomization
# é derivada de um cluster que já existe.
# ---------------------------------------------------------------------------

# Lê as saídas do stack de infra (developer) direto do state remoto.
data "terraform_remote_state" "infra" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "developer"
  }
}

data "google_client_config" "current" {}

data "google_container_cluster" "gke" {
  name     = data.terraform_remote_state.infra.outputs.gke_cluster_name
  location = data.terraform_remote_state.infra.outputs.gke_location
  project  = var.project_id
}

provider "kustomization" {
  # kubeconfig em memória, montado a partir do cluster + token de curta duração
  # do ADC/gcloud. Nada gravado em disco.
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
  source         = "../../modules/argocd"
  manifests_path = "${path.root}/../../../gitops/install"
}
