terraform {
  # State próprio (prefix separado do stack de infra "developer").
  #   terraform init -backend-config="bucket=dito-tfstate-745166201237"
  backend "gcs" {
    prefix = "developer-bootstrap"
  }
}
