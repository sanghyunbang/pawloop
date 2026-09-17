output "backend_url" {
  description = "앱과 OAuth 콘솔이 쓰는 주소."
  value       = "https://${var.domain_name}"
}

output "backend_public_ip" {
  description = "Elastic IP. 인스턴스를 교체해도 바뀌지 않는다."
  value       = aws_eip.backend.public_ip
}

output "backend_instance_id" {
  value = module.backend_host.instance_id
}

output "backend_private_ip" {
  value = module.backend_host.private_ip
}

output "backend_security_group_id" {
  value = module.backend_host.security_group_id
}

output "data_volume_id" {
  description = "DB 데이터 볼륨. 인스턴스와 생애가 다르다 — 교체해도 남는다."
  value       = aws_ebs_volume.data.id
}

output "oauth_redirect_uris" {
  description = "구글·카카오·애플 콘솔에 등록할 리다이렉트 주소 (#611)."
  value = {
    google = "https://${var.domain_name}/login/oauth2/code/google"
    kakao  = "https://${var.domain_name}/login/oauth2/code/kakao"
    apple  = "https://${var.domain_name}/login/oauth2/code/apple"
  }
}
