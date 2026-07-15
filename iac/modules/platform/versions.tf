terraform {
  required_version = ">= 1.3"

  required_providers {
    google = {
      source = "hashicorp/google"
      # Faixa que satisfaz todos os módulos oficiais usados (GKE e Secret
      # Manager exigem < 6; sql-db exige >= 5.12).
      version = ">= 5.12, < 6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
