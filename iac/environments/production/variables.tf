variable "project_id" {
  description = "ID do projeto GCP de produção."
  type        = string
}

variable "region" {
  description = "Região do ambiente."
  type        = string
  default     = "southamerica-east1"
}

variable "gke_machine_type" {
  description = "Tipo de máquina dos nós."
  type        = string
  default     = "e2-standard-4"
}

variable "gke_min_nodes_per_zone" {
  description = "Mínimo de nós por zona."
  type        = number
  default     = 2
}

variable "gke_max_nodes_per_zone" {
  description = "Máximo de nós por zona."
  type        = number
  default     = 5
}

variable "db_tier" {
  description = "Tier do Cloud SQL."
  type        = string
  default     = "db-custom-2-7680"
}

variable "master_authorized_networks" {
  description = "Redes autorizadas a acessar o control plane."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}
