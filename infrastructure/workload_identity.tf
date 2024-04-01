locals {
  gha_name        = "gha-terraform-checker"
  attribute_scope = "repository"
}

resource "google_service_account" "gha_cloud_functions_deployment" {
  account_id   = "gha-cloud-functions-deployment"
  description  = "For use by Terraform and GitHub Actions to deploy DNR pipeline resources via security-cloud-functions repo"
  display_name = "gha-cloud-functions-deployment"
  project      = local.project
}

resource "google_iam_workload_identity_pool" "gha_terraform_checker_pool" {
  workload_identity_pool_id = "${local.gha_name}-pool"
  display_name              = "GHA Terraform Checker Pool"
  description               = "Identity pool for Terraform Plan GHA"
}

resource "google_iam_workload_identity_pool_provider" "gha_terraform_checker_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.gha_terraform_checker_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "${local.gha_name}-provider"
  display_name                       = "GHA Terraform Checker Provider"
  description                        = "OIDC identity pool provider for Terraform Plan GHA"

  attribute_mapping = {
    "google.subject"       = "assertion.${local.attribute_scope}"
    "attribute.actor"      = "assertion.actor"
    "attribute.aud"        = "assertion.aud"
    "attribute.repository" = "assertion.repository"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "gha_workload_identity_user" {
  service_account_id = google_service_account.gha_cloud_functions_deployment.id
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.gha_terraform_checker_pool.name}/*"
}