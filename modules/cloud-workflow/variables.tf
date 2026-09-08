variable "name" {
  type        = string
  description = "Name of the cloud workflow"
}

variable "description" {
  type        = string
  description = "Description for the cloud workflow"
  default     = null
}

variable "workflow_yaml_file" {
  type        = string
  description = "Path to the yaml to deploy as a workflow. Read verbatim with file(), so Cloud Workflows $${...} expressions work as written."
}

variable "functions" {
  type        = set(string)
  description = "Cloud Functions this workflow calls. Each one listed here gets an invoker grant for the workflow's service account; a function called from workflow.yaml but missing from this list will fail at runtime with 403."
  default     = []
}

variable "cloudruns" {
  type        = set(string)
  description = "Cloud Run services this workflow calls. Each one gets a run.invoker grant for the workflow's service account."
  default     = []
}

variable "bucket" {
  type        = set(string)
  description = "GCS buckets this workflow reads from. Each one listed here gets an objectViewer grant for the workflow's service account."
  default     = []
}

variable "workflow" {
  type        = set(string)
  description = "Other workflows this workflow calls. Any non-empty value grants project-wide roles/workflows.invoker -- see the note in main.tf."
  default     = []
}

variable "project" {
  type        = string
  description = "GCP project the workflow is deployed into"
}

variable "region" {
  type        = string
  description = "Region the workflow and the functions it invokes live in"
}

variable "owner" {
  type        = string
  description = "The owner of the project, used for tagging resources and future ownership tracking"
}
