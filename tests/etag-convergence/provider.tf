# Fixture-only provider: plan runs with no AWS calls and no credentials.
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

variable "source_files" {
  type = string
}

resource "aws_s3_bucket" "app_bucket" {
  bucket = "etag-convergence-fixture"
}
