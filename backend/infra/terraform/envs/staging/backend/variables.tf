variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-northeast-2"
}

variable "name_prefix" {
  description = "리소스 이름 prefix."
  type        = string
  default     = "heat-trip-staging"
}

variable "vpc_id" {
  description = "이미 존재하는 VPC ID."
  type        = string
}

variable "subnet_id" {
  description = "Backend EC2를 배치할 기존 subnet ID."
  type        = string
}

variable "key_name" {
  description = "이미 생성되어 있는 EC2 key pair 이름."
  type        = string
}

variable "instance_type" {
  description = "Backend EC2 instance type. AMI가 x86_64 고정이라 t4g 같은 Graviton 타입은 쓸 수 없다."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size_gb" {
  description = "Backend root EBS volume 크기."
  type        = number
  default     = 40
}

variable "allowed_ssh_cidr_blocks" {
  description = "Backend EC2 SSH 접속을 허용할 CIDR 목록."
  type        = list(string)
  default     = []
}

variable "backend_app_allowed_cidr_blocks" {
  description = "Backend app 8080 포트 접근을 허용할 CIDR 목록. 0.0.0.0/0 대신 Loader private CIDR 또는 VPC CIDR를 권장한다."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.backend_app_allowed_cidr_blocks) > 0
    error_message = "backend_app_allowed_cidr_blocks를 최소 1개 설정해야 한다. Loader 또는 VPC private CIDR를 권장한다."
  }
}

variable "repo_url" {
  description = "배포할 Git repository URL. private 저장소는 SSH 형식(git@github.com:소유자/저장소.git)으로 적고 repo_deploy_key_ssm_parameter_name을 같이 준다."
  type        = string

  validation {
    condition     = length(trimspace(var.repo_url)) > 0
    error_message = "repo_url은 비워둘 수 없다."
  }
}

variable "repo_branch" {
  description = "배포할 Git branch."
  type        = string
  default     = "main"
}

variable "repo_deploy_key_ssm_parameter_name" {
  description = "읽기 전용 GitHub deploy key(개인키) 전체를 담은 SSM SecureString parameter 이름. private 저장소를 clone하려면 필요하다. 비우면 인증 없이 clone한다."
  type        = string
  default     = ""

  validation {
    condition = (
      var.repo_deploy_key_ssm_parameter_name == "" ||
      startswith(var.repo_url, "git@") ||
      startswith(var.repo_url, "ssh://")
    )
    error_message = "deploy key를 쓰면 repo_url도 SSH 형식이어야 한다: git@github.com:소유자/저장소.git"
  }
}

variable "app_env_ssm_parameter_name" {
  description = "backend .env 전체 내용을 담은 SSM SecureString parameter 이름."
  type        = string
  default     = ""
}

variable "kms_key_arns" {
  description = "SecureString 복호화에 필요한 선택 KMS key ARN 목록."
  type        = list(string)
  default     = []
}

variable "enable_observability" {
  description = "Prometheus/Grafana compose override 실행 여부."
  type        = bool
  default     = true
}

variable "tags" {
  description = "추가 resource tag."
  type        = map(string)
  default     = {}
}
