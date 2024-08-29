resource "google_service_account" "function_sa" {
  account_id   = "cf-${var.name}"
  display_name = "Cloud Function Service Account for ${var.name}"
}

resource "google_cloudfunctions_function_iam_member" "involker" {
  project        = google_cloudfunctions_function.function.project
  region         = google_cloudfunctions_function.function.region
  cloud_function = google_cloudfunctions_function.function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_secret_manager_secret_iam_member" "secret_iam" {
  for_each  = { for s in var.secret_environment_variables : s.key => s }
  secret_id = each.value.secret
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.function_sa.email}"
}


resource "google_service_account_iam_member" "function_sa_actas_iam" {
  service_account_id = google_service_account.function_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_service_account_iam_member" "deploy_sa_actas_iam" {
  service_account_id = google_service_account.function_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.deploy_sa_email}" # we have to set this for our CD to work
}

resource "google_project_iam_member" "function_sa_logwriter_iam" {
  project = var.project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

data "archive_file" "source" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${var.temp_zip_output_dir}/${var.name}.zip"
  excludes    = var.files_to_exclude
}

resource "google_storage_bucket_object" "zip" {
  source       = data.archive_file.source.output_path
  content_type = "application/zip"

  # Append to the MD5 checksum of the files's content
  # to force the zip to be updated as soon as a change occurs
  name   = "${var.source_object_prefix}${data.archive_file.source.output_md5}.zip"
  bucket = "${var.project}-cloud-function-staging"
}

resource "google_cloudfunctions_function" "function" {
  name        = var.name
  description = var.description
  runtime     = var.runtime

  # Get the source code of the cloud function as a Zip compression
  source_archive_bucket = "${var.project}-cloud-function-staging"
  source_archive_object = google_storage_bucket_object.zip.name

  entry_point           = var.function_entrypoint
  trigger_http          = var.trigger_http
  timeout               = var.execution_timeout
  available_memory_mb   = var.available_memory_mb
  environment_variables = var.environment_variables
  service_account_email = google_service_account.function_sa.email

  dynamic "secret_environment_variables" {
    for_each = var.secret_environment_variables
    iterator = item
    content {
      key     = item.value.key
      secret  = var.secret_ids[item.value.secret]
      version = item.value.version
    }
  }

  depends_on = [
    google_service_account_iam_member.function_sa_actas_iam,
    google_service_account_iam_member.deploy_sa_actas_iam,
    data.archive_file.source
  ]
}