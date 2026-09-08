resource "google_service_account" "workflow_sa" {
  account_id   = "wf-${var.name}"
  display_name = "Workflow Service Account for ${var.name}"
  description  = "Service account for ${var.name}, owned by ${var.owner}, managed by Terraform"
}

resource "google_workflows_workflow" "workflow" {
  name            = var.name
  region          = var.region
  description     = var.description
  service_account = google_service_account.workflow_sa.id

  # file(), NOT templatefile(). Cloud Workflows uses ${...} for its own runtime
  # expressions; templatefile() would try to evaluate those as HCL and fail with
  # "Extra characters after interpolation expression". To parameterise a
  # workflow, read GOOGLE_CLOUD_PROJECT_ID / GOOGLE_CLOUD_LOCATION at runtime --
  # see examples/workflow-basic/workflow.yaml.
  source_contents = file(var.workflow_yaml_file)

  labels = {
    owner       = var.owner
    terraformed = "true"
  }
}

resource "google_cloudfunctions2_function_iam_member" "function_invoker" {
  for_each = var.functions

  project        = var.project
  location       = var.region
  cloud_function = each.value
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.workflow_sa.email}"
}

# gen2 functions are Cloud Run underneath, so an OIDC call to the function URL
# needs run.invoker as well as cloudfunctions.invoker.
resource "google_cloud_run_service_iam_member" "function_run_invoker" {
  for_each = var.functions

  project  = var.project
  location = var.region
  service  = each.value
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.workflow_sa.email}"
}

resource "google_cloud_run_v2_service_iam_member" "cloudrun_invoker" {
  for_each = var.cloudruns

  project  = var.project
  location = var.region
  name     = each.value
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.workflow_sa.email}"
}

resource "google_storage_bucket_iam_member" "workflow_bucket_read" {
  for_each = var.bucket
  bucket   = each.value
  role     = "roles/storage.objectViewer"
  member   = "serviceAccount:${google_service_account.workflow_sa.email}"
}

resource "google_project_iam_member" "workflow_invoker" {
  # Project-wide because there is no way to scope it: the provider exposes no
  # google_workflows_workflow_iam_* resource, and workflows.googleapis.com does
  # not support resource.name IAM Conditions. Only created when this workflow
  # actually calls other workflows.
  count   = length(var.workflow) == 0 ? 0 : 1
  project = var.project
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}
