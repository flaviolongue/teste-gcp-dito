# Valores do ambiente PRODUCTION.
# Substitua project_id pelo ID real do projeto GCP de produção.

project_id = "dito-production"
region     = "southamerica-east1"

gke_machine_type       = "e2-standard-4"
gke_min_nodes_per_zone = 2
gke_max_nodes_per_zone = 5

db_tier = "db-custom-2-7680"

# Em produção, o control plane NÃO deve ficar aberto. Restrinja às redes
# corporativas e aos runners de CI que rodam terraform/kubectl.
# master_authorized_networks = [
#   { cidr_block = "203.0.113.0/24", display_name = "vpn-corporativa" }
# ]
master_authorized_networks = []
