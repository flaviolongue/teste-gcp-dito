variable "project_id" {
  description = "ID do projeto GCP onde o bucket de state será criado."
  type        = string
}

variable "region" {
  description = "Região do bucket de state (ex.: southamerica-east1)."
  type        = string
  default     = "southamerica-east1"
}

variable "state_bucket_name" {
  description = "Nome neutro do bucket de state (desacoplado de workload). Vazio = convenção <project>-tfstate."
  type        = string
  default     = ""
}
