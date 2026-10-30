# State in the repo's own R2 bucket (releases-backup, EU), one key per stack: infra/terraform
# (the bucket) takes terraform/releases.tfstate. Creds (AWS_ACCESS_KEY_ID/SECRET
# of the R2 token releases-terraform-state) come in memory from
# secrets/releases-terraform-state.env.age via `mise run tf:github`.
terraform {
  backend "s3" {
    bucket = "releases-backup"
    key    = "terraform/github.tfstate"
    region = "auto"
    endpoints = {
      s3 = "https://fbc5bc4bfe835ba7165482b7c8f500ee.eu.r2.cloudflarestorage.com"
    }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
