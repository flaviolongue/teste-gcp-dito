# Repassa os outputs relevantes da plataforma para o nível do ambiente.

output "gke_cluster_name" {
  description = "Nome do cluster GKE de produção."
  value       = module.platform.gke_cluster_name
}

output "gke_get_credentials_command" {
  description = "Comando para configurar o kubeconfig deste cluster."
  value       = module.platform.gke_get_credentials_command
}

output "workload_service_account_email" {
  description = "GSA do workload para anotar na KSA."
  value       = module.platform.workload_service_account_email
}

output "artifact_registry_url" {
  description = "URL do Artifact Registry."
  value       = module.platform.artifact_registry_url
}

output "db_connection_name" {
  description = "Connection name do Cloud SQL."
  value       = module.platform.db_connection_name
}

output "db_private_ip" {
  description = "IP privado do Cloud SQL."
  value       = module.platform.db_private_ip
}

output "app_api_key_secret_id" {
  description = "secret_id do secret de aplicação."
  value       = module.platform.app_api_key_secret_id
}

output "gke_location" {
  description = "Location (região) do cluster GKE — consumido pelo stack production-bootstrap."
  value       = module.platform.gke_location
}
