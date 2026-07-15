# ---------------------------------------------------------------------------
# Módulo: argocd
# Aplica o install do ArgoCD (gitops/install) via provider kustomization.
#
# O provider roda `kustomize build` — inclusive baixando a base remota oficial
# pinada — e aplica cada recurso. Usa ids_prio para respeitar a ordem: primeiro
# CRDs/Namespaces (prio 0), depois o resto (prio 1 e 2), evitando o erro de
# aplicar um CR antes do seu CRD existir.
# ---------------------------------------------------------------------------

data "kustomization_build" "argocd" {
  path = var.manifests_path
}

# Prioridade 0: Namespaces, CRDs, etc.
resource "kustomization_resource" "p0" {
  for_each = data.kustomization_build.argocd.ids_prio[0]
  manifest = data.kustomization_build.argocd.manifests[each.value]
}

# Prioridade 1: a maioria dos recursos namespaced.
resource "kustomization_resource" "p1" {
  for_each = data.kustomization_build.argocd.ids_prio[1]
  manifest = data.kustomization_build.argocd.manifests[each.value]

  depends_on = [kustomization_resource.p0]
}

# Prioridade 2: webhooks e recursos que dependem dos anteriores.
resource "kustomization_resource" "p2" {
  for_each = data.kustomization_build.argocd.ids_prio[2]
  manifest = data.kustomization_build.argocd.manifests[each.value]

  depends_on = [kustomization_resource.p1]
}
