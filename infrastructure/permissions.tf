# Project-wide roles for the privileged "apply" service account.
#
# roles/iam.serviceAccountUser is a project-wide actAs primitive and cannot be
# scoped down: creating a per-SA actAs binding on a freshly-created SA itself
# requires iam.serviceAccounts.setIamPolicy on that SA (circular), and IAM
# Conditions are not supported for service-account resources. setIamPolicy would
# be strictly broader -- it can grant any principal actAs on any SA. To lock this
# down further, drop the role and create runtime-SA actAs bindings in a
# privileged bootstrap apply, at the cost of CI self-service.
locals {
  roles = [
    "roles/viewer",
    "roles/iam.securityReviewer", # *.getIamPolicy, so plan/apply can refresh IAM resources
    "roles/storage.admin",
    "roles/cloudfunctions.developer",
    "roles/logging.viewer",
    "roles/iam.workloadIdentityPoolViewer",
    "roles/iam.serviceAccountCreator", # create the per-resource runtime service accounts
    "roles/iam.serviceAccountUser",    # actAs those runtime SAs to deploy as them
    "roles/pubsub.admin",
    "roles/artifactregistry.admin", # manage the Cloud Run repo and push images to it
  ]
}

# tfsec flags the *.admin roles and the project-wide serviceAccountUser grant.
# Both are the deliberate, documented cost of a self-service apply identity --
# see the header comment above and the README's "Security design" section.
#tfsec:ignore:google-iam-no-privileged-service-accounts
#tfsec:ignore:google-iam-no-project-level-service-account-impersonation
resource "google_project_iam_member" "project_roles" {
  for_each = toset(local.roles)
  project  = var.project
  role     = each.value
  member   = "serviceAccount:${local.apply_sa_email}"
}

# Deploying a secret does not require reading it, so the apply SA gets secret
# management without roles/secretmanager.secretAccessor: a compromised CI run
# cannot exfiltrate secret values.
resource "google_project_iam_custom_role" "tf_secret_manager" {
  role_id     = "cfTemplateSecretManager"
  title       = "CF Template Secret Manager (no value access)"
  description = "Create and manage Secret Manager secrets and their IAM bindings without reading secret values"
  permissions = [
    "secretmanager.secrets.create",
    "secretmanager.secrets.delete",
    "secretmanager.secrets.get",
    "secretmanager.secrets.list",
    "secretmanager.secrets.update",
    "secretmanager.secrets.getIamPolicy",
    "secretmanager.secrets.setIamPolicy",
  ]

  depends_on = [google_project_service.services]
}

resource "google_project_iam_member" "apply_secret_manager" {
  project = var.project
  role    = google_project_iam_custom_role.tf_secret_manager.name
  member  = "serviceAccount:${local.apply_sa_email}"
}

# Read-only project access for the plan SA. Neither of these grants
# secretmanager.versions.access, so it cannot read secret values.
resource "google_project_iam_member" "plan_viewer" {
  count   = var.deploy_sa_email != null ? 0 : 1
  project = var.project
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.gha_tf_plan[0].email}"
}

resource "google_project_iam_member" "plan_security_reviewer" {
  count   = var.deploy_sa_email != null ? 0 : 1
  project = var.project
  role    = "roles/iam.securityReviewer"
  member  = "serviceAccount:${google_service_account.gha_tf_plan[0].email}"
}

# securityReviewer grants list + getIamPolicy but not get, which plan needs to
# refresh the pool and provider resources.
resource "google_project_iam_member" "plan_wif_viewer" {
  count   = var.deploy_sa_email != null ? 0 : 1
  project = var.project
  role    = "roles/iam.workloadIdentityPoolViewer"
  member  = "serviceAccount:${google_service_account.gha_tf_plan[0].email}"
}

# roles/viewer omits storage.buckets.get, which plan needs to refresh bucket
# resources. Metadata only: object reads stay scoped to the staging bucket (see
# main.tf) so PR code cannot read other buckets' contents, e.g. pub/sub sinks.
resource "google_project_iam_custom_role" "tf_plan_bucket_reader" {
  count       = var.deploy_sa_email != null ? 0 : 1
  role_id     = "cfTemplatePlanBucketReader"
  title       = "CF Template Plan Bucket Metadata Reader"
  description = "Read bucket metadata (storage.buckets.get) for terraform plan refresh, no object access"
  permissions = [
    "storage.buckets.get",
  ]

  depends_on = [google_project_service.services]
}

resource "google_project_iam_member" "plan_bucket_reader" {
  count   = var.deploy_sa_email != null ? 0 : 1
  project = var.project
  role    = google_project_iam_custom_role.tf_plan_bucket_reader[0].name
  member  = "serviceAccount:${google_service_account.gha_tf_plan[0].email}"
}
