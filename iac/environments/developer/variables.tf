variable "project_id" {
  description = "ID do projeto GCP do ambiente developer."
  type        = string
}

variable "region" {
  description = "Região do ambiente."
  type        = string
  default     = "southamerica-east1"
}

variable "master_authorized_networks" {
  description = "Redes autorizadas a acessar o control plane (inclua seu IP público para rodar kubectl)."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "github_repo" {
  description = "Repositório GitHub autorizado a assumir a SA do CI (owner/repo)."
  type        = string
  default     = "flaviolongue/teste-gcp-dito"
}
