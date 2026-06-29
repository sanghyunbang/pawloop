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
  description = "Loader EC2를 배치할 기존 subnet ID."
  type        = string
}

variable "key_name" {
  description = "이미 생성되어 있는 EC2 key pair 이름."
  type        = string
}

variable "instance_type" {
  description = "Loader EC2 instance type."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gb" {
  description = "Loader root EBS volume 크기."
  type        = number
  default     = 30
}

variable "allowed_ssh_cidr_blocks" {
  description = "Loader EC2 SSH 접속을 허용할 CIDR 목록."
  type        = list(string)
  default     = []
}

variable "repo_url" {
  description = "public Git repository URL."
  type        = string

  validation {
    condition     = length(trimspace(var.repo_url)) > 0
    error_message = "repo_url은 비워둘 수 없다."
  }
}

variable "repo_branch" {
  description = "clone할 Git branch."
  type        = string
  default     = "main"
}

variable "backend_base_url" {
  description = "k6가 호출할 Backend URL. 보통 http://<backend-private-ip>:8080 형식이다."
  type        = string

  validation {
    condition     = can(regex("^https?://", var.backend_base_url))
    error_message = "backend_base_url은 http:// 또는 https://로 시작해야 한다."
  }
}

variable "k6_env_ssm_parameter_name" {
  description = "k6 env 값을 담은 선택 SSM SecureString parameter 이름."
  type        = string
  default     = ""
}

variable "kms_key_arns" {
  description = "SecureString 복호화에 필요한 선택 KMS key ARN 목록."
  type        = list(string)
  default     = []
}

variable "default_vus" {
  description = "SSM k6 env가 없을 때 k6.env에 기록할 기본 VUS."
  type        = number
  default     = 20
}

variable "default_duration" {
  description = "SSM k6 env가 없을 때 k6.env에 기록할 기본 duration."
  type        = string
  default     = "10m"
}

variable "tags" {
  description = "추가 resource tag."
  type        = map(string)
  default     = {}
}
