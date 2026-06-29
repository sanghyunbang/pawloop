data "aws_caller_identity" "current" {}

locals {
  k6_env_parameter_arn = var.k6_env_ssm_parameter_name == "" ? "" : "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${trimprefix(var.k6_env_ssm_parameter_name, "/")}"

  tags = merge(var.tags, {
    Project     = "heat-trip"
    Environment = "staging"
    Role        = "load-generator"
  })
}

module "load_generator_host" {
  source = "../../../modules/ec2-docker-host"

  name                    = "${var.name_prefix}-load-generator"
  vpc_id                  = var.vpc_id
  subnet_id               = var.subnet_id
  instance_type           = var.instance_type
  key_name                = var.key_name
  allowed_ssh_cidr_blocks = var.allowed_ssh_cidr_blocks
  root_volume_size_gb     = var.root_volume_size_gb
  tags                    = local.tags

  iam_ssm_parameter_arns = local.k6_env_parameter_arn == "" ? [] : [local.k6_env_parameter_arn]
  kms_key_arns           = var.kms_key_arns

  startup_commands = templatefile("${path.module}/user_data_load_generator.sh.tftpl", {
    repo_url                  = var.repo_url
    repo_branch               = var.repo_branch
    backend_base_url          = var.backend_base_url
    k6_env_ssm_parameter_name = var.k6_env_ssm_parameter_name
    default_vus               = var.default_vus
    default_duration          = var.default_duration
  })
}

