output "backend_instance_id" {
  value = module.backend_host.instance_id
}

output "backend_private_ip" {
  value = module.backend_host.private_ip
}

output "backend_public_ip" {
  value = module.backend_host.public_ip
}

output "backend_security_group_id" {
  value = module.backend_host.security_group_id
}

output "backend_base_url_for_loader" {
  value = "http://${module.backend_host.private_ip}:8080"
}

