# Negative control for tests/assert-site-registration.sh: a bare aws_s3_object
# written the way the module must NOT be (provider 4.8 default ACL, or an
# explicit one). The test proves its ACL check rejects these plans.
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

variable "acl" {
  type    = string
  default = null # null leaves the provider 4.8 default ("private")
}

resource "aws_s3_object" "control" {
  bucket  = "fixture-registry"
  key     = "registrations/v1/o/s/e.json"
  content = "{}"
  acl     = var.acl
}
