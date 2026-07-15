# Valores do ambiente DEVELOPER.
# Projeto GCP real: "Teste-dito" (número 745166201237).
project_id = "project-4a372108-be7a-4159-966"

region = "southamerica-east1"

# Para rodar `kubectl` a partir da sua máquina, descubra seu IP público
# (curl ifconfig.me) e libere-o no control plane. Enquanto vazio, o endpoint
# público fica sem restrição de IP — ok para um teste curto, evite deixar assim.
# master_authorized_networks = [
#   { cidr_block = "SEU.IP.PUBLICO/32", display_name = "minha-maquina" }
# ]
master_authorized_networks = []
