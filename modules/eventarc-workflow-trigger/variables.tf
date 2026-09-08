variable "name" {
  type        = string
  description = "Name of the eventarc trigger"
}

variable "location" {
  type        = string
  description = "Trigger location. Must match the region of the workflow it targets."
}

variable "workflow_project_id" {
  type        = string
  description = "Project ID for the workflow to trigger"
}

variable "workflow_id" {
  type        = string
  description = "ID for the workflow to trigger"
}

variable "pubsub_topic" {
  type        = string
  description = "Name of an existing Pub/Sub topic to consume. Null lets Eventarc create its own, whose name is exposed in the pubsub_topic output."
  default     = null
}

variable "criteria" {
  description = "Event attributes the trigger matches on. At minimum a `type`, e.g. google.cloud.pubsub.topic.v1.messagePublished."
  type = list(object({
    attribute = string
    value     = string
  }))

  validation {
    condition     = length(var.criteria) > 0
    error_message = "workflow-trigger.criteria must list at least one attribute/value pair -- a trigger with no criteria matches nothing."
  }

  validation {
    condition     = contains([for c in var.criteria : c.attribute], "type")
    error_message = "workflow-trigger.criteria must include an entry with attribute: type. Eventarc requires it."
  }
}

variable "owner" {
  type        = string
  description = "The owner of the project, used for tagging resources and future ownership tracking"
}
