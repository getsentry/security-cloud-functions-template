# Every subdirectory of cloudruns/ containing a terraform.yaml becomes a Cloud
# Run service. Nothing else needs editing to add one -- see README.md.

variable "project" {}
variable "region" {}
variable "secret_ids" {}
variable "local_variables" {}
variable "image_registry" {}
variable "image_tag" {}
variable "owner" {}

locals {
  terraform_files = fileset(path.module, "*/terraform.yaml")

  configs = {
    for f in local.terraform_files :
    dirname(f) => yamldecode(file("${path.module}/${f}"))
  }

  run_cfg  = { for d, c in local.configs : d => try(merge(c["cloud-run"]), {}) }
  cron_cfg = { for d, c in local.configs : d => try(merge(c["cron"]), {}) }

  allowed_top_keys  = ["name", "description", "cloud-run", "cron"]
  allowed_run_keys  = ["image", "port", "cpu", "memory", "cpu_idle", "concurrency", "min_instances", "max_instances", "request_timeout", "execution_environment", "ingress", "allow_unauthenticated", "deletion_protection", "environment_variables", "secrets"]
  allowed_cron_keys = ["description", "schedule", "time_zone", "attempt_deadline", "http_method", "path"]

  services = { for d, c in local.configs : d => c if contains(keys(c), "cloud-run") }
  crons    = { for d, c in local.services : d => c if contains(keys(c), "cron") }

  missing_secrets = {
    for d, c in local.configs :
    d => [for s in try(local.run_cfg[d]["secrets"], []) : s.secret if !contains(keys(var.secret_ids), s.secret)]
  }

  # An explicit `image:` wins, for services whose images are built elsewhere.
  # Otherwise the image is the one the build workflow pushes for this directory.
  images = {
    for d, c in local.services :
    d => try(local.run_cfg[d]["image"], null) != null ? local.run_cfg[d]["image"] : "${var.image_registry}/${d}:${var.image_tag}"
  }
}

# Fails at plan time, before anything is created, naming the file and the key.
resource "terraform_data" "config_validation" {
  for_each = local.configs
  input    = each.key

  lifecycle {
    precondition {
      condition     = contains(keys(each.value), "name")
      error_message = "cloudruns/${each.key}/terraform.yaml is missing the required `name` key."
    }

    precondition {
      condition     = try(each.value["name"], each.key) == each.key
      error_message = "cloudruns/${each.key}/terraform.yaml has name '${try(each.value["name"], "")}' but lives in directory '${each.key}'. They must match -- the directory name is the service name and the image name."
    }

    precondition {
      condition     = contains(keys(each.value), "cloud-run")
      error_message = "cloudruns/${each.key}/terraform.yaml is missing the required `cloud-run` block. See cloudruns/README.md."
    }

    # Without a Dockerfile the build workflow has nothing to push, and apply
    # would fail much later with an image-not-found error from Cloud Run.
    precondition {
      condition     = try(local.run_cfg[each.key]["image"], null) != null || fileexists("${path.module}/${each.key}/Dockerfile")
      error_message = "cloudruns/${each.key}/ has no Dockerfile. Add one, or set `image:` in terraform.yaml to deploy an image you build elsewhere."
    }

    precondition {
      condition     = length(setsubtract(keys(each.value), local.allowed_top_keys)) == 0
      error_message = "cloudruns/${each.key}/terraform.yaml has unknown top-level key(s): ${join(", ", setsubtract(keys(each.value), local.allowed_top_keys))}. Valid keys: ${join(", ", local.allowed_top_keys)}."
    }

    precondition {
      condition     = length(setsubtract(keys(local.run_cfg[each.key]), local.allowed_run_keys)) == 0
      error_message = "cloudruns/${each.key}/terraform.yaml has unknown key(s) under cloud-run: ${join(", ", setsubtract(keys(local.run_cfg[each.key]), local.allowed_run_keys))}. Valid keys: ${join(", ", local.allowed_run_keys)}."
    }

    precondition {
      condition     = length(setsubtract(keys(local.cron_cfg[each.key]), local.allowed_cron_keys)) == 0
      error_message = "cloudruns/${each.key}/terraform.yaml has unknown key(s) under cron: ${join(", ", setsubtract(keys(local.cron_cfg[each.key]), local.allowed_cron_keys))}. Valid keys: ${join(", ", local.allowed_cron_keys)}."
    }

    precondition {
      condition     = !contains(keys(each.value), "cron") || try(local.cron_cfg[each.key]["schedule"], null) != null
      error_message = "cloudruns/${each.key}/terraform.yaml has a `cron` block with no `schedule`. Add one, e.g. schedule: \"0 * * * *\" for hourly."
    }

    precondition {
      condition     = length(local.missing_secrets[each.key]) == 0
      error_message = "cloudruns/${each.key}/terraform.yaml references secret(s) not declared in the root `secrets` list in terraform.tfvars: ${join(", ", local.missing_secrets[each.key])}. Add the name(s) there, then add the value(s) -- see secrets/readme.md."
    }
  }
}

module "cloud_run" {
  source   = "../modules/cloud-run"
  for_each = local.services

  name        = each.key
  description = try(each.value["description"], null)
  image       = local.images[each.key]

  port                  = try(local.run_cfg[each.key]["port"], null)
  cpu                   = try(local.run_cfg[each.key]["cpu"], null)
  memory                = try(local.run_cfg[each.key]["memory"], null)
  cpu_idle              = try(local.run_cfg[each.key]["cpu_idle"], null)
  concurrency           = try(local.run_cfg[each.key]["concurrency"], null)
  min_instances         = try(local.run_cfg[each.key]["min_instances"], null)
  max_instances         = try(local.run_cfg[each.key]["max_instances"], null)
  request_timeout       = try(local.run_cfg[each.key]["request_timeout"], null)
  execution_environment = try(local.run_cfg[each.key]["execution_environment"], null)
  ingress               = try(local.run_cfg[each.key]["ingress"], null)
  allow_unauthenticated = try(local.run_cfg[each.key]["allow_unauthenticated"], null)
  deletion_protection   = try(local.run_cfg[each.key]["deletion_protection"], null)

  # "$name" resolves from local_variables; no match is passed through verbatim.
  environment_variables = {
    for k, v in try(local.run_cfg[each.key]["environment_variables"], {}) :
    k => startswith(tostring(v), "$") ? lookup(var.local_variables, substr(tostring(v), 1, -1), tostring(v)) : tostring(v)
  }

  secret_environment_variables = try(local.run_cfg[each.key]["secrets"], [])

  location   = var.region
  project    = var.project
  secret_ids = var.secret_ids
  owner      = var.owner

  depends_on = [terraform_data.config_validation]
}

module "cloud_run_cron" {
  source   = "../modules/cloud-run-cron"
  for_each = local.crons

  name             = each.key
  description      = try(local.cron_cfg[each.key]["description"], try(each.value["description"], null))
  schedule         = try(local.cron_cfg[each.key]["schedule"], null)
  time_zone        = try(local.cron_cfg[each.key]["time_zone"], null)
  attempt_deadline = try(local.cron_cfg[each.key]["attempt_deadline"], null)
  http_method      = try(local.cron_cfg[each.key]["http_method"], null)
  path             = try(local.cron_cfg[each.key]["path"], null)

  target_service_name = module.cloud_run[each.key].service_name
  target_url          = module.cloud_run[each.key].service_url
  target_project      = var.project
  target_region       = var.region
  owner               = var.owner
}
