
output "secret_ids" {
  value = { for s in google_secret_manager_secret.secret : s.secret_id => s.secret_id }
}

output "deploy_sa_email" {
  value = google_service_account.gha_cloud_functions_deployment.email
}