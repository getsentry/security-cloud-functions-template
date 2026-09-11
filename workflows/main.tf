# Every subdirectory of workflows/ containing a terraform.yaml becomes a Cloud
# Workflow. Nothing else needs editing to add one -- see README.md.

variable "project" {}
variable "region" {}
variable "owner" {}
# From the other loaders, so every name a workflow references can be checked at
# plan time instead of failing at apply with a 404 or at runtime with a 403.
variable "function_names" {}
variable "cloudrun_names" {}
variable "topic_names" {}

locals {
  terraform_files = fileset(path.module, "*/terraform.yaml")

  configs = {
    for f in local.terraform_files :
    dirname(f) => yamldecode(file("${path.module}/${f}"))
  }

  trigger_cfg = { for d, c in local.configs : d => try(merge(c["workflow-trigger"]), {}) }

  allowed_top_keys     = ["name", "description", "functions", "cloudruns", "bucket", "workflow", "workflow-trigger"]
  allowed_trigger_keys = ["criteria", "pubsub_topic"]

  triggers = { for d, c in local.configs : d => c if contains(keys(c), "workflow-trigger") }

  # Names this config references that do not exist, per list.
  unknown_functions = { for d, c in local.configs : d => setsubtract(toset(try(c["functions"], [])), var.function_names) }
  unknown_cloudruns = { for d, c in local.configs : d => setsubtract(toset(try(c["cloudruns"], [])), var.cloudrun_names) }
  unknown_workflows = { for d, c in local.configs : d => setsubtract(toset(try(c["workflow"], [])), toset(keys(local.configs))) }
}

resource "terraform_data" "config_validation" {
  for_each = local.configs
  input    = each.key

  lifecycle {
    precondition {
      condition     = contains(keys(each.value), "name")
      error_message = "workflows/${each.key}/terraform.yaml is missing the required `name` key."
    }

    precondition {
      condition     = try(each.value["name"], each.key) == each.key
      error_message = "workflows/${each.key}/terraform.yaml has name '${try(each.value["name"], "")}' but lives in directory '${each.key}'. They must match."
    }

    precondition {
      condition     = fileexists("${path.module}/${each.key}/workflow.yaml")
      error_message = "workflows/${each.key}/workflow.yaml does not exist. Every workflow directory needs both terraform.yaml (the Terraform config) and workflow.yaml (the workflow definition itself)."
    }

    precondition {
      condition     = length(setsubtract(keys(each.value), local.allowed_top_keys)) == 0
      error_message = "workflows/${each.key}/terraform.yaml has unknown top-level key(s): ${join(", ", setsubtract(keys(each.value), local.allowed_top_keys))}. Valid keys: ${join(", ", local.allowed_top_keys)}."
    }

    precondition {
      condition     = length(local.unknown_functions[each.key]) == 0
      error_message = "workflows/${each.key}/terraform.yaml lists function(s) that are not in functions/: ${join(", ", local.unknown_functions[each.key])}. Known functions: ${join(", ", sort(var.function_names))}."
    }

    precondition {
      condition     = length(local.unknown_cloudruns[each.key]) == 0
      error_message = "workflows/${each.key}/terraform.yaml lists cloudrun(s) that are not in cloudruns/: ${join(", ", local.unknown_cloudruns[each.key])}. Known services: ${join(", ", sort(var.cloudrun_names))}."
    }

    precondition {
      condition     = length(local.unknown_workflows[each.key]) == 0
      error_message = "workflows/${each.key}/terraform.yaml lists workflow(s) that are not in workflows/: ${join(", ", local.unknown_workflows[each.key])}. Known workflows: ${join(", ", sort(keys(local.configs)))}."
    }

    precondition {
      condition     = length(setsubtract(keys(local.trigger_cfg[each.key]), local.allowed_trigger_keys)) == 0
      error_message = "workflows/${each.key}/terraform.yaml has unknown key(s) under workflow-trigger: ${join(", ", setsubtract(keys(local.trigger_cfg[each.key]), local.allowed_trigger_keys))}. Valid keys: ${join(", ", local.allowed_trigger_keys)}."
    }

    precondition {
      condition     = !contains(keys(each.value), "workflow-trigger") || try(local.trigger_cfg[each.key]["criteria"], null) != null
      error_message = "workflows/${each.key}/terraform.yaml has a workflow-trigger with no `criteria`."
    }

    precondition {
      condition     = try(local.trigger_cfg[each.key]["pubsub_topic"], null) == null || contains(var.topic_names, try(local.trigger_cfg[each.key]["pubsub_topic"], ""))
      error_message = "workflows/${each.key}/terraform.yaml workflow-trigger.pubsub_topic '${try(local.trigger_cfg[each.key]["pubsub_topic"], "")}' is not a topic defined in pubsubs/. Known topics: ${join(", ", sort(var.topic_names))}."
    }
  }
}

module "workflows" {
  source   = "../modules/cloud-workflow"
  for_each = local.configs

  name               = each.key
  description        = try(each.value["description"], null)
  functions          = toset(try(each.value["functions"], []))
  cloudruns          = toset(try(each.value["cloudruns"], []))
  bucket             = toset(try(each.value["bucket"], []))
  workflow           = toset(try(each.value["workflow"], []))
  workflow_yaml_file = "${path.module}/${each.key}/workflow.yaml"

  project = var.project
  region  = var.region
  owner   = var.owner

  depends_on = [terraform_data.config_validation]
}

module "workflows-ingest-trigger" {
  source   = "../modules/eventarc-workflow-trigger"
  for_each = local.triggers

  name                = "${each.key}-trigger"
  location            = var.region
  workflow_project_id = var.project
  workflow_id         = module.workflows[each.key].workflow_id
  criteria            = local.trigger_cfg[each.key]["criteria"]
  pubsub_topic        = try(local.trigger_cfg[each.key]["pubsub_topic"], null)
  owner               = var.owner
}
