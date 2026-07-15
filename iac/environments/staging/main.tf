# Ambiente STAGING: instancia o módulo platform com parâmetros de staging.
# A fiação dos recursos vive no módulo; aqui ficam apenas os valores do ambiente.

module "platform" {
  source = "../../modules/platform"

  project_id  = var.project_id
  region      = var.region
  environment = "staging"

  # Staging é mais enxuto: nós menores, sem HA no banco.
  gke_machine_type       = var.gke_machine_type
  gke_min_nodes_per_zone = var.gke_min_nodes_per_zone
  gke_max_nodes_per_zone = var.gke_max_nodes_per_zone
  db_tier                = var.db_tier
  db_availability_type   = "ZONAL"

  master_authorized_networks = var.master_authorized_networks

  # Sem proteção de exclusão em staging: facilita recriar o ambiente.
  deletion_protection = false
}
