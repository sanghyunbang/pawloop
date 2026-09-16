terraform {
  # 1.9 부터 변수 validation 안에서 다른 변수를 볼 수 있다. repo_deploy_key_ssm_parameter_name
  # 이 repo_url 의 형식을 같이 검사하려면 필요하다 — 이 검사가 없으면 https URL 에
  # 배포 키를 붙인 실수를 apply 가 끝나고 서버 안의 로그에서야 알게 된다.
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
