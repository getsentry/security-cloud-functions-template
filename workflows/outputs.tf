output "eventarc_topics" {
  description = "Map of triggered workflow to the Pub/Sub topic that fires it. Publish to this topic to run the workflow."
  value       = { for k, m in module.workflows-ingest-trigger : k => m.pubsub_topic }
}
