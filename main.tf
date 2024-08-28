terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.23.0"
    }

    google-beta = {
      source = "hashicorp/google-beta"
    }
  }
}

provider "google" {
  project = local.project
  region  = local.region
  zone    = local.zone
}


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

resource "google_storage_bucket" "staging_bucket" {
  name          = "${local.project}-cloud-function-staging"
  location      = "US"
  force_destroy = true

  public_access_prevention = "enforced"
}