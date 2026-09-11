variable "project" {
  type        = string
  description = "The GCP project ID (e.g. my-team-prod). This is the only project identifier you need to set."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project))
    error_message = "project must be a valid GCP project ID: 6-30 chars, lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    # upper() rather than the literal, so this file does not trip the CI check
    # that greps for unreplaced placeholders.
    condition     = !can(regex(upper("changeme"), var.project))
    error_message = "project is still the placeholder value. Run `sbin/bootstrap`, or edit terraform.tfvars."
  }
}

variable "project_num" {
  type        = string
  description = "The GCP project number (digits only). Used to build the workload identity audience and the Pub/Sub service agent email. `sbin/bootstrap` fills this in for you; find it with `gcloud projects describe <project> --format='value(projectNumber)'`."

  validation {
    condition     = can(regex("^[0-9]+$", var.project_num))
    error_message = "project_num must be the numeric project number, not the project ID."
  }
}

variable "region" {
  type        = string
  description = "The GCP region for regional resources (Cloud Functions, Workflows, Eventarc, Cloud Scheduler)."

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must look like us-west1 or europe-west4."
  }
}

variable "zone" {
  type        = string
  description = "The GCP zone. Only used as the provider default; no resource in this template is zonal."

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "zone must look like us-west1-b."
  }
}

variable "bucket_location" {
  type        = string
  description = "Location for GCS buckets created by this template (state, function staging, Pub/Sub sinks). Can be a multi-region (US), dual-region, or region (US-WEST1)."

  validation {
    condition     = can(regex("^[A-Z0-9-]+$", var.bucket_location))
    error_message = "bucket_location must be uppercase, e.g. US or US-WEST1."
  }
}

variable "github_repository" {
  type        = string
  description = "GitHub repository in 'owner/repo' form that is allowed to authenticate via workload identity. Tokens from any other repository are rejected at the provider level."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must be in 'owner/repo' form, e.g. getsentry/secure-cloud-functions-template."
  }
}

variable "owner" {
  type        = string
  description = "Owning team, applied as the `owner` label on every resource. Must be a valid GCP label value."

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,63}$", var.owner))
    error_message = "owner must be a valid GCP label value: lowercase letters, digits, hyphens and underscores only (no spaces or capitals). e.g. team-security."
  }
}

variable "deploy_sa_email" {
  type        = string
  description = "Bring-your-own service account for `terraform apply`. Leave null to have this template create its own workload identity pool and service accounts. See README."
  default     = null
}

variable "secrets" {
  type        = list(string)
  description = "Secret Manager secrets to create (names only -- values are added out of band, see secrets/readme.md). Shared across functions and workflows."
  default     = []

  validation {
    condition     = alltrue([for s in var.secrets : can(regex("^[A-Za-z0-9_-]{1,255}$", s))])
    error_message = "Secret names may only contain letters, digits, underscores and hyphens."
  }
}

variable "cloudrun_image_tag" {
  type        = string
  description = "Tag of the Cloud Run container images to deploy. CI sets this to the commit SHA of the images it just built. There is deliberately no default: images are only ever built and pushed by CI, so a local apply cannot know a tag that exists. `sbin/tf-plan` and `sbin/bootstrap` pass the current commit; for anything else use -var cloudrun_image_tag=<sha>. A service can opt out by setting `image:` in its terraform.yaml."
  nullable    = false

  validation {
    condition     = length(var.cloudrun_image_tag) > 0 && var.cloudrun_image_tag != "latest"
    error_message = "cloudrun_image_tag must be a specific tag such as a commit SHA. CI never pushes `latest`, so deploying it would fail or, worse, serve a stale image."
  }
}

variable "template_variables" {
  type        = map(string)
  description = "Extra values you want to reference from a terraform.yaml with the `$name` syntax, e.g. {slack_channel = \"#alerts\"}. `project`, `region`, `zone` and `owner` are always available and do not need to be listed here."
  default     = {}
}

locals {
  # Values a terraform.yaml can reference as `$name` in environment_variables.
  local_variables = merge(
    {
      project = var.project
      region  = var.region
      zone    = var.zone
      owner   = var.owner
    },
    var.template_variables,
  )
}
