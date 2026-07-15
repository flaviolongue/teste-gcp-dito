# Ambiente PRODUCTION: mesmo módulo platform, parâmetros de produção.
# Diferenças-chave: banco em HA (REGIONAL), mais capacidade de nós e proteção
# contra exclusão de recursos stateful.

module "platform" {
  source = "../../modules/platform"

  project_id  = var.project_id
  region      = var.region
  environment = "production"

  gke_machine_type       = var.gke_machine_type
  gke_min_nodes_per_zone = var.gke_min_nodes_per_zone
  gke_max_nodes_per_zone = var.gke_max_nodes_per_zone
  db_tier                = var.db_tier
  db_availability_type   = "REGIONAL" # HA multi-zona em produção.

  master_authorized_networks = var.master_authorized_networks

  # Impede destruição acidental do cluster e do banco em produção.
  deletion_protection = true
}
