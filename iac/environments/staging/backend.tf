terraform {
  # State remoto no bucket criado pelo bootstrap. Cada ambiente usa um prefix
  # diferente para isolar o state dentro do mesmo bucket.
  #
  # O nome do bucket não pode ser interpolado aqui (limitação do Terraform),
  # por isso ele é passado via `-backend-config` no `terraform init`:
  #   terraform init -backend-config="bucket=dito-staging-tfstate"
  backend "gcs" {
    prefix = "staging"
  }
}
