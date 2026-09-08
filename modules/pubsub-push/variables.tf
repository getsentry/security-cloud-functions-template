variable "target_type" {
  type        = string
  description = "What receives the pushes: `function` (Cloud Functions gen2) or `cloudrun`."

  validation {
    condition     = contains(["function", "cloudrun"], var.target_type)
    error_message = "target_type must be `function` or `cloudrun`."
  }
}

variable "target_name" {
  type        = string
  description = "Name of the function or Cloud Run service. Also names the push identity, ps-<target_name>."
}

variable "target_url" {
  type        = string
  description = "Root HTTPS URL of the target. Also used as the OIDC audience."
}

variable "subscriptions" {
  description = "One push subscription per topic."
  type = list(object({
    topic                = string
    path                 = string
    ack_deadline_seconds = number
  }))
}

variable "project" {
  type        = string
  description = "GCP project the target lives in"
}

variable "location" {
  type        = string
  description = "Region the target lives in"
}

variable "owner" {
  type        = string
  description = "The owner of the project, used for tagging resources and future ownership tracking"
}
