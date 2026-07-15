# Outputs agregados da plataforma, consumidos pelos ambientes.

output "network_name" {
  description = "Nome da VPC."
  value       = module.vpc.network_name
}

output "gke_cluster_name" {
  description = "Nome do cluster GKE."
  value       = module.gke.name
}

output "gke_location" {
  description = "Location (zona ou região) do cluster GKE."
  value       = module.gke.location
}

output "gateway_ip" {
  description = "IP estático global do Gateway — aponte o A record do DNS para ele."
  value       = var.create_gateway_ip ? google_compute_global_address.gateway[0].address : null
}

output "gateway_ip_name" {
  description = "Nome do IP estático — referenciado pelo Gateway (NamedAddress)."
  value       = var.create_gateway_ip ? google_compute_global_address.gateway[0].name : null
}

output "gke_get_credentials_command" {
  description = "Comando pronto para obter as credenciais do cluster."
  # --location funciona tanto para cluster regional quanto zonal (ao contrário
  # de --region, que quebra no zonal).
  value = "gcloud container clusters get-credentials ${module.gke.name} --location ${module.gke.location} --project ${var.project_id}"
}

output "workload_service_account_email" {
  description = "GSA do workload — anote na KSA (annotation iam.gke.io/gcp-service-account)."
  value       = module.workload_identity.gcp_service_account_email
}

output "artifact_registry_url" {
  description = "URL base do Artifact Registry para push/pull de imagens."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${local.name_prefix}-docker"
}

output "db_connection_name" {
  description = "Connection name do Cloud SQL para o Auth Proxy/sidecar."
  value       = module.postgres.instance_connection_name
}

output "db_private_ip" {
  description = "IP privado do Cloud SQL."
  value       = module.postgres.private_ip_address
}

output "db_name" {
  description = "Nome do banco da aplicação."
  value       = "app"
}

output "db_password_secret_id" {
  description = "secret_id no Secret Manager com a senha do banco."
  value       = "${local.name_prefix}-db-password"
}

output "app_api_key_secret_id" {
  description = "secret_id no Secret Manager do secret de aplicação."
  value       = "${local.name_prefix}-app-api-key"
}
