output "wif_provider" {
  description = "Nome completo do Workload Identity Provider — vai no secret WIF_PROVIDER do GitHub."
  value       = module.gh_oidc.provider_name
}

output "service_account_email" {
  description = "SA que o GitHub Actions impersona — vai no secret do GitHub."
  value       = google_service_account.gh_actions.email
}
