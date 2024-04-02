resource "google_secret_manager_secret" "secret" {
  for_each  = { for s in local.secrets : s => s }
  secret_id = each.value
  replication {
    auto {}
  }
}

output "secret_ids" {
  value = { for s in google_secret_manager_secret.secret : s.secret_id => s.secret_id }
}

locals {
  secrets = [
    "test_key_1",
    "test_key_2"
  ]
}
