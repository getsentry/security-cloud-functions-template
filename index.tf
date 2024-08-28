module "functions" {
  source = "./functions"

  project    = local.project
  region     = local.region
  project_id = local.project_id
  secret_ids = module.infrastructure.secret_ids

  depends_on = [
    module.infrastructure
  ]
}

module "infrastructure" {
  source = "./infrastructure"

  project    = local.project
  region     = local.region
  project_id = local.project_id
}
