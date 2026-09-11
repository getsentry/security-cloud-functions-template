output "pubsub_topic" {
  description = "Full name of the Pub/Sub topic this trigger consumes -- the one you named, or the one Eventarc created."
  value       = try(google_eventarc_trigger.earc-trigger.transport[0].pubsub[0].topic, null)
}
