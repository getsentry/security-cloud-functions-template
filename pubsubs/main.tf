# Every subdirectory of pubsubs/ containing a terraform.yaml becomes a Pub/Sub
# topic, optionally with a pull subscription, push deliveries to functions or
# Cloud Run services, and a GCS archive sink. See README.md.

variable "project" {}
variable "project_num" {}
variable "region" {}
variable "bucket_location" {}
variable "owner" {}
# From the functions/ and cloudruns/ loaders, so push targets can be validated
# at plan time and resolved to URLs.
variable "function_names" {}
variable "function_urls" {}
variable "cloudrun_names" {}
variable "cloudrun_urls" {}

locals {
  terraform_files = fileset(path.module, "*/terraform.yaml")

  configs = {
    for f in local.terraform_files :
    dirname(f) => yamldecode(file("${path.module}/${f}"))
  }

  pubsub_cfg = { for d, c in local.configs : d => try(merge(c["pubsub"]), {}) }

  allowed_top_keys     = ["name", "description", "pubsub", "sink"]
  allowed_pubsub_keys  = ["topic_name", "subscription_id", "service_account_id", "service_account_display_name", "ttl", "push_to"]
  allowed_push_keys    = ["function", "cloudrun", "path", "ack_deadline_seconds"]
  allowed_sink_keys    = ["sink_name", "retention_days", "max_duration", "max_bytes", "filename_prefix"]
  required_pubsub_keys = ["topic_name"]

  pubsubs = { for d, c in local.configs : d => c if contains(keys(c), "pubsub") }
  sinks   = { for d, c in local.configs : d => c if contains(keys(c), "sink") }

  # Every push_to entry across every config, normalised to one shape and tagged
  # with the config it came from so validation can name the file.
  push_entries = flatten([
    for d, c in local.pubsubs : [
      for p in try(local.pubsub_cfg[d]["push_to"], []) : {
        config = d
        topic  = local.pubsub_cfg[d]["topic_name"]
        # try() around keys(): a malformed entry (e.g. a bare string instead of
        # a map) must produce the clear precondition message below, not a
        # type error from here.
        type                 = contains(try(keys(p), []), "function") ? "function" : "cloudrun"
        name                 = tostring(try(p["function"], try(p["cloudrun"], "")))
        path                 = tostring(try(p["path"], ""))
        ack_deadline_seconds = try(p["ack_deadline_seconds"], 60)
        unknown_keys         = setsubtract(try(keys(p), []), local.allowed_push_keys)
        has_one_target       = length(setintersection(try(keys(p), []), ["function", "cloudrun"])) == 1
      }
    ]
  ])

  # Grouped by target: one push identity per function/service, however many
  # topics feed it. See modules/pubsub-push for why. Only well-formed entries
  # that name a real target get here; the rest are reported by the
  # preconditions and must not also produce a module evaluation error.
  valid_push_entries = [
    for e in local.push_entries : e
    if e.has_one_target && (e.type == "function" ? contains(var.function_names, e.name) : contains(var.cloudrun_names, e.name))
  ]

  push_targets = {
    for key in distinct([for e in local.valid_push_entries : "${e.type}/${e.name}"]) :
    key => {
      type          = split("/", key)[0]
      name          = split("/", key)[1]
      subscriptions = [for e in local.valid_push_entries : { topic = e.topic, path = e.path, ack_deadline_seconds = e.ack_deadline_seconds } if "${e.type}/${e.name}" == key]
    }
  }

  # Per-config problems, computed here so the preconditions below stay readable.
  push_problems = {
    for d, c in local.pubsubs : d => concat(
      [for e in local.push_entries : "push_to entry has unknown key(s): ${join(", ", e.unknown_keys)} (valid: ${join(", ", local.allowed_push_keys)})" if e.config == d && length(e.unknown_keys) > 0],
      [for e in local.push_entries : "push_to entry must name exactly one of `function:` or `cloudrun:`" if e.config == d && !e.has_one_target],
      [for e in local.push_entries : "push_to references function '${e.name}', which is not in functions/ (known: ${join(", ", sort(var.function_names))})" if e.config == d && e.has_one_target && e.type == "function" && !contains(var.function_names, e.name)],
      [for e in local.push_entries : "push_to references cloudrun '${e.name}', which is not in cloudruns/ (known: ${join(", ", sort(var.cloudrun_names))})" if e.config == d && e.has_one_target && e.type == "cloudrun" && !contains(var.cloudrun_names, e.name)],
      [for e in local.push_entries : "push_to path '${e.path}' must start with /" if e.config == d && e.path != "" && !startswith(e.path, "/")],
      # A repeated (topic, target) pair would collapse into one subscription
      # (they are keyed by topic inside the module) and the extra path would
      # vanish with no error. It also means double-delivering every message to
      # the same service, which is almost never intended.
      [for key in local.duplicate_push_pairs : "push_to lists ${split("|", key)[1]} more than once for topic '${split("|", key)[0]}'. List each target once per topic and route on the message inside your handler" if startswith(key, "${local.pubsub_cfg[d]["topic_name"]}|")],
    )
  }

  # (topic|type/name) pairs that appear more than once across all configs.
  duplicate_push_pairs = distinct([
    for e in local.push_entries : "${e.topic}|${e.type}/${e.name}"
    if e.has_one_target && length([for f in local.push_entries : f if f.has_one_target && f.topic == e.topic && f.type == e.type && f.name == e.name]) > 1
  ])
}

# Fails at plan time, before anything is created, naming the file and the key.
resource "terraform_data" "config_validation" {
  for_each = local.configs
  input    = each.key

  lifecycle {
    precondition {
      condition     = contains(keys(each.value), "name")
      error_message = "pubsubs/${each.key}/terraform.yaml is missing the required `name` key."
    }

    precondition {
      condition     = try(each.value["name"], each.key) == each.key
      error_message = "pubsubs/${each.key}/terraform.yaml has name '${try(each.value["name"], "")}' but lives in directory '${each.key}'. They must match."
    }

    precondition {
      condition     = contains(keys(each.value), "pubsub")
      error_message = "pubsubs/${each.key}/terraform.yaml is missing the required `pubsub` block. A sink needs a topic to archive."
    }

    precondition {
      condition     = length(setsubtract(keys(each.value), local.allowed_top_keys)) == 0
      error_message = "pubsubs/${each.key}/terraform.yaml has unknown top-level key(s): ${join(", ", setsubtract(keys(each.value), local.allowed_top_keys))}. Valid keys: ${join(", ", local.allowed_top_keys)}."
    }

    precondition {
      condition     = length(setsubtract(keys(local.pubsub_cfg[each.key]), local.allowed_pubsub_keys)) == 0
      error_message = "pubsubs/${each.key}/terraform.yaml has unknown key(s) under pubsub: ${join(", ", setsubtract(keys(local.pubsub_cfg[each.key]), local.allowed_pubsub_keys))}. Valid keys: ${join(", ", local.allowed_pubsub_keys)}."
    }

    precondition {
      condition     = length(setsubtract(local.required_pubsub_keys, keys(local.pubsub_cfg[each.key]))) == 0
      error_message = "pubsubs/${each.key}/terraform.yaml is missing required key(s) under pubsub: ${join(", ", setsubtract(local.required_pubsub_keys, keys(local.pubsub_cfg[each.key])))}."
    }

    # A pull subscription needs a consumer identity; the two go together.
    precondition {
      condition     = try(local.pubsub_cfg[each.key]["subscription_id"], null) == null || try(local.pubsub_cfg[each.key]["service_account_id"], null) != null
      error_message = "pubsubs/${each.key}/terraform.yaml sets pubsub.subscription_id but not pubsub.service_account_id. A pull subscription needs a service account for its consumer; add one, or remove subscription_id if this topic only pushes."
    }

    precondition {
      condition     = try(local.pubsub_cfg[each.key]["subscription_id"], null) != null || try(local.pubsub_cfg[each.key]["ttl"], null) == null
      error_message = "pubsubs/${each.key}/terraform.yaml sets pubsub.ttl, which only applies to a pull subscription, but has no subscription_id."
    }

    precondition {
      condition     = length(try(local.push_problems[each.key], [])) == 0
      error_message = "pubsubs/${each.key}/terraform.yaml: ${join("; ", try(local.push_problems[each.key], []))}."
    }

    precondition {
      condition     = !contains(keys(each.value), "sink") || length(setsubtract(keys(try(each.value["sink"], {})), local.allowed_sink_keys)) == 0
      error_message = "pubsubs/${each.key}/terraform.yaml has unknown key(s) under sink: ${join(", ", setsubtract(keys(try(each.value["sink"], {})), local.allowed_sink_keys))}. Valid keys: ${join(", ", local.allowed_sink_keys)}."
    }

    precondition {
      condition     = !contains(keys(each.value), "sink") || try(each.value["sink"]["sink_name"], null) != null
      error_message = "pubsubs/${each.key}/terraform.yaml has a `sink` block with no `sink_name`."
    }
  }
}

module "pubsubs" {
  source   = "../modules/pubsub"
  for_each = local.pubsubs

  topic_name                   = local.pubsub_cfg[each.key]["topic_name"]
  subscription_id              = try(local.pubsub_cfg[each.key]["subscription_id"], null)
  service_account_id           = try(local.pubsub_cfg[each.key]["service_account_id"], null)
  service_account_display_name = try(local.pubsub_cfg[each.key]["service_account_display_name"], null)
  ttl                          = try(local.pubsub_cfg[each.key]["ttl"], null)

  gcp_region = var.region
  owner      = var.owner

  depends_on = [terraform_data.config_validation]
}

module "pubsub_push" {
  source   = "../modules/pubsub-push"
  for_each = local.push_targets

  target_type   = each.value.type
  target_name   = each.value.name
  target_url    = each.value.type == "function" ? var.function_urls[each.value.name] : var.cloudrun_urls[each.value.name]
  subscriptions = each.value.subscriptions

  project  = var.project
  location = var.region
  owner    = var.owner

  # Subscriptions reference topics by name; make sure the topic exists first.
  depends_on = [module.pubsubs]
}

module "pubsubs_sink" {
  source   = "../modules/pubsub-sink"
  for_each = local.sinks

  sink_name       = each.value["sink"]["sink_name"]
  topic_name      = module.pubsubs[each.key].pubsub_topic_name
  retention_days  = try(each.value["sink"]["retention_days"], null)
  max_duration    = try(each.value["sink"]["max_duration"], null)
  max_bytes       = try(each.value["sink"]["max_bytes"], null)
  filename_prefix = try(each.value["sink"]["filename_prefix"], null)

  project         = var.project
  project_num     = var.project_num
  bucket_location = var.bucket_location
  owner           = var.owner
}
