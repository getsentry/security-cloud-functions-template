terraform {
  source = "../../modules/cronjob-cloud-function"
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
  config_path = "../example"
  mock_outputs = {
    function_project = "local",
    function_region = "us"
    function_name = "example",
    function_trigger_url = "https://google.com"
  }
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

// module "function-cron-example" {
//   source = "./cloud-function"

//   name              = "cron-example"
//   description       = "An example cloud function run by Cloud Scheduler (cron jobs) every hour"
//   source_dir        = "../functions/cron-example"
//   execution_timeout = 30
// }

// module "cronjob-cron-example" {
//   source = "./cronjob-cloud-function"

//   name             = "cron-example-job"
//   description      = "Example cloud functions cron job"
//   schedule         = "0 * * * *"
//   time_zone        = "America/New_York"
//   attempt_deadline = "320s"

//   target_project       = module.function-cron-example.function_project
//   target_region        = module.function-cron-example.function_region
//   target_function_name = module.function-cron-example.function_name

//   http_method       = "GET"
//   https_trigger_url = module.function-cron-example.function_trigger_url
// }
