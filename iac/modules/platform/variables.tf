variable "project_id" {
  description = "ID do projeto GCP do ambiente."
  type        = string
}

variable "region" {
  description = "Região principal do ambiente."
  type        = string
  default     = "southamerica-east1"
}

variable "environment" {
  description = "Nome do ambiente (developer | staging | production)."
  type        = string
  validation {
    condition     = contains(["developer", "staging", "production"], var.environment)
    error_message = "environment deve ser 'developer', 'staging' ou 'production'."
  }
}

# --- Rede -------------------------------------------------------------------
variable "subnet_cidr" {
  description = "CIDR primário da subnet."
  type        = string
  default     = "10.10.0.0/20"
}

variable "pods_cidr" {
  description = "CIDR secundário para Pods."
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  description = "CIDR secundário para Services."
  type        = string
  default     = "10.30.0.0/20"
}

# --- GKE --------------------------------------------------------------------
variable "master_authorized_networks" {
  description = "Redes autorizadas a acessar o control plane do GKE."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "master_ipv4_cidr" {
  description = "CIDR /28 privado para o control plane do GKE."
  type        = string
  default     = "172.16.0.0/28"
}

variable "gke_regional" {
  description = "true = cluster regional (multi-zona, prod). false = zonal (barato, para teste/developer)."
  type        = bool
  default     = true
}

variable "gke_zones" {
  description = "Zonas do cluster quando zonal (gke_regional=false). Ex.: [\"southamerica-east1-a\"]."
  type        = list(string)
  default     = []
}

variable "gke_spot" {
  description = "Usa nós Spot (bem mais baratos, podem ser preemptados). Ideal para developer."
  type        = bool
  default     = false
}

variable "create_gateway_ip" {
  description = "Reserva um IP estático GLOBAL para o Gateway (Application LB). É o IP apontado no DNS."
  type        = bool
  default     = true
}

variable "gateway_api_channel" {
  description = "Habilita o Gateway API gerenciado do GKE (CHANNEL_STANDARD) ou desliga (CHANNEL_DISABLED). O controller roda no control plane do Google — não sobe pod no cluster."
  type        = string
  default     = "CHANNEL_STANDARD"
}

variable "gke_machine_type" {
  description = "Tipo de máquina dos nós do GKE."
  type        = string
  default     = "e2-standard-2"
}

variable "gke_min_nodes_per_zone" {
  description = "Mínimo de nós por zona."
  type        = number
  default     = 1
}

variable "gke_max_nodes_per_zone" {
  description = "Máximo de nós por zona."
  type        = number
  default     = 3
}

# --- Banco ------------------------------------------------------------------
variable "db_tier" {
  description = "Tier da instância Cloud SQL."
  type        = string
  default     = "db-custom-1-3840"
}

variable "db_availability_type" {
  description = "ZONAL ou REGIONAL (HA)."
  type        = string
  default     = "ZONAL"
}

variable "db_disk_size" {
  description = "Tamanho do disco do Cloud SQL em GB."
  type        = number
  default     = 20
}

# --- Kubernetes / Workload Identity -----------------------------------------
variable "k8s_namespace" {
  description = "Namespace onde a aplicação roda."
  type        = string
  default     = "apps"
}

variable "k8s_service_account" {
  description = "Nome da ServiceAccount Kubernetes da aplicação."
  type        = string
  default     = "dito-api"
}

# --- Secrets -----------------------------------------------------------------
variable "app_api_key_placeholder" {
  description = "Valor placeholder do secret de aplicação. O valor real é injetado fora do Terraform."
  type        = string
  default     = "CHANGE_ME_VIA_CI_OR_CONSOLE"
  sensitive   = true
}

# --- Proteções ---------------------------------------------------------------
variable "deletion_protection" {
  description = "Proteção contra destruição de recursos stateful (cluster, DB)."
  type        = bool
  default     = false
}
