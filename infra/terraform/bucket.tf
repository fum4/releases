# The public home of every package's releases (bin/publish writes it, install.sh reads
# it): <pkg>/<tag>/…, <pkg>/latest, <pkg>/install.sh, index.html, index.json, _assets/.
# Public only through its custom domain releases.nomadware.io, which Nomadware.io's
# infra/terraform/r2.tf owns (the zone lives there). EU jurisdiction, like every bucket on
# the account. The bucket is this repo's: its publisher is the only writer.
resource "cloudflare_r2_bucket" "releases" {
  account_id   = var.account_id
  name         = "nomadware-releases"
  jurisdiction = "eu"

  lifecycle {
    # Installs pin versions in it (install.sh --version) and old binaries fetch their own
    # tag from it: a recreate would come back empty and break all of them.
    prevent_destroy = true
  }
}

# The r2.dev URL stays off, so the custom domain is the only public way in (one URL, one
# cache policy, one place to cut access).
resource "cloudflare_r2_managed_domain" "releases" {
  account_id   = var.account_id
  bucket_name  = cloudflare_r2_bucket.releases.name
  jurisdiction = "eu"
  enabled      = false
}
