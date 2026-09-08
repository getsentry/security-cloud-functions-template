# Read by the build step in .github/workflows/terraform-apply.yaml so it knows
# which images to build and push before applying.
output "images" {
  description = "Map of service directory to the container image it deploys."
  value       = local.images
}

# Consumed by the pubsubs/ and workflows/ loaders so that a reference to a
# service by name can be validated at plan time and resolved to a URL.
output "service_names" {
  description = "Set of every Cloud Run service name deployed from this directory."
  value       = toset(keys(module.cloud_run))
}

output "service_urls" {
  description = "Map of service name to its Cloud Run URL."
  value       = { for k, m in module.cloud_run : k => m.service_url }
}
