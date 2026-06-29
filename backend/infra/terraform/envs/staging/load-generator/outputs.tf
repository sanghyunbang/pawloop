output "loader_instance_id" {
  value = module.load_generator_host.instance_id
}

output "loader_private_ip" {
  value = module.load_generator_host.private_ip
}

output "loader_public_ip" {
  value = module.load_generator_host.public_ip
}

output "loader_security_group_id" {
  value = module.load_generator_host.security_group_id
}

output "run_command" {
  value = "ssh ec2-user@${module.load_generator_host.public_ip} run-heattrip-k6 domains/journey/journey-crud.js"
}

