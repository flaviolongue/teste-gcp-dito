terraform {
  # State próprio (prefix separado do stack de infra "production").
  #   terraform init -backend-config="bucket=<seu-bucket-de-state>"
  backend "gcs" {
    prefix = "production-bootstrap"
  }
}
