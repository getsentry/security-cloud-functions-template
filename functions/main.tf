# Every subdirectory of functions/ containing a terraform.yaml becomes a Cloud
# Function. Nothing else needs editing to add one -- see README.md.

variable "project" {}
variable "region" {}
variable "staging_bucket" {}
variable "secret_ids" {}
variable "local_variables" {}
variable "owner" {}

locals {
  terraform_files = fileset(path.module, "*/terraform.yaml")

  # Keyed by directory, not by the `name` field, so a mismatch between the two
  # can be reported precisely below.
  configs = {
    for f in local.terraform_files :
    dirname(f) => yamldecode(file("${path.module}/${f}"))
  }

  # try(merge(x), {}) yields the block if present, {} if the key is absent OR
  # the block is empty (YAML decodes `key:` to null). A plain conditional
  # (`x == null ? {} : x`) fails type-checking because {} and an object with
  # attributes are different types.
  fn_cfg   = { for d, c in local.configs : d => try(merge(c["cloud-function-gen2"]), {}) }
  cron_cfg = { for d, c in local.configs : d => try(merge(c["cron"]), {}) }

  # Anything not listed here is rejected by the preconditions below, so a typo
  # like `timeout:` for `execution_timeout:` cannot silently deploy the default.
  allowed_top_keys      = ["name", "description", "cloud-function-gen2", "cron"]
  allowed_function_keys = ["runtime", "execution_timeout", "available_memory", "allow_unauthenticated", "function_entrypoint", "environment_variables", "secrets", "ingress_settings", "min_instances", "max_instances"]
  allowed_cron_keys     = ["description", "schedule", "time_zone", "attempt_deadline", "http_method"]

  functions = { for d, c in local.configs : d => c if contains(keys(c), "cloud-function-gen2") }
  crons     = { for d, c in local.functions : d => c if contains(keys(c), "cron") }

  missing_secrets = {
    for d, c in local.configs :
    d => [for s in try(local.fn_cfg[d]["secrets"], []) : s.secret if !contains(keys(var.secret_ids), s.secret)]
  }
}

# Fails at plan time, before anything is created, naming the file and the key.
resource "terraform_data" "config_validation" {
  for_each = local.configs
  input    = each.key

  lifecycle {
    precondition {
      condition     = contains(keys(each.value), "name")
      error_message = "functions/${each.key}/terraform.yaml is missing the required `name` key."
    }

    precondition {
      condition     = try(each.value["name"], each.key) == each.key
      error_message = "functions/${each.key}/terraform.yaml has name '${try(each.value["name"], "")}' but lives in directory '${each.key}'. They must match -- the directory is what gets zipped and deployed."
    }

    precondition {
      condition     = contains(keys(each.value), "cloud-function-gen2")
      error_message = "functions/${each.key}/terraform.yaml is missing the required `cloud-function-gen2` block. See functions/README.md."
    }

    precondition {
      condition     = length(setsubtract(keys(each.value), local.allowed_top_keys)) == 0
      error_message = "functions/${each.key}/terraform.yaml has unknown top-level key(s): ${join(", ", setsubtract(keys(each.value), local.allowed_top_keys))}. Valid keys: ${join(", ", local.allowed_top_keys)}."
    }

    precondition {
      condition     = length(setsubtract(keys(local.fn_cfg[each.key]), local.allowed_function_keys)) == 0
      error_message = "functions/${each.key}/terraform.yaml has unknown key(s) under cloud-function-gen2: ${join(", ", setsubtract(keys(local.fn_cfg[each.key]), local.allowed_function_keys))}. Valid keys: ${join(", ", local.allowed_function_keys)}."
    }

    precondition {
      condition     = length(setsubtract(keys(local.cron_cfg[each.key]), local.allowed_cron_keys)) == 0
      error_message = "functions/${each.key}/terraform.yaml has unknown key(s) under cron: ${join(", ", setsubtract(keys(local.cron_cfg[each.key]), local.allowed_cron_keys))}. Valid keys: ${join(", ", local.allowed_cron_keys)}."
    }

    precondition {
      condition     = !contains(keys(each.value), "cron") || try(local.cron_cfg[each.key]["schedule"], null) != null
      error_message = "functions/${each.key}/terraform.yaml has a `cron` block with no `schedule`. Add one, e.g. schedule: \"0 * * * *\" for hourly."
    }

    precondition {
      condition     = length(local.missing_secrets[each.key]) == 0
      error_message = "functions/${each.key}/terraform.yaml references secret(s) not declared in the root `secrets` list in terraform.tfvars: ${join(", ", local.missing_secrets[each.key])}. Add the name(s) there, then add the value(s) -- see secrets/readme.md."
    }
  }
}

module "cloud_function_gen2" {
  source   = "../modules/cloud-function-gen2"
  for_each = local.functions

  name        = each.key
  description = try(each.value["description"], null)
  source_dir  = "${path.module}/${each.key}"

  runtime               = try(local.fn_cfg[each.key]["runtime"], null)
  execution_timeout     = try(local.fn_cfg[each.key]["execution_timeout"], null)
  available_memory      = try(local.fn_cfg[each.key]["available_memory"], null)
  allow_unauthenticated = try(local.fn_cfg[each.key]["allow_unauthenticated"], null)
  function_entrypoint   = try(local.fn_cfg[each.key]["function_entrypoint"], null)
  ingress_settings      = try(local.fn_cfg[each.key]["ingress_settings"], null)
  min_instances         = try(local.fn_cfg[each.key]["min_instances"], null)
  max_instances         = try(local.fn_cfg[each.key]["max_instances"], null)

  # "$name" resolves from local_variables; no match is passed through verbatim.
  environment_variables = {
    for k, v in try(local.fn_cfg[each.key]["environment_variables"], {}) :
    k => startswith(tostring(v), "$") ? lookup(var.local_variables, substr(tostring(v), 1, -1), tostring(v)) : tostring(v)
  }

  secret_environment_variables = try(local.fn_cfg[each.key]["secrets"], [])

  # `location` must come from the root region. A module-level default here
  # silently deploys the function to one region while its cron trigger, which
  # uses var.region, looks for it in another.
  location       = var.region
  project        = var.project
  staging_bucket = var.staging_bucket
  secret_ids     = var.secret_ids
  owner          = var.owner

  depends_on = [terraform_data.config_validation]
}

module "cronjob-gen2" {
  source   = "../modules/cronjob-gen2"
  for_each = local.crons

  name                 = each.key
  description          = try(local.cron_cfg[each.key]["description"], try(each.value["description"], null))
  schedule             = try(local.cron_cfg[each.key]["schedule"], null)
  time_zone            = try(local.cron_cfg[each.key]["time_zone"], null)
  attempt_deadline     = try(local.cron_cfg[each.key]["attempt_deadline"], null)
  http_method          = try(local.cron_cfg[each.key]["http_method"], null)
  target_function_name = module.cloud_function_gen2[each.key].function_name
  https_trigger_url    = module.cloud_function_gen2[each.key].function_trigger_url

  target_project = var.project
  target_region  = var.region
  owner          = var.owner
}
