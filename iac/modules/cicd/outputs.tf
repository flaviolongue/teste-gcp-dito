output "wif_provider" {
  description = "Nome completo do Workload Identity Provider — vai no secret WIF_PROVIDER do GitHub."
  value       = module.gh_oidc.provider_name
}

output "service_account_email" {
  description = "SA de build/push de imagem — vai no secret APP_DEPLOYER_SERVICE_ACCOUNT."
  value       = google_service_account.gh_actions.email
}

output "terraform_service_account_email" {
  description = "SA de Terraform plan/apply — vai no secret TF_SERVICE_ACCOUNT."
  value       = google_service_account.terraform.email
}
