# Bootstrap do GitOps (ArgoCD) em duas fases.
#
# Uso:
#   make bootstrap   # instala o ArgoCD + config e depois registra as Applications
#   make install     # só instala/atualiza o ArgoCD (base remota + config)
#   make apps        # só (re)aplica AppProject + Applications
#   make diff        # mostra o que mudaria no install sem aplicar
#   make password    # imprime a senha inicial do admin

.PHONY: bootstrap install wait apps diff password uninstall

bootstrap: install wait apps
	@echo "ArgoCD no ar. Acesse a UI e sincronize as Applications."

install:
	# --server-side é necessário: os CRDs do ArgoCD têm anotações grandes que
	# estouram o limite do apply client-side.
	kustomize build install | kubectl apply --server-side --force-conflicts -f -

wait:
	kubectl -n argocd rollout status deploy/argocd-server --timeout=180s
	kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=180s

apps:
	kustomize build apps | kubectl apply -f -

diff:
	kustomize build install | kubectl diff -f - || true

password:
	@kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 -d; echo

uninstall:
	-kustomize build apps    | kubectl delete -f - --ignore-not-found
	-kustomize build install | kubectl delete -f - --ignore-not-found
