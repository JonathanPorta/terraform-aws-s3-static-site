# Fixture for tests/assert-site-registration.sh: calls the submodule exactly as
# a consumer would. Plan runs with no AWS calls and no credentials.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.8.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "fixture"
  secret_key                  = "fixture"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

# One object of inputs per case, written by the test script. Unset keys fall
# back to the module defaults.
variable "inputs" {
  type = any
}

module "registration" {
  source = "../../modules/site-registration"

  registry_bucket           = lookup(var.inputs, "registry_bucket", "fixture-registry")
  owner                     = lookup(var.inputs, "owner", "JonathanPorta")
  service                   = lookup(var.inputs, "service", "docsort.io")
  environment               = lookup(var.inputs, "environment", "production")
  url                       = lookup(var.inputs, "url", "https://www.docsort.io/")
  hostname                  = lookup(var.inputs, "hostname", "www.docsort.io")
  registered_domain         = lookup(var.inputs, "registered_domain", "docsort.io")
  checks                    = lookup(var.inputs, "checks", null)
  enabled                   = lookup(var.inputs, "enabled", null)
  id                        = lookup(var.inputs, "id", null)
  override_http_response_ms = lookup(var.inputs, "override_http_response_ms", null)
  override_body_contains    = lookup(var.inputs, "override_body_contains", null)
  override_dns_resolver     = lookup(var.inputs, "override_dns_resolver", null)
  tags                      = lookup(var.inputs, "tags", null)
}

output "document" {
  value = module.registration.document
}

output "key" {
  value = module.registration.key
}
