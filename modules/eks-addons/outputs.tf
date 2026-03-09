# Output the initial admin password
# This is marked sensitive so it won't appear in logs
# To view it, run: terraform output -raw argocd_initial_admin_password
output "argocd_initial_admin_password" {
  description = "username=admin"
  value = try(
    data.kubernetes_secret.argocd_initial_admin_secret.data["password"],
    "Password not yet available"
  )
  sensitive = true
}
