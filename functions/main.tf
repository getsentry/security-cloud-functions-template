provider "google" {
  project = local.project
  region  = local.region
  zone    = local.zone
}

locals {
  terraform_files   = fileset(path.module, "*/terraform.yaml")
  terraform_configs = [for f in local.terraform_files : yamldecode(file("${path.module}/${f}"))]
  project           = "jeffreyhung-test"
  project_id        = "jeffreyhung-test"
  project_num       = "546928617664"
  region            = "us-west1"
  zone              = "us-west1-b"
  bucket_location   = "US-WEST1"
  alerts_collection = "alerts"
  sentry_jira_url   = "https://getsentry.atlassian.net"
}

module "cloud_function" {
  source   = "../modules/cloud-function"
  for_each = { for config in local.terraform_configs : config.name => config }

  name                         = each.value.name
  description                  = each.value.description
  runtime                      = lookup(each.value.config, "runtime", "python39")
  source_dir                   = lookup(each.value.config, "source_dir", ".")
  execution_timeout            = lookup(each.value.config, "timeout", "30")
  trigger_http                 = lookup(each.value.config, "trigger_http", "30")
  available_memory_mb          = lookup(each.value.config, "available_memory_mb", "30")
  environment_variables        = lookup(each.value.config, "environment_variables", null)
  secret_environment_variables = lookup(each.value.config, "secrets", [])
}
