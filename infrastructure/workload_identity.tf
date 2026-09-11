locals {
  gha_name = "gha-terraform-checker"

  # BYO account if one was supplied, otherwise the one created below.
  apply_sa_email = var.deploy_sa_email != null ? var.deploy_sa_email : google_service_account.gha_cloud_functions_deployment[0].email
}

resource "google_service_account" "gha_cloud_functions_deployment" {
  count = var.deploy_sa_email != null ? 0 : 1

  account_id   = "gha-cloud-functions-deployment"
  description  = "Privileged SA for `terraform apply` (push to main only), owned by ${var.owner}, managed by Terraform"
  display_name = "gha-cloud-functions-deployment"
  project      = var.project

  depends_on = [google_project_service.services]
}

# `terraform plan` executes attacker-controllable PR configuration, so this
# identity must never hold write or secret-read permissions. See permissions.tf.
resource "google_service_account" "gha_tf_plan" {
  count = var.deploy_sa_email != null ? 0 : 1

  account_id   = "gha-cf-tf-plan"
  description  = "Read-only SA for `terraform plan` on pull requests, owned by ${var.owner}, managed by Terraform"
  display_name = "gha-cf-tf-plan"
  project      = var.project

  depends_on = [google_project_service.services]
}

resource "google_iam_workload_identity_pool" "gha_terraform_checker_pool" {
  count = var.deploy_sa_email != null ? 0 : 1

  workload_identity_pool_id = "${local.gha_name}-pool"
  display_name              = "GHA Terraform Checker Pool"
  description               = "Identity pool for Terraform Plan GHA, owned by ${var.owner}, managed by Terraform"

  depends_on = [google_project_service.services]
}

resource "google_iam_workload_identity_pool_provider" "gha_terraform_checker_provider" {
  count = var.deploy_sa_email != null ? 0 : 1

  workload_identity_pool_id          = google_iam_workload_identity_pool.gha_terraform_checker_pool[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "${local.gha_name}-provider"
  display_name                       = "GHA Terraform Checker Provider"
  description                        = "OIDC identity pool provider for Terraform Plan GHA, owned by ${var.owner}, managed by Terraform"

  attribute_mapping = {
    # The full GitHub subject (repo + ref/environment), so it is unique per
    # identity rather than per repository. The apply binding below matches on it.
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.aud"        = "assertion.aud"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository == '${var.github_repository}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
    allowed_audiences = [
      "https://iam.googleapis.com/projects/${var.project}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.gha_terraform_checker_pool[0].workload_identity_pool_id}/providers/${local.gha_name}-provider",
      "https://iam.googleapis.com/projects/${var.project_num}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.gha_terraform_checker_pool[0].workload_identity_pool_id}/providers/${local.gha_name}-provider"
    ]
  }
}

# Pinned to the `production` environment SUBJECT, not the git ref, which enforces
# the human approval gate at the IAM layer: a token only carries
# `...:environment:production` if its job declares `environment: production`, so
# no other main-triggered workflow can mint this one. Requires the environment to
# have a main-only deployment branch rule -- see README.
resource "google_service_account_iam_member" "gha_apply_workload_identity_user" {
  count = var.deploy_sa_email != null ? 0 : 1

  service_account_id = google_service_account.gha_cloud_functions_deployment[0].id
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.gha_terraform_checker_pool[0].name}/subject/repo:${var.github_repository}:environment:production"
}

# Any ref in this repository, so PR refs (refs/pull/<n>/merge) work.
resource "google_service_account_iam_member" "gha_plan_workload_identity_user" {
  count = var.deploy_sa_email != null ? 0 : 1

  service_account_id = google_service_account.gha_tf_plan[0].id
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.gha_terraform_checker_pool[0].name}/attribute.repository/${var.github_repository}"
}
