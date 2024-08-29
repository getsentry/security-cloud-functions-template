variable "project" {
  type = string
}

variable "secret_ids" {}

variable "name" {
  type        = string
  description = "Name of the cloud function"
}

variable "description" {
  type        = string
  description = "Description for the cloud function"
  default     = null
}

variable "source_dir" {
  type        = string
  description = "Directory containing source code, relative or absolute (relative preferred, think about CI/CD!)"
}

variable "runtime" {
  type        = string
  description = "Function runtime, default python 3.11"
  default     = "python311"
  nullable    = false
}

variable "source_object_prefix" {
  type        = string
  description = "String prefixing source upload objects"
  default     = "src-"
}

variable "source_upload_bucket" {
  type        = string
  description = "Bucket where source files are uploaded before cloud function deployment"
  default     = "cloud-function-source-staging"
}

variable "function_entrypoint" {
  type        = string
  description = "Entrypoint function on cloud function trigger"
  default     = "main"
}

variable "trigger_http" {
  type        = bool
  description = "Whether or not the trigger for this cloud function should be an HTTP endpoint"
  default     = true
  nullable    = false
}

variable "execution_timeout" {
  type        = number
  description = "Amount of time function can execute before timing out, in seconds"
  default     = 60
  nullable    = false
}

variable "available_memory_mb" {
  type        = number
  description = "Amount of memory assigned to each execution"
  default     = 128
  nullable    = false
}

variable "temp_zip_output_dir" {
  type        = string
  description = "Dir path where temporary archive will be written"
  default     = "/tmp"
}

variable "deploy_sa_email" {
  type        = string
  description = "Service account used for CD in GitHub actions"
}

variable "environment_variables" {
  type        = map(any)
  description = "Environment variables available to the function"
  default     = null
}

variable "secret_environment_variables" {
  description = "list of secrets to mount as env vars"
  type = list(object({
    key     = string
    secret  = string
    version = string
  }))

  default = []
}

variable "files_to_exclude" {
  description = "files to exclude from the "
  type        = list(string)
  default = [
    "terraform.yaml",
  ]
}
