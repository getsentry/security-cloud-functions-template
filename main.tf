locals {
  project           = "jeffreyhung-test"
  region            = "us-west1"
  zone              = "us-west1-b"
  project_id        = "jeffreyhung-test"
  project_num       = "546928617664"
  bucket_location   = "US-WEST1"
  alerts_collection = "alerts"
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
  name                     = "${local.project}-cloud-function-staging"
  location                 = "US"
  force_destroy            = true
  public_access_prevention = "enforced"
}

resource "google_storage_bucket_iam_binding" "staging-bucket-iam" {
  bucket = google_storage_bucket.tf-state.name
  role   = "roles/storage.objectUser"

  members = ["serviceAccount:${module.infrastructure.deploy_sa_email}"]

  depends_on = [
    module.infrastructure,
    google_storage_bucket.staging_bucket
  ]
}

resource "google_storage_bucket_iam_member" "staging_bucket_get" {
  bucket = google_storage_bucket.staging_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${module.infrastructure.deploy_sa_email}"
}

resource "google_storage_bucket" "tf-state" {
  name                     = "${local.project}-tfstate"
  force_destroy            = false
  location                 = "US"
  storage_class            = "STANDARD"
  public_access_prevention = "enforced"
  versioning {
    enabled = true
  }
}

resource "google_storage_bucket_iam_binding" "tfstate-bucket-iam" {
  bucket = google_storage_bucket.tf-state.name
  role   = "roles/storage.objectUser"

  members = ["serviceAccount:${module.infrastructure.deploy_sa_email}"]

  depends_on = [
    module.infrastructure,
    google_storage_bucket.tf-state
  ]
}

resource "google_storage_bucket_iam_member" "tfstate_bucket_get" {
  bucket = google_storage_bucket.tf-state.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${module.infrastructure.deploy_sa_email}"
}