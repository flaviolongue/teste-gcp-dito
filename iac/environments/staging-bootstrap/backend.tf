terraform {
  # State próprio (prefix separado do stack de infra "staging").
  #   terraform init -backend-config="bucket=<seu-bucket-de-state>"
  backend "gcs" {
    prefix = "staging-bootstrap"
  }
}
