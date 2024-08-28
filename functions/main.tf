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
  for_each = { for config in local.terraform_configs : config.name => config if contains(keys(config), "cloud-function") }

  name                         = each.value.name
  description                  = each.value.description
  runtime                      = lookup(each.value.cloud-function, "runtime", "python39")
  source_dir                   = lookup(each.value.cloud-function, "source_dir", ".")
  execution_timeout            = lookup(each.value.cloud-function, "timeout", "30")
  trigger_http                 = lookup(each.value.cloud-function, "trigger_http", true)
  available_memory_mb          = lookup(each.value.cloud-function, "available_memory_mb", "30")
  environment_variables        = lookup(each.value.cloud-function, "environment_variables", null)
  secret_environment_variables = lookup(each.value.cloud-function, "secrets", [])
}

module "cloud_function_gen2" {
  source   = "../modules/cloud-function-gen2"
  for_each = { for config in local.terraform_configs : config.name => config if contains(keys(config), "cloud-function-gen2") }

  name                         = each.value.name
  description                  = each.value.description
  runtime                      = lookup(each.value.cloud-function-gen2, "runtime", "python39")
  source_dir                   = lookup(each.value.cloud-function-gen2, "source_dir", ".")
  execution_timeout            = lookup(each.value.cloud-function-gen2, "timeout", "30")
  trigger_http                 = lookup(each.value.cloud-function-gen2, "trigger_http", true)
  available_memory_mb          = lookup(each.value.cloud-function-gen2, "available_memory_mb", "30")
  environment_variables        = lookup(each.value.cloud-function-gen2, "environment_variables", null)
  secret_environment_variables = lookup(each.value.cloud-function-gen2, "secrets", [])
}

module "cronjob" {
  source   = "../modules/cronjob-gen1"
  for_each = { for config in local.terraform_configs : config.name => config if contains(keys(config), "cron") && contains(keys(config), "cloud-function")}

  name                 = each.value.name
  description          = each.value.description
  schedule             = lookup(each.value.cron, "schedule", "")
  time_zone            = lookup(each.value.cron, "time_zone", "")
  attempt_deadline     = lookup(each.value.cron, "attempt_deadline", "")
  http_method          = lookup(each.value.cron, "http_method", "")
  target_project       = local.project
  target_region        = local.region
  target_function_name = module.cloud_function[each.value.name].function_name
  https_trigger_url    = module.cloud_function[each.value.name].function_trigger_url

  depends_on = [
    module.cloud_function
  ]
}

module "cronjob-gen2" {
  source   = "../modules/cronjob-gen2"
  for_each = { for config in local.terraform_configs : config.name => config if contains(keys(config), "cron") && contains(keys(config), "cloud-function-gen2")}

  name                 = each.value.name
  description          = each.value.description
  schedule             = lookup(each.value.cron, "schedule", "")
  time_zone            = lookup(each.value.cron, "time_zone", "")
  attempt_deadline     = lookup(each.value.cron, "attempt_deadline", "")
  http_method          = lookup(each.value.cron, "http_method", "")
  target_project       = local.project
  target_region        = local.region
  target_function_name = module.cloud_function_gen2[each.value.name].function_name
  https_trigger_url    = module.cloud_function_gen2[each.value.name].function_trigger_url

  depends_on = [
    module.cloud_function_gen2
  ]
}