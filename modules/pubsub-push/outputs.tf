output "push_sa_email" {
  description = "Service account Pub/Sub authenticates as when pushing to this target."
  value       = google_service_account.push_sa.email
}

output "subscription_names" {
  description = "Push subscription per source topic."
  value       = { for k, s in google_pubsub_subscription.push : k => s.name }
}
