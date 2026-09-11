# Consumed by the workflows/ loader so an Eventarc trigger can name a topic
# defined here, validated at plan time.
output "topic_names" {
  description = "Set of every Pub/Sub topic name created from this directory."
  value       = toset([for m in module.pubsubs : m.pubsub_topic_name])
}

output "push_identities" {
  description = "Map of push target (type/name) to the service account Pub/Sub delivers as."
  value       = { for k, m in module.pubsub_push : k => m.push_sa_email }
}
