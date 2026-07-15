terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # Provider nativo que roda `kustomize build` e aplica cada recurso como um
    # recurso Terraform (com diff/drift real). É o "kustomize dentro do TF".
    kustomization = {
      source  = "kbst/kustomization"
      version = "~> 0.9"
    }
  }
}
