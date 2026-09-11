# Consumed by the pubsubs/ and workflows/ loaders so that a reference to a
# function by name can be validated at plan time and resolved to a URL.
output "function_names" {
  description = "Set of every Cloud Function name deployed from this directory."
  value       = toset(keys(module.cloud_function_gen2))
}

output "function_urls" {
  description = "Map of function name to its HTTPS trigger URL."
  value       = { for k, m in module.cloud_function_gen2 : k => m.function_trigger_url }
}
