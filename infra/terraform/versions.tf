# Pinned to the provider's latest release (2026-10-30), as Nomadware.io and ephedra pin
# it; bump deliberately. .terraform.lock.hcl (committed) freezes the build + checksums.
terraform {
  required_version = ">= 1.9"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.28.1"
    }
  }
}
