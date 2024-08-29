locals {
  project           = "jeffreyhung-test"
  region            = "us-west1"
  zone              = "us-west1-b"
  project_id        = "jeffreyhung-test"
  project_num       = "546928617664"
  bucket_location   = "US-WEST1"
  alerts_collection = "alerts"
  sentry_jira_url   = "https://getsentry.atlassian.net"
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0.1"
    }
  }
  backend "gcs" {
    bucket = "jeffreyhung-test-tfstate"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = local.project
  region  = local.region
  zone    = local.zone
}

resource "google_storage_bucket" "staging_bucket" {
  name          = "${local.project}-cloud-function-staging"
  location      = "US"
  force_destroy = true
  public_access_prevention = "enforced"
}

resource "google_storage_bucket" "tf-state" {
  name          = "${local.project}-tfstate"
  force_destroy = false
  location      = "US"
  storage_class = "STANDARD"
  public_access_prevention = "enforced"
  versioning {
    enabled = true
  }
}

resource "google_storage_bucket_iam_binding" "tfstate-bucket" {
  bucket = google_storage_bucket.tf-state.name
  role   = "roles/storage.objectUser"

  members = ["serviceAccount:${module.infrastructure.deploy_sa_email}"]

  depends_on = [ module.infrastructure ]
}