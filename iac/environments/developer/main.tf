# Ambiente DEVELOPER: perfil mínimo/barato para validar o procedimento de ponta
# a ponta na GCP. Mantém a arquitetura (nós privados + NAT + Workload Identity +
# Secret Manager + Cloud SQL privado), mas em tamanho reduzido:
#   - GKE ZONAL (1 zona) com nós Spot  -> muito mais barato que regional
#   - Cloud SQL db-f1-micro, ZONAL     -> menor instância
# NÃO usar este perfil para produção.

module "platform" {
  source = "../../modules/platform"

  project_id  = var.project_id
  region      = var.region
  environment = "developer"

  # GKE enxuto: zonal, on-demand. Spot foi desligado porque um nó único Spot,
  # ao ser preemptado, derruba tudo (ArgoCD/ESO/app) — ruim para um ambiente que
  # fica ligado para demonstração. On-demand aqui ainda é barato com o crédito.
  gke_regional           = false
  gke_zones              = ["${var.region}-a"]
  gke_spot               = false
  gke_machine_type       = "e2-standard-2"
  gke_min_nodes_per_zone = 1
  gke_max_nodes_per_zone = 3

  # Banco mínimo.
  db_tier              = "db-f1-micro"
  db_availability_type = "ZONAL"
  db_disk_size         = 10

  master_authorized_networks = var.master_authorized_networks

  # Ambiente descartável: sem proteção contra destruição (facilita o destroy).
  deletion_protection = false
}
