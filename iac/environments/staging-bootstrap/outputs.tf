output "argocd_namespace" {
  description = "Namespace onde o ArgoCD foi instalado."
  value       = "argocd"
}

output "argocd_admin_password_command" {
  description = "Comando para obter a senha inicial do admin do ArgoCD."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_port_forward_command" {
  description = "Comando para acessar a UI do ArgoCD via localhost."
  value       = "kubectl -n argocd port-forward svc/argocd-server 8080:80"
}
