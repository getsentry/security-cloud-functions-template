# Google-managed encryption. A CMEK would need a KMS key and key-admin roles on
# the apply SA that this template deliberately does not grant.
#tfsec:ignore:google-storage-bucket-encryption-customer-key
resource "google_storage_bucket" "staging_bucket" {
  name                        = "${var.project}-cloud-function-staging"
  location                    = var.bucket_location
  force_destroy               = true
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
  labels = {
    owner       = var.owner
    terraformed = "true"
  }

  # Source object names are content-addressed (see modules/cloud-function-gen2),
  # so superseded archives are never referenced again and would pile up forever.
  lifecycle_rule {
    condition {
      age = var.staging_retention_days
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.services]
}

resource "google_storage_bucket_iam_binding" "staging-bucket-iam" {
  bucket = google_storage_bucket.staging_bucket.name
  role   = "roles/storage.objectUser"

  members = ["serviceAccount:${local.apply_sa_email}"]
}

# Object reads for plan are scoped to this bucket only, so the identity exposed
# to PR code cannot read other buckets' contents.
resource "google_storage_bucket_iam_member" "staging_bucket_plan_object_read" {
  count  = var.deploy_sa_email != null ? 0 : 1
  bucket = google_storage_bucket.staging_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.gha_tf_plan[0].email}"
}

#tfsec:ignore:google-storage-bucket-encryption-customer-key
resource "google_storage_bucket" "tf-state" {
  name                        = "${var.project}-tfstate"
  force_destroy               = false
  location                    = var.bucket_location
  storage_class               = "STANDARD"
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }
  labels = {
    owner       = var.owner
    terraformed = "true"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.services]
}

# SECURITY: only the apply identity may WRITE state, and this binding is
# authoritative so nothing can pick up write access out of band.
#
# The plan identity is deliberately absent. `terraform plan` executes
# attacker-controllable config from pull requests -- a `data "external"` block
# runs arbitrary code during plan with whatever credentials the job holds. Write
# access here would let it poison the state file that the next apply on main
# acts on. Versioning makes that recoverable, not prevented.
#
# Read-only also means plan cannot take the state lock, hence
# TF_CLI_ARGS_plan=-lock=false in the plan workflow. Safe (plan never writes
# state) and fails closed: without it the job errors instead of gaining write.
resource "google_storage_bucket_iam_binding" "tfstate-bucket-iam" {
  bucket  = google_storage_bucket.tf-state.name
  role    = "roles/storage.objectUser"
  members = ["serviceAccount:${local.apply_sa_email}"]
}

resource "google_storage_bucket_iam_member" "tfstate_bucket_plan_read" {
  count  = var.deploy_sa_email != null ? 0 : 1
  bucket = google_storage_bucket.tf-state.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.gha_tf_plan[0].email}"
}
