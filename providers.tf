terraform {
  # Floor set by the private-origin change: `moved` (1.1) keeps the bucket-ACL
  # address refactor from churning existing state, and `precondition` (1.2)
  # rejects contradictory private-origin inputs at plan time. Nothing here needs
  # a newer feature, so the floor is deliberately not raised further.
  required_version = ">= 1.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.8.0"
    }
    betteruptime = {
      source  = "BetterStackHQ/better-uptime"
      version = "~> 0.3.15"
    }
  }
}
