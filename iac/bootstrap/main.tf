# ---------------------------------------------------------------------------
# Bootstrap: cria o bucket de GCS que guarda o state remoto do Terraform.
#
# Este código resolve o problema do "ovo e a galinha": o backend remoto
# precisa de um bucket, mas o bucket precisa ser criado por Terraform. Por
# isso o bootstrap usa backend LOCAL e é aplicado uma única vez, manualmente,
# antes de qualquer outro ambiente. Depois disso, todo o resto usa o bucket.
#
# Um bucket por ambiente NÃO é necessário: usamos prefixos (state paths)
# diferentes dentro do mesmo bucket para isolar staging e production.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Bootstrap usa state local de propósito (ver comentário acima).
  backend "local" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  # Nome neutro (desacoplado de qualquer ambiente de workload). Em produção este
  # bucket vive num projeto "seed"/automação e guarda o state dos 3 ambientes
  # via prefix. Se não informado, cai na convenção padrão <project>-tfstate.
  bucket_name = var.state_bucket_name != "" ? var.state_bucket_name : "${var.project_id}-tfstate"
}

resource "google_storage_bucket" "tf_state" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id

  # Impede exclusão acidental do bucket que guarda TODO o state.
  force_destroy = false

  # Versionamento é essencial para state: permite recuperar de um apply ruim.
  versioning {
    enabled = true
  }

  # Sem ACLs legadas — apenas IAM. Boa prática de segurança.
  uniform_bucket_level_access = true

  # Bloqueia qualquer exposição pública acidental.
  public_access_prevention = "enforced"

  # Mantém histórico enxuto: expira versões antigas do state depois de 90 dias.
  lifecycle_rule {
    condition {
      num_newer_versions = 10
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }
}
