output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "argocd_server_url" {
  description = "ArgoCD server URL (LoadBalancer endpoint)"
  value = try(
    "http://${data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].hostname}",
    "ArgoCD server URL will be available once LoadBalancer is provisioned"
  )
}

# Output the initial admin password
# This is marked sensitive so it won't appear in logs
# To view it, run: terraform output -raw argocd_initial_admin_password
output "argocd_initial_admin_password" {
  description = "Initial admin password for ArgoCD (use 'admin' as username)"
  value = try(
    data.kubernetes_secret.argocd_initial_admin_secret.data["password"],
    "Password not yet available"
  )
  sensitive = true
}
