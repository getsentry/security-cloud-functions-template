variable "name" {
  type        = string
  description = "Name of the cloud function"
}

variable "source_dir" {
  type        = string
  description = "Directory containing source code, relative or absolute (relative preferred, think about CI/CD!)"
}

variable "location" {
  type        = string
  description = "The location of this cloud function"
  default     = "us-west1"
}

variable "description" {
  type        = string
  description = "Description for the cloud function"
  default     = null
}

variable "runtime" {
  type        = string
  description = "Function runtime, default python 3.9"
  default     = "python39"
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
}

variable "execution_timeout" {
  type        = number
  description = "Amount of time function can execute before timing out, in seconds"
  default     = 60
}

variable "available_memory_mb" {
  type        = string
  description = "Amount of memory assigned to each execution"
  default     = "128M"
}

variable "temp_zip_output_dir" {
  type        = string
  description = "Dir path where temporary archive will be written"
  default     = "/tmp"
}

variable "deploy_sa_email" {
  type        = string
  description = "Service account used for CD in GitHub actions"
  # TODO: Remove hardcoded account once deployment SA moved to terraform
  default = "gha-cloud-functions-deployment@jeffreyhung-test.iam.gserviceaccount.com"
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

variable "ingress_settings" {
  description = "Available ingress settings. ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB."
  type        = string
  default     = "ALLOW_ALL"

}

variable "files_to_exclude" {
  description = "files to exclude from the "
  type        = list(string)
  default = [
    "terragrunt.hcl",
    ".terraform.lock.hcl",
    "locals.tf",
    "variables.tf",
    "main.tf",
    "terraform.tfstate",
    "terraform.tfstate.backup",
    ".terraform.tfstate.lock.info",
    ".terragrunt-module-manifest",
    ".terragrunt-source-manifest",
    ".terragrunt-source-version",
  ]
}
