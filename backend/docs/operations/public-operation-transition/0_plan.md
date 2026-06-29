# 0. 공개 운영 전환 계획

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 목적: 새 public 저장소를 실제 운영 기준 저장소로 사용하기 위한 정리 작업을 단계별로 관리한다.
- 현재 전제: 사용자 거의 없음, 서버 일시 중단 허용, secret은 저장소 밖으로 분리

## 이번 작업 범위

1. DB 관련 평문 비밀번호 제거
2. 공개 가능한 예시 설정 파일 추가
3. 공개 가능한 배포 workflow 형태로 정리
4. `SecurityConfig` 공개 범위 재설계

## 작업 순서

1. [1_db_refactoring.md](1_db_refactoring.md)
2. [2_config_examples.md](2_config_examples.md)
3. [3_deployment_publicization.md](3_deployment_publicization.md)
4. [4_security_boundary_redesign.md](4_security_boundary_redesign.md)
5. [5_current_status.md](5_current_status.md)
6. [6_secret_scan.md](6_secret_scan.md)
7. [7_rate_limit.md](7_rate_limit.md)
8. [8_gitleaks_config.md](8_gitleaks_config.md)
9. [9_gateway_rate_limit_guide.md](9_gateway_rate_limit_guide.md)
10. [10_next_rate_limit_plan.md](10_next_rate_limit_plan.md)
11. [11_nginx_rate_limit_example.md](11_nginx_rate_limit_example.md)
12. [12_gitleaks_local_and_release_checklist.md](12_gitleaks_local_and_release_checklist.md)
13. [13_cloudflare_nginx_architecture.md](13_cloudflare_nginx_architecture.md)
14. [14_cloudflare_tunnel_and_nginx_practical_guide.md](14_cloudflare_tunnel_and_nginx_practical_guide.md)
15. [15_public_launch_runbook.md](15_public_launch_runbook.md)
16. [16_real_nginx_config_template.md](16_real_nginx_config_template.md)
17. [17_operating_machine_discovery_checklist.md](17_operating_machine_discovery_checklist.md)
18. [18_public_release_final_checklist.md](18_public_release_final_checklist.md)
19. [19_mac_mini_command_checklist.md](19_mac_mini_command_checklist.md)
20. [20_mac_mini_actual_state_2026_03_18.md](20_mac_mini_actual_state_2026_03_18.md)
21. [21_secret_separation_and_recommender_hardening.md](21_secret_separation_and_recommender_hardening.md)
22. [22_cicd_option_review.md](22_cicd_option_review.md)
23. [23_backend_and_recommender_cicd_design.md](23_backend_and_recommender_cicd_design.md)
99. [99_session_handoff.md](99_session_handoff.md)

## 먼저 참고할 문서

- [PublicTransitionPlan.md](../PublicTransitionPlan.md)
- [PublicRepoFilePolicy.md](../policy/PublicRepoFilePolicy.md)
- [PublicSecurityAssessment.md](../security/PublicSecurityAssessment.md)

## 현재 판단

- 기존 private 저장소를 그대로 public 전환하는 방식보다, 정리된 새 public 저장소를 만드는 방식이 안전하다.
- 이번 단계에서는 `secret 제거`, `운영 정보 제거`, `보안 범위 축소`까지를 완료한다.
- 이번 단계에서 CI secret scan과 앱 레벨 최소 rate limit까지 추가한다.
