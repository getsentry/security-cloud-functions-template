variable "project" {
  type        = string
  description = "GCP project ID for deployment"
}

variable "project_num" {
  type        = string
  description = "GCP project number, used to build the workload identity audience"
}

variable "region" {
  type        = string
  description = "GCP region for deployment"
}

variable "bucket_location" {
  type        = string
  description = "Location for the state and staging buckets"
}

variable "deploy_sa_email" {
  type        = string
  description = "Bring-your-own service account for apply. Null means create our own."
  default     = null
}

variable "github_repository" {
  type        = string
  description = "GitHub repository in 'owner/repo' form that is allowed to authenticate via workload identity"
}

variable "owner" {
  type        = string
  description = "The owner of the project, used for tagging resources and future ownership tracking"
}

variable "staging_retention_days" {
  type        = number
  description = "Days before old Cloud Function source archives are deleted from the staging bucket. Source objects are content-addressed, so superseded archives are never referenced again."
  default     = 90
}

variable "image_versions_to_keep" {
  type        = number
  description = "Most recent container image versions always retained per Cloud Run service, regardless of age. Keep enough to roll back to."
  default     = 20
}

variable "image_retention_days" {
  type        = number
  description = "Tagged container images older than this are deleted from Artifact Registry, except the most recent `image_versions_to_keep`."
  default     = 90
}
