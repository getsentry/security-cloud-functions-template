variable "topic_name" {
  type        = string
  description = "Pub/Sub topic name"
}

variable "subscription_id" {
  type        = string
  description = "Name of a pull subscription to create. Null means no pull subscription (and no consumer service account) -- use this for topics that only push to functions or services."
  default     = null
}

variable "service_account_id" {
  type        = string
  description = "Service account id for the pull consumer. Required when subscription_id is set; the loader enforces this."
  default     = null
}

variable "service_account_display_name" {
  type        = string
  description = "Display name for the consumer service account. Defaults to one derived from subscription_id."
  default     = null
}

variable "gcp_region" {
  type        = string
  description = "Region messages are allowed to be persisted in"
}

variable "ttl" {
  type        = string
  description = "Subscription expiration policy: how long the subscription may sit idle before Pub/Sub deletes it. A duration string in seconds, e.g. \"604800s\" for 7 days. Null means never expire (the module sets an explicit never-expire policy; GCP's default would be 31 days)."
  default     = null

  validation {
    condition     = var.ttl == null || can(regex("^[0-9]+s$", var.ttl))
    error_message = "ttl must be a duration string in seconds, e.g. \"604800s\" for 7 days. A bare number like 7 is not valid."
  }
}

variable "owner" {
  type        = string
  description = "The owner of the project, used for tagging resources and future ownership tracking"
}
