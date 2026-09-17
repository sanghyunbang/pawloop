terraform {
  # staging 과 같은 이유로 1.9 이상이다 — 변수 validation 안에서 다른 변수를 본다.
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
