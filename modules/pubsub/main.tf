resource "google_pubsub_topic" "topic" {
  name = var.topic_name
  labels = {
    owner       = var.owner
    terraformed = "true"
  }

  message_retention_duration = "604800s" # 7 days, the maximum
  message_storage_policy {
    allowed_persistence_regions = [var.gcp_region]
  }
}

# The pull subscription and its consumer identity are optional: a topic that only
# pushes to functions/services (see modules/pubsub-push) has no pull consumer,
# and creating a service account nothing can run as would just be clutter.
resource "google_pubsub_subscription" "subscription" {
  count = var.subscription_id != null ? 1 : 0

  name                       = var.subscription_id
  topic                      = google_pubsub_topic.topic.name
  message_retention_duration = "604800s"
  retain_acked_messages      = false
  ack_deadline_seconds       = 600 # the maximum
  enable_message_ordering    = false
  labels = {
    owner       = var.owner
    terraformed = "true"
  }

  # Always set: omitting the block does NOT mean "never" -- it means GCP's
  # default of deleting the subscription after 31 idle days. Empty string is how
  # the API spells "never expire".
  expiration_policy {
    ttl = var.ttl != null ? var.ttl : ""
  }

  retry_policy {
    minimum_backoff = "10s"
  }
}

resource "google_service_account" "pubsub_service_account" {
  count = var.subscription_id != null ? 1 : 0

  account_id   = var.service_account_id
  display_name = coalesce(var.service_account_display_name, "Pub/Sub subscriber for ${var.subscription_id}")
  description  = "Service account for ${var.topic_name}, owned by ${var.owner}, managed by Terraform"
}

resource "google_pubsub_subscription_iam_member" "viewer" {
  count = var.subscription_id != null ? 1 : 0

  subscription = google_pubsub_subscription.subscription[0].name
  role         = "roles/pubsub.viewer"
  member       = "serviceAccount:${google_service_account.pubsub_service_account[0].email}"
}

resource "google_pubsub_subscription_iam_member" "subscriber" {
  count = var.subscription_id != null ? 1 : 0

  subscription = google_pubsub_subscription.subscription[0].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.pubsub_service_account[0].email}"
}
