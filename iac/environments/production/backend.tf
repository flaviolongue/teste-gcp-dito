terraform {
  # State remoto isolado por prefix. O bucket é passado no init:
  #   terraform init -backend-config="bucket=dito-production-tfstate"
  backend "gcs" {
    prefix = "production"
  }
}
