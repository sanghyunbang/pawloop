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

output "mail_smtp_endpoint" {
  description = <<-EOT
    .env 의 SPRING_MAIL_HOST 에 넣을 값 (#635). 도메인을 안 걸었으면 비어 있다.

    자격증명(SPRING_MAIL_USERNAME·PASSWORD)은 **여기서 안 나온다** — terraform 이 만들면
    state 에 평문으로 남는다. SES 콘솔 → SMTP settings → Create SMTP credentials 가
    한 번만 보여 주는 값을 직접 .env 에 넣는다.
  EOT
  value       = var.mail_domain_name == "" ? "" : "email-smtp.${var.aws_region}.amazonaws.com"
}

output "mail_domain_verified" {
  description = "SES 도메인 인증이 끝났는가. 거짓이면 SES 가 무엇을 보내든 거절한다."
  value       = var.mail_domain_name == "" ? false : length(aws_ses_domain_identity_verification.mail) > 0
}
