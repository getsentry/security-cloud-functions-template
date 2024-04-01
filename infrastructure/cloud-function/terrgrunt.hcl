
dependency "infra" {
  config_path = "."
  mock_outputs = {
    secret_ids = {
      test_key_1  = "test_key_1"
    }
  }
}