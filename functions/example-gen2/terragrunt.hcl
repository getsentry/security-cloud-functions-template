terraform {
  source = "../../modules/cloud-function-gen2"
}

# TODO: move dependency to module
dependency "infra" {
  config_path = "../..//infrastructure"
  mock_outputs = {
    secret_ids = {
      test_key_1  = "test_key_1"
    }
  }
}

inputs = {
  name              = "example-gen2"
  description       = "gen2 cloud function example"
  source_dir        = "." 
  execution_timeout = 120
  available_memory_mb = "128Mi"

  secrets = [
    {
      key = "example_token"
      secret = dependency.infra.outputs.secret_ids["test_key_1"]
      version = "latest"
    }
  ]
}
