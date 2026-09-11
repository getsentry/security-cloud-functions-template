module "infrastructure" {
  source = "./infrastructure"

  project           = var.project
  project_num       = var.project_num
  region            = var.region
  bucket_location   = var.bucket_location
  deploy_sa_email   = var.deploy_sa_email
  github_repository = var.github_repository
  owner             = var.owner
}

module "secrets" {
  source = "./secrets"

  secrets = var.secrets
  owner   = var.owner

  depends_on = [
    module.infrastructure
  ]
}

module "functions" {
  source = "./functions"

  project         = var.project
  region          = var.region
  staging_bucket  = module.infrastructure.staging_bucket_name
  secret_ids      = module.secrets.secret_ids
  local_variables = local.local_variables
  owner           = var.owner

  depends_on = [
    module.infrastructure
  ]
}

module "cloudruns" {
  source = "./cloudruns"

  project        = var.project
  region         = var.region
  secret_ids     = module.secrets.secret_ids
  image_registry = module.infrastructure.image_registry
  image_tag      = var.cloudrun_image_tag
  # Values that a terraform.yaml can reference with the `$name` syntax.
  local_variables = local.local_variables
  owner           = var.owner

  depends_on = [
    module.infrastructure
  ]
}

# Dependency order: infrastructure -> secrets -> functions, cloudruns -> pubsubs
# -> workflows. Each loader receives the names of what earlier ones created, so
# a reference in a terraform.yaml is checked at plan time rather than failing
# at apply.

module "pubsubs" {
  source = "./pubsubs"

  project         = var.project
  project_num     = var.project_num
  region          = var.region
  bucket_location = var.bucket_location
  owner           = var.owner

  function_names = module.functions.function_names
  function_urls  = module.functions.function_urls
  cloudrun_names = module.cloudruns.service_names
  cloudrun_urls  = module.cloudruns.service_urls

  depends_on = [
    module.infrastructure
  ]
}

module "workflows" {
  source = "./workflows"

  project = var.project
  region  = var.region
  owner   = var.owner

  function_names = module.functions.function_names
  cloudrun_names = module.cloudruns.service_names
  topic_names    = module.pubsubs.topic_names

  depends_on = [
    module.infrastructure
  ]
}

locals {
  apply_sa_email = var.deploy_sa_email != null ? var.deploy_sa_email : module.infrastructure.deploy_sa_email
}
