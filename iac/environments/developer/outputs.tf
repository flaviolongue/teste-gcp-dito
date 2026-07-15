output "gke_cluster_name" {
  description = "Nome do cluster GKE de developer."
  value       = module.platform.gke_cluster_name
}

output "gke_location" {
  description = "Location (zona) do cluster GKE — consumido pelo stack developer-bootstrap."
  value       = module.platform.gke_location
}

output "gateway_ip" {
  description = "IP estático global do Gateway — aponte os A records do Cloudflare para ele."
  value       = module.platform.gateway_ip
}

output "gateway_ip_name" {
  description = "Nome do IP estático, referenciado pelo Gateway."
  value       = module.platform.gateway_ip_name
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

output "wif_provider" {
  description = "Valor do secret WIF_PROVIDER no GitHub."
  value       = module.cicd.wif_provider
}

output "cicd_service_account" {
  description = "Valor do secret do GitHub com a SA que o Actions impersona."
  value       = module.cicd.service_account_email
}
