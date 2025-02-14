terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">=5.0.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.0.0-rc1"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      domain     = var.domain
      repository = "github.com/agjmills/static-site-vending-machine"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
  alias  = "aws_euw2"
}

provider "cloudflare" {
  api_token = data.aws_secretsmanager_secret_version.cloudflare_api_token.secret_string
}
