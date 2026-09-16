data "aws_caller_identity" "current" {}

locals {
  ssm_parameter_arn_prefix = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter"

  app_env_parameter_arn    = var.app_env_ssm_parameter_name == "" ? "" : "${local.ssm_parameter_arn_prefix}/${trimprefix(var.app_env_ssm_parameter_name, "/")}"
  deploy_key_parameter_arn = var.repo_deploy_key_ssm_parameter_name == "" ? "" : "${local.ssm_parameter_arn_prefix}/${trimprefix(var.repo_deploy_key_ssm_parameter_name, "/")}"

  # EC2 가 읽을 수 있는 parameter 는 여기 적힌 것뿐이다. 안 쓰는 것은 compact 가 턴다.
  ssm_parameter_arns = compact([local.app_env_parameter_arn, local.deploy_key_parameter_arn])

  compose_files = var.enable_observability ? "-f docker-compose.yml -f docker-compose.observability.yml" : "-f docker-compose.yml"

  tags = merge(var.tags, {
    Project     = "heat-trip"
    Environment = "staging"
    Role        = "backend"
  })
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

  ingress_rules = [
    {
      description = "Backend app"
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      cidr_blocks = var.backend_app_allowed_cidr_blocks
    }
  ]

  iam_ssm_parameter_arns = local.ssm_parameter_arns
  kms_key_arns           = var.kms_key_arns

  startup_commands = templatefile("${path.module}/user_data_backend.sh.tftpl", {
    repo_url                           = var.repo_url
    repo_branch                        = var.repo_branch
    repo_deploy_key_ssm_parameter_name = var.repo_deploy_key_ssm_parameter_name
    app_env_ssm_parameter_name         = var.app_env_ssm_parameter_name
    compose_files                      = local.compose_files
  })
}
