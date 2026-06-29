variable "name" {
  description = "EC2, 보안그룹, IAM 리소스 이름 prefix."
  type        = string
}

variable "vpc_id" {
  description = "EC2 인스턴스를 실행할 VPC ID."
  type        = string
}

variable "subnet_id" {
  description = "EC2 인스턴스를 실행할 subnet ID."
  type        = string
}

variable "ami_id" {
  description = "선택 AMI ID. 비워두면 최신 Amazon Linux 2023 x86_64 AMI를 사용한다."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "이미 생성되어 있는 EC2 key pair 이름."
  type        = string
}

variable "allowed_ssh_cidr_blocks" {
  description = "SSH 접속을 허용할 CIDR 목록."
  type        = list(string)
  default     = []
}

variable "ingress_rules" {
  description = "추가 security group ingress rule 목록."
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = []
}

variable "root_volume_size_gb" {
  description = "Root EBS volume 크기."
  type        = number
  default     = 30
}

variable "startup_commands" {
  description = "Docker/Git 기본 설치 후 실행할 shell command."
  type        = string
  default     = ""
}

variable "iam_ssm_parameter_arns" {
  description = "이 EC2가 읽을 수 있는 SSM parameter ARN 목록."
  type        = list(string)
  default     = []
}

variable "kms_key_arns" {
  description = "SecureString 복호화에 필요한 선택 KMS key ARN 목록."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "모든 리소스에 적용할 tag."
  type        = map(string)
  default     = {}
}
