# Valores do ambiente STAGING.
# Substitua project_id pelo ID real do projeto GCP de staging.

project_id = "dito-staging"
region     = "southamerica-east1"

gke_machine_type       = "e2-standard-2"
gke_min_nodes_per_zone = 1
gke_max_nodes_per_zone = 2

db_tier = "db-custom-1-3840"

# Em um cenário real, restrinja o acesso ao control plane às redes corporativas
# e à faixa dos runners de CI. Exemplo:
# master_authorized_networks = [
#   { cidr_block = "203.0.113.0/24", display_name = "escritorio" }
# ]
master_authorized_networks = []
