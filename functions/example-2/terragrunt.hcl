terraform {
  source = "../../modules/cloud-function"
}

# TODO: move dependency to module
dependency "infra" {
  config_path = "../../infrastructure"
  mock_outputs = {
    secret_ids = {
      test_key_1 = "test_key_1"
    }
  }
}

inputs = {
  name              = "cloud-func-gen1"
  description       = "example for cloud function gen1"
  source_dir        = "."
  execution_timeout = 30
  secrets = [
    {
      key     = "test_key"
      secret  = dependency.infra.outputs.secret_ids["test_key_1"]
      version = "latest"
    }
  ]
}