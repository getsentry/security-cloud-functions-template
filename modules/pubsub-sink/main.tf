# Archives every message published to a topic into GCS.
#
# The export subscription is separate from the topic's pull subscription on
# purpose: a subscription with cloud_storage_config is consumed by Pub/Sub
# itself and cannot also be pulled from, so sharing one would break the consumer.

locals {
  # Bucket names are globally unique, so an unprefixed name like "example-sink"
  # is almost certainly taken by someone else's project.
  bucket_name = "${var.project}-${var.sink_name}"

  pubsub_service_agent = "serviceAccount:service-${var.project_num}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_storage_bucket" "pubsub-sink-bucket" {
  name                        = local.bucket_name
  location                    = var.bucket_location
  force_destroy               = true
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
  labels = {
    owner       = var.owner
    terraformed = "true"
  }

  lifecycle_rule {
    condition {
      age = var.retention_days
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket_iam_member" "pubsub_writer" {
  bucket = google_storage_bucket.pubsub-sink-bucket.name
  role   = "roles/storage.objectCreator"
  member = local.pubsub_service_agent
}

# Pub/Sub checks it can write to the bucket when the subscription is created,
# so the grant has to land first.
resource "google_pubsub_subscription" "sink" {
  name                       = "${var.sink_name}-gcs-export"
  topic                      = var.topic_name
  message_retention_duration = var.message_retention_duration

  labels = {
    owner       = var.owner
    terraformed = "true"
  }

  # Never expire. GCP's default deletes a subscription idle for 31 days, which
  # would silently stop archiving a quiet topic.
  expiration_policy {
    ttl = ""
  }

  cloud_storage_config {
    bucket          = google_storage_bucket.pubsub-sink-bucket.name
    filename_prefix = var.filename_prefix
    filename_suffix = ".json"
    max_duration    = var.max_duration
    max_bytes       = var.max_bytes
  }

  depends_on = [
    google_storage_bucket_iam_member.pubsub_writer
  ]
}
