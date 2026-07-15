terraform {
  # State remoto isolado por prefix. O bucket é passado no init:
  #   terraform init -backend-config="bucket=<project>-tfstate"
  backend "gcs" {
    prefix = "developer"
  }
}
