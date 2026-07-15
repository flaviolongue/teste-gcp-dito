variable "project_id" {
  description = "ID do projeto GCP."
  type        = string
}

variable "region" {
  description = "Região do Artifact Registry."
  type        = string
}

variable "name_prefix" {
  description = "Prefixo para nomes de recursos (ex.: dito-developer)."
  type        = string
}

variable "github_repo" {
  description = "Repositório GitHub autorizado, no formato owner/repo. Só ele consegue assumir a SA."
  type        = string
}

variable "artifact_registry_repo" {
  description = "Nome do repositório do Artifact Registry onde o pipeline faz push."
  type        = string
}
