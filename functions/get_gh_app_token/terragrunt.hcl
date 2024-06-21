terraform {
  source = "../../modules/cloud-function"
}

# TODO: move dependency to module
dependency "infra" {
  config_path = "../../infrastructure"
}

inputs = {
  name              = "terragrunt-test"
  description       = "terragrunt test function"
  source_dir        = "."
  execution_timeout = 30
  secrets = [
    {
      key     = "GH_APP_ID"
      secret  = dependency.infra.outputs.secret_ids["GH_APP_ID"]
      version = "latest"
    },
    {
      key     = "GH_APP_INSTALLATION_ID"
      secret  = dependency.infra.outputs.secret_ids["GH_APP_INSTALLATION_ID"]
      version = "latest"
    },
    {
      key     = "GH_APP_PRI_KEY"
      secret  = dependency.infra.outputs.secret_ids["GH_APP_PRI_KEY"]
      version = "latest"
    }

  ]
}