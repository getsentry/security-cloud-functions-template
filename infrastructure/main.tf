terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.23.0"
    }

    google-beta = {
      source = "hashicorp/google-beta"
    }
  }
}

provider "google" {
  project = local.project
  region  = local.region
  zone    = local.zone
}


# TODO: move all locals to root level
locals {
  project = "jeffreyhung-test"
  region  = "us-west1"
  zone    = "us-west1-b"
}