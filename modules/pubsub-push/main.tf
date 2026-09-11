# Delivers Pub/Sub messages to a Cloud Function or Cloud Run service over HTTP
# push, authenticated with an OIDC token minted for a dedicated service account.
#
# One instance per TARGET, holding one push subscription per topic. The
# alternative -- one instance per (topic, target) pair -- would mean two topics
# pushing to the same function both try to create the same `ps-<target>` SA.

resource "google_service_account" "push_sa" {
  account_id   = "ps-${var.target_name}"
  display_name = "Pub/Sub push identity for ${var.target_type} ${var.target_name}"
  description  = "Used by Pub/Sub to invoke ${var.target_name}, owned by ${var.owner}, managed by Terraform"
}

# gen2 functions are Cloud Run underneath; an OIDC call to the function URL is
# authorised by run.invoker as well as cloudfunctions.invoker.
resource "google_cloudfunctions2_function_iam_member" "function_invoker" {
  count          = var.target_type == "function" ? 1 : 0
  project        = var.project
  location       = var.location
  cloud_function = var.target_name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.push_sa.email}"
}

resource "google_cloud_run_service_iam_member" "function_run_invoker" {
  count    = var.target_type == "function" ? 1 : 0
  project  = var.project
  location = var.location
  service  = var.target_name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.push_sa.email}"
}

resource "google_cloud_run_v2_service_iam_member" "cloudrun_invoker" {
  count    = var.target_type == "cloudrun" ? 1 : 0
  project  = var.project
  location = var.location
  name     = var.target_name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.push_sa.email}"
}

# NOTE: Pub/Sub mints the OIDC token as the project's Pub/Sub service agent,
# which needs iam.serviceAccounts.getOpenIdToken on push_sa. Projects created
# after 2021-04-08 get that automatically via roles/pubsub.serviceAgent. Older
# projects need a one-off manual grant, because the apply SA deliberately
# cannot set IAM on service accounts:
#   gcloud iam service-accounts add-iam-policy-binding ps-<target>@<project>.iam.gserviceaccount.com \
#     --member=serviceAccount:service-<project-number>@gcp-sa-pubsub.iam.gserviceaccount.com \
#     --role=roles/iam.serviceAccountTokenCreator
resource "google_pubsub_subscription" "push" {
  # Keyed by topic. The loader rejects a repeated (topic, target) pair at plan
  # time, so this can never silently merge two entries; the precondition below
  # is the backstop if the module is ever called directly.
  for_each = { for s in var.subscriptions : s.topic => s }

  name                       = "${each.value.topic}-to-${var.target_name}"
  topic                      = each.value.topic
  ack_deadline_seconds       = each.value.ack_deadline_seconds
  message_retention_duration = "604800s" # 7 days, the maximum

  labels = {
    owner       = var.owner
    terraformed = "true"
  }

  push_config {
    push_endpoint = "${var.target_url}${each.value.path}"

    oidc_token {
      service_account_email = google_service_account.push_sa.email
      # The audience is the service root, not the endpoint path: Cloud Run
      # validates the token against the service URL and rejects a path-suffixed
      # audience with 401.
      audience = var.target_url
    }
  }

  # Without this GCP applies its default of deleting the subscription after 31
  # days of no messages. A quiet topic would silently lose its delivery until the
  # next apply recreated it. Empty string means never expire.
  expiration_policy {
    ttl = ""
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  lifecycle {
    precondition {
      condition     = length(var.subscriptions) == length(distinct([for s in var.subscriptions : s.topic]))
      error_message = "pubsub-push for ${var.target_name}: the same topic appears more than once in subscriptions; each topic may push to a target only once."
    }
  }

  depends_on = [
    google_cloudfunctions2_function_iam_member.function_invoker,
    google_cloud_run_service_iam_member.function_run_invoker,
    google_cloud_run_v2_service_iam_member.cloudrun_invoker,
  ]
}
