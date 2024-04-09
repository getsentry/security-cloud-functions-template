output "function_name" {
  value = google_cloudfunctions_function.function.name
}

output "function_project" {
  value = google_cloudfunctions_function.function.project
}

output "function_region" {
  value = google_cloudfunctions_function.function.region
}

output "function_trigger_url" {
  value = google_cloudfunctions_function.function.https_trigger_url
}