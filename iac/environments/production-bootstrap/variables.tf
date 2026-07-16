variable "project_id" {
  description = "ID do projeto GCP (mesmo do stack de infra production)."
  type        = string
}

variable "region" {
  description = "Região do ambiente."
  type        = string
  default     = "southamerica-east1"
}

variable "state_bucket" {
  description = "Bucket onde está o state do stack de infra (para o terraform_remote_state)."
  type        = string
}
