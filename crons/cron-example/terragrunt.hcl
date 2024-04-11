terraform {
  source = "../../modules/cronjob-gen1"
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

# point to the function that cron job should be running off
dependency "cloud-function" {
  config_path = "../../functions/example"
}

inputs = {
  name                 = "cron-example"
  description          = "An example cloud function run by Cloud Scheduler (cron jobs) every hour"
  schedule             = "0 * * * *"
  time_zone            = "America/New_York"
  attempt_deadline     = "320s"
  http_method          = "GET"
  target_project       = dependency.cloud-function.outputs.function_project
  target_region        = dependency.cloud-function.outputs.function_region
  target_function_name = dependency.cloud-function.outputs.function_name
  https_trigger_url    = dependency.cloud-function.outputs.function_trigger_url
}