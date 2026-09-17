variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-northeast-2"
}

variable "name_prefix" {
  description = "리소스 이름 prefix."
  type        = string
  default     = "pawloop-prod"
}

variable "vpc_id" {
  description = "이미 존재하는 VPC ID."
  type        = string
}

variable "subnet_id" {
  description = "Backend EC2를 배치할 기존 subnet ID. 퍼블릭 서브넷이어야 한다 — Elastic IP 를 붙인다."
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
  description = <<-EOT
    Root EBS volume 크기. 여기에는 OS · 도커 이미지 · 저장소 클론 · Gradle 캐시가 들어간다.
    **DB 는 여기 없다** — data_volume_size_gb 의 별도 볼륨에 있다.
  EOT
  type        = number
  default     = 40
}

# ── DB 를 서버에서 떼어낸다 ─────────────────────────────────────────
#
# 부팅 스크립트를 고치면 user_data_replace_on_change 때문에 인스턴스가 교체된다.
# root 볼륨은 그때 같이 사라지므로, 거기에 DB 를 두면 배포할 때마다 데이터가 날아간다.
# staging 에서 실제로 세 번 날렸다 (#600).
variable "data_volume_size_gb" {
  description = "DB 데이터 전용 EBS volume 크기. 인스턴스를 교체해도 이 볼륨은 남는다."
  type        = number
  default     = 20
}

variable "data_volume_type" {
  description = "DB 볼륨 타입. gp3 는 크기와 무관하게 3000 IOPS 를 기본으로 준다."
  type        = string
  default     = "gp3"
}

variable "allowed_ssh_cidr_blocks" {
  description = <<-EOT
    SSH(22) 접속을 허용할 CIDR 목록. **내 공인 IP 하나만 적는다** (`x.x.x.x/32`).
    장소를 옮기면 바뀌므로 그때 여기를 고치고 apply 한다 — 절차는 이슈 #607.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.allowed_ssh_cidr_blocks) > 0
    error_message = "allowed_ssh_cidr_blocks 를 최소 1개 설정해야 한다. 비우면 서버에 들어갈 방법이 없다."
  }

  validation {
    condition     = !contains(var.allowed_ssh_cidr_blocks, "0.0.0.0/0")
    error_message = "SSH 를 0.0.0.0/0 으로 열지 않는다. 22번 포트는 전 세계 스캔 대상이다."
  }
}

variable "domain_name" {
  description = <<-EOT
    백엔드가 응답할 호스트 이름. 예: api.pawloop.app

    Caddy 가 이 이름으로 Let's Encrypt 인증서를 받는다. 그래서 **이 이름의 DNS A 레코드가
    이 서버를 가리키고 있어야** 발급이 된다 — 이 구성은 그 레코드도 함께 만든다.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.domain_name))
    error_message = "domain_name 은 호스트 이름이다. 스킴(https://)이나 경로를 붙이지 않는다."
  }
}

variable "site_domain_name" {
  description = <<-EOT
    소개·약관 페이지가 응답할 호스트 이름. 예: pawloop.app — 이슈 #611.

    **스토어가 공개 개인정보처리방침 URL 을 요구한다.** 앱 심사에 적을 주소가 여기서 나온다.

    `domain_name`(api.…)과 **다른 이름**이다. 같은 서버·같은 Caddy 가 둘 다 받고, 이름으로
    갈라 하나는 백엔드로 넘기고 하나는 정적 문서를 그린다. 인증서도 이름마다 따로 받으므로
    이 레코드도 있어야 발급이 된다.

    비워 두면 그 사이트를 안 띄운다 — 도메인이 아직 없을 때 전체가 막히지 않게.
  EOT
  type        = string
  default     = ""

  validation {
    condition = var.site_domain_name == "" || can(regex(
      "^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.site_domain_name))
    error_message = "site_domain_name 은 호스트 이름이다. 스킴(https://)이나 경로를 붙이지 않는다."
  }
}

variable "route53_zone_id" {
  description = <<-EOT
    domain_name 이 속한 Route 53 호스팅 영역 ID.

    도메인을 Route 53 에서 등록하면 영역이 자동으로 생긴다. 콘솔의 Hosted zones 에서
    확인하거나 `aws route53 list-hosted-zones-by-name --dns-name pawloop.app` 로 읽는다.
  EOT
  type        = string
}

variable "acme_email" {
  description = <<-EOT
    Let's Encrypt 에 등록할 이메일. 인증서 만료 경고가 여기로 온다.

    비워 두면 Caddy 가 익명으로 발급받는데, 그러면 만료 경고를 받을 수 없다. 자동 갱신이
    조용히 실패하면 **어느 날 갑자기 로그인이 전부 죽는다** — 그때 알아채는 유일한 경로다.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.acme_email))
    error_message = "acme_email 은 실제로 받아지는 이메일 주소여야 한다."
  }
}

variable "repo_url" {
  description = "클론할 저장소. private 이라 SSH 주소(git@github.com:...)를 쓴다."
  type        = string
}

variable "repo_branch" {
  description = "클론할 브랜치."
  type        = string
  default     = "main"
}

variable "repo_deploy_key_ssm_parameter_name" {
  description = <<-EOT
    저장소 배포 키(개인키)를 담은 SSM SecureString 이름.

    이 저장소는 private 이라 이것 없이는 clone 이 안 된다. staging 에서 이 값을 안 넘겨
    부팅이 통째로 멈춘 적이 있다 (#598).
  EOT
  type        = string

  validation {
    condition     = length(var.repo_deploy_key_ssm_parameter_name) > 0
    error_message = "private 저장소를 클론하려면 배포 키가 필요하다."
  }

  # 조건은 자기 변수를 반드시 참조해야 한다 — terraform 이 그렇게 요구한다.
  # 첫 항이 그 역할이고, 위 validation 때문에 실제로 참이 되는 일은 없다.
  validation {
    condition = (
      var.repo_deploy_key_ssm_parameter_name == "" ||
      startswith(var.repo_url, "git@") ||
      startswith(var.repo_url, "ssh://")
    )
    error_message = "배포 키는 SSH 주소에만 쓸 수 있다. repo_url 을 git@github.com:소유자/저장소.git 형태로 적는다."
  }
}

variable "app_env_ssm_parameter_name" {
  description = "앱 .env 를 담은 SSM SecureString 이름."
  type        = string

  validation {
    condition     = length(var.app_env_ssm_parameter_name) > 0
    error_message = "prod 는 .env 없이 뜨지 않는다. SSM 파라미터 이름을 적는다."
  }
}

variable "kms_key_arns" {
  description = "SecureString 복호화에 필요한 KMS key ARN 목록. 기본 키를 쓰면 비워 둔다."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "모든 리소스에 붙일 tag."
  type        = map(string)
  default     = {}
}
