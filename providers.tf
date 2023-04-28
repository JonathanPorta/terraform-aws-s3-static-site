terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.8.0"
    }
    betteruptime = {
      # https://github.com/BetterStackHQ/terraform-provider-better-uptime/blob/master/CHANGELOG.md
      source  = "BetterStackHQ/better-uptime"
      version = "~> 0.3.15"
    }
  }
}
