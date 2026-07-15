output "state_bucket" {
  description = "Nome do bucket GCS criado para o state remoto. Use-o no bloco backend dos ambientes."
  value       = google_storage_bucket.tf_state.name
}
