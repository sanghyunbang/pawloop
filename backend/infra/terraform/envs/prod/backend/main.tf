data "aws_caller_identity" "current" {}

# 볼륨은 인스턴스와 **같은 가용영역**에 있어야 붙는다. 서브넷이 가용영역을 정하므로
# 거기서 읽는다 — 손으로 적으면 서브넷을 바꿨을 때 조용히 어긋난다.
data "aws_subnet" "selected" {
  id = var.subnet_id
}

locals {
  ssm_parameter_arn_prefix = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter"

  app_env_parameter_arn    = "${local.ssm_parameter_arn_prefix}/${trimprefix(var.app_env_ssm_parameter_name, "/")}"
  deploy_key_parameter_arn = "${local.ssm_parameter_arn_prefix}/${trimprefix(var.repo_deploy_key_ssm_parameter_name, "/")}"

  # EC2 가 읽을 수 있는 parameter 는 여기 적힌 것뿐이다.
  ssm_parameter_arns = [local.app_env_parameter_arn, local.deploy_key_parameter_arn]

  tags = merge(var.tags, {
    Project     = "pawloop"
    Environment = "prod"
    Role        = "backend"
  })
}

# ── 주소를 고정한다 ─────────────────────────────────────────────────
#
# Elastic IP 가 없으면 인스턴스를 교체할 때마다 공인 IP 가 바뀐다. staging 에서 하루에
# 세 번 바뀌었고, 그때마다 SSM 의 APP_BASE_URL · 보안그룹 · 앱 빌드가 전부 흔들렸다.
#
# prod 에서는 그것으로 끝나지 않는다 — 구글·카카오·애플 콘솔에 등록한 리다이렉트 주소가
# 이 도메인이고, 도메인은 이 IP 를 가리킨다. 주소가 흔들리면 로그인이 흔들린다.
#
# 요금: 떠 있는 인스턴스에 붙어 있는 동안에는 없다. 놀리면 시간당 요금이 붙는다.
resource "aws_eip" "backend" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${var.name_prefix}-backend-eip" })
}

resource "aws_eip_association" "backend" {
  instance_id   = module.backend_host.instance_id
  allocation_id = aws_eip.backend.id
}

# ── 이름을 붙인다 ───────────────────────────────────────────────────
#
# Caddy 는 이 이름으로 Let's Encrypt 인증서를 받는다(HTTP-01). 그래서 **이 레코드가
# 먼저 있어야** 한다 — 인스턴스가 이 레코드에 의존하게 둔 이유다.
#
# TTL 60 인 것은 주소를 옮길 일이 생겼을 때 빨리 바뀌게 하려는 것이다. 이 레코드는
# 자주 안 바뀌므로 조회 요금 차이는 무시할 만하다.
resource "aws_route53_record" "api" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 60
  records = [aws_eip.backend.public_ip]
}

# 소개·약관 페이지의 이름 — 이슈 #611.
#
# `api.…` 와 같은 서버를 가리킨다. Caddy 가 이름으로 갈라 하나는 백엔드로 넘기고 하나는
# 정적 문서를 그린다. **이 레코드가 없으면 인증서가 안 나오고**, 인증서가 없으면 스토어에
# 적을 https 주소가 없다.
#
# `count` 인 것은 도메인이 아직 없을 때 전체가 막히지 않게 하려는 것이다.
resource "aws_route53_record" "site" {
  count = var.site_domain_name == "" ? 0 : 1

  zone_id = var.route53_zone_id
  name    = var.site_domain_name
  type    = "A"
  ttl     = 60
  records = [aws_eip.backend.public_ip]
}

# ── DB 를 서버에서 떼어낸다 ─────────────────────────────────────────
#
# 부팅 스크립트를 고치면 인스턴스가 교체된다(user_data_replace_on_change). root 볼륨은
# 그때 사라지므로 DB 를 거기 두면 배포마다 데이터가 날아간다.
#
# 이 볼륨은 인스턴스와 생애가 다르다. 교체돼도 남고, 새 인스턴스가 다시 붙인다.
resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.selected.availability_zone
  size              = var.data_volume_size_gb
  type              = var.data_volume_type
  encrypted         = true

  tags = merge(local.tags, { Name = "${var.name_prefix}-backend-data" })

  # 이 볼륨이 사라지면 DB 가 사라진다. `terraform destroy` 는 여기서 멈춘다 —
  # 진짜로 지우려면 이 블록을 먼저 지워야 하고, 그 편집 자체가 한 번 더 생각하게 만든다.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = module.backend_host.instance_id

  # 인스턴스가 교체될 때 먼저 떼어낸다. 강제 분리(force_detach)는 쓰지 않는다 —
  # 마운트된 채로 떼면 파일시스템이 깨질 수 있다. 정상 종료가 언마운트를 한다.
}

module "backend_host" {
  source = "../../../modules/ec2-docker-host"

  name                    = "${var.name_prefix}-backend"
  vpc_id                  = var.vpc_id
  subnet_id               = var.subnet_id
  instance_type           = var.instance_type
  key_name                = var.key_name
  allowed_ssh_cidr_blocks = var.allowed_ssh_cidr_blocks
  root_volume_size_gb     = var.root_volume_size_gb
  tags                    = local.tags

  # 여기서부터 staging 과 성격이 갈린다 — **세상에 연다.**
  #
  # 8080 은 열지 않는다. 앱은 .env 의 APP_PUBLISHED_HOST=127.0.0.1 로 루프백에만
  # 묶이고, 밖에서 오는 것은 전부 Caddy(443)를 지난다. 그래야 actuator 차단과
  # X-Real-IP 주입이 우회되지 않는다.
  ingress_rules = [
    {
      description = "HTTPS"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      # Let's Encrypt 의 HTTP-01 확인과 http→https 되돌림에 필요하다.
      # 이 포트를 닫으면 인증서를 못 받는다.
      description = "HTTP (ACME challenge and redirect to HTTPS)"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  iam_ssm_parameter_arns = local.ssm_parameter_arns
  kms_key_arns           = var.kms_key_arns

  startup_commands = templatefile("${path.module}/user_data_backend.sh.tftpl", {
    repo_url                           = var.repo_url
    repo_branch                        = var.repo_branch
    repo_deploy_key_ssm_parameter_name = var.repo_deploy_key_ssm_parameter_name
    app_env_ssm_parameter_name         = var.app_env_ssm_parameter_name
    data_volume_id                     = aws_ebs_volume.data.id
    domain_name                        = var.domain_name
    site_domain_name                   = var.site_domain_name
    acme_email                         = var.acme_email
  })

  # 인증서를 받으려면 부팅 시점에 이름이 이미 이 서버를 가리키고 있어야 한다.
  # 두 이름 다 먼저 있어야 한다 — Caddy 가 부팅하자마자 둘 모두의 인증서를 받으러 간다.
  depends_on = [aws_route53_record.api, aws_route53_record.site]
}

# ── 메일을 보낼 수 있게 한다 (SES) ──────────────────────────────────
#
# 이슈 #635. 가입 인증 코드와 비밀번호 재설정 코드가 이 도메인에서 나간다.
#
# **여기서 만드는 것은 도메인 인증과 DKIM 레코드 셋뿐이다.** SMTP 자격증명(IAM 사용자 +
# 액세스 키)은 만들지 않는다 — terraform 이 만들면 그 비밀번호가 **state 파일에 평문으로
# 남는다.** SES 콘솔이 한 번만 보여 주는 값을 사장님이 직접 .env 에 넣는다.
#
# 인증이 없으면 SES 는 무엇을 보내든 거절한다. 그래서 이것이 보내기의 전제다.
resource "aws_ses_domain_identity" "mail" {
  count = var.mail_domain_name == "" ? 0 : 1

  domain = var.mail_domain_name
}

# 도메인 소유 확인용 TXT. SES 가 준 토큰을 `_amazonses.<도메인>` 에 심는다.
#
# **apex 가 아니라 `_amazonses` 아래**라서 SPF TXT 와 이름이 안 겹친다 — 같은 이름에
# TXT 를 둘 두면 한쪽이 조용히 묻힌다.
resource "aws_route53_record" "mail_verification" {
  count = var.mail_domain_name == "" ? 0 : 1

  zone_id = var.route53_zone_id
  name    = "_amazonses.${var.mail_domain_name}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.mail[0].verification_token]
}

# DKIM 서명. 받는 쪽(지메일·네이버)이 "정말 이 도메인이 보냈는가" 를 검증하는 수단이고,
# **없으면 인증 코드 메일이 스팸함으로 간다.** 사용자는 그것을 "메일이 안 왔다" 로 겪는다.
resource "aws_ses_domain_dkim" "mail" {
  count = var.mail_domain_name == "" ? 0 : 1

  domain = aws_ses_domain_identity.mail[0].domain
}

# SES 가 주는 토큰 셋을 CNAME 으로 심는다. 손으로 넣으면 셋 중 하나를 빠뜨려도
# 콘솔은 "Pending" 만 보여 주고 무엇이 빠졌는지는 말해 주지 않는다.
resource "aws_route53_record" "mail_dkim" {
  count = var.mail_domain_name == "" ? 0 : 3

  zone_id = var.route53_zone_id
  name    = "${aws_ses_domain_dkim.mail[0].dkim_tokens[count.index]}._domainkey.${var.mail_domain_name}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.mail[0].dkim_tokens[count.index]}.dkim.amazonses.com"]
}

# 위 레코드가 퍼진 뒤에 SES 가 스스로 확인한다 — 이 리소스는 그때까지 기다린다.
#
# **여기서 멈추면 코드가 아니라 DNS 다.** 기다림을 10분으로 줄여 둔 이유는, 기본값(45분)
# 이면 DNS 를 잘못 넣은 apply 하나가 45분을 잡아먹기 때문이다. 시간이 넘으면 apply 가
# 실패하지만 레코드는 이미 만들어져 있으므로, 원인을 고친 뒤 다시 apply 하면 그 자리부터
# 이어진다.
resource "aws_ses_domain_identity_verification" "mail" {
  count = var.mail_domain_name == "" ? 0 : 1

  domain = aws_ses_domain_identity.mail[0].id

  timeouts {
    create = "10m"
  }

  depends_on = [
    aws_route53_record.mail_verification,
    aws_route53_record.mail_dkim,
  ]
}

# SPF. "이 도메인의 메일은 SES 가 보낸다" 를 적어 두는 TXT 다.
#
# **apex 의 TXT 는 하나로 합쳐야 한다.** 같은 이름에 TXT 를 두 개 두면 받는 쪽이 둘 다
# 보고 혼란스러워하거나 한쪽만 읽는다. 그래서 이 레코드는 도메인에 다른 TXT 가 없을 때만
# 만든다 — 이미 있으면 그 값에 `include:amazonses.com` 을 **손으로 더한다.**
resource "aws_route53_record" "mail_spf" {
  count = var.mail_domain_name == "" || !var.manage_mail_spf_record ? 0 : 1

  zone_id = var.route53_zone_id
  name    = var.mail_domain_name
  type    = "TXT"
  ttl     = 600
  records = ["v=spf1 include:amazonses.com ~all"]
}
