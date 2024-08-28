resource "google_service_account" "cronjob_sa" {
  account_id   = "cj-${var.name}"
  display_name = "CronJob Service Account for ${var.name}"
}

resource "google_service_account_iam_member" "deploy_sa_actas_iam" {
  service_account_id = google_service_account.cronjob_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.deploy_sa_email}"
}

resource "google_cloudfunctions_function_iam_member" "cj_example_cron_invoker" {
  project        = var.target_project
  region         = var.target_region
  cloud_function = var.target_function_name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.cronjob_sa.email}"
}

resource "google_cloud_scheduler_job" "example_cronjob" {
  name             = var.name
  description      = var.description
  schedule         = var.schedule
  time_zone        = var.time_zone
  attempt_deadline = var.attempt_deadline

  http_target {
    http_method = var.http_method
    uri         = var.https_trigger_url

    oidc_token {
      service_account_email = google_service_account.cronjob_sa.email
    }
  }
}