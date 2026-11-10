terraform {
  # Same floor as the root module. `precondition` (1.2) carries the checks that
  # compare two inputs; variable validation can only see its own variable until
  # Terraform 1.9. `optional()` object attributes need 1.3, so the optional
  # overrides are separate nullable variables instead.
  required_version = ">= 1.2"

  required_providers {
    # Same pin the root module and its consumers already use. No other provider.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.8.0"
    }
  }
}
