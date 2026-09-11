output "pubsub_topic_name" {
  value = google_pubsub_topic.topic.name
}

output "pubsub_subscription_name" {
  description = "Pull subscription name, or null if the topic has no pull subscription."
  value       = one(google_pubsub_subscription.subscription[*].name)
}

output "service_account_email" {
  description = "Pull consumer service account, or null if the topic has no pull subscription."
  value       = one(google_service_account.pubsub_service_account[*].email)
}
