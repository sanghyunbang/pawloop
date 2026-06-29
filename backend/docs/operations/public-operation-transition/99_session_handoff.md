# 99. 세션 인계 문서

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 목적: 현재 대화 세션이 끊겨도, 다음 세션에서 바로 이어서 작업할 수 있게 핵심 내용을 한 문서에 정리한다.

## 현재 목표

이 프로젝트를 `public 저장소를 실제 운영 기준 저장소로 쓰는 구조`로 전환하는 것이다.

즉:

- 코드는 public
- secret은 저장소 밖
- Cloudflare + Nginx + Spring Boot 구조 고려
- public 운영에 필요한 최소 보안 자동화와 문서화 완료

## 이번 세션에서 완료한 큰 작업

### 1. public 운영형 문서 체계 작성

아래 문서들이 추가되었다.

- [0_plan.md](0_plan.md)
- [1_db_refactoring.md](1_db_refactoring.md)
- [2_config_examples.md](2_config_examples.md)
- [3_deployment_publicization.md](3_deployment_publicization.md)
- [4_security_boundary_redesign.md](4_security_boundary_redesign.md)
- [5_current_status.md](5_current_status.md)
- [6_secret_scan.md](6_secret_scan.md)
- [7_rate_limit.md](7_rate_limit.md)
- [8_gitleaks_config.md](8_gitleaks_config.md)
- [9_gateway_rate_limit_guide.md](9_gateway_rate_limit_guide.md)
- [10_next_rate_limit_plan.md](10_next_rate_limit_plan.md)
- [11_nginx_rate_limit_example.md](11_nginx_rate_limit_example.md)
- [12_gitleaks_local_and_release_checklist.md](12_gitleaks_local_and_release_checklist.md)
- [13_cloudflare_nginx_architecture.md](13_cloudflare_nginx_architecture.md)
- [14_cloudflare_tunnel_and_nginx_practical_guide.md](14_cloudflare_tunnel_and_nginx_practical_guide.md)
- [15_public_launch_runbook.md](15_public_launch_runbook.md)
- [16_real_nginx_config_template.md](16_real_nginx_config_template.md)
- [17_operating_machine_discovery_checklist.md](17_operating_machine_discovery_checklist.md)
- [18_public_release_final_checklist.md](18_public_release_final_checklist.md)
- [19_mac_mini_command_checklist.md](19_mac_mini_command_checklist.md)

### 2. public 운영형 코드/설정 정리

실제 수정된 핵심 파일:

- [docker-compose.yml](/C:/Users/mm206/git_projects/heat_trip_backend/docker-compose.yml)
- [application.properties](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/resources/application.properties)
- [SecurityConfig.java](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/java/com/heattrip/heat_trip_backend/config/SecurityConfig.java)
- [.github/workflows/deploy-backend.yml](/C:/Users/mm206/git_projects/heat_trip_backend/.github/workflows/deploy-backend.yml)
- [.gitignore](/C:/Users/mm206/git_projects/heat_trip_backend/.gitignore)
- [.dockerignore](/C:/Users/mm206/git_projects/heat_trip_backend/.dockerignore)
- [.env.example](/C:/Users/mm206/git_projects/heat_trip_backend/.env.example)
- [application-private.properties.example](/C:/Users/mm206/git_projects/heat_trip_backend/application-private.properties.example)
- [README.md](/C:/Users/mm206/git_projects/heat_trip_backend/README.md)

### 3. secret scan 추가

추가 파일:

- [secret-scan.yml](/C:/Users/mm206/git_projects/heat_trip_backend/.github/workflows/secret-scan.yml)
- [.gitleaks.toml](/C:/Users/mm206/git_projects/heat_trip_backend/.gitleaks.toml)

### 4. 앱 레벨 rate limit 추가

추가 파일:

- [PublicSecurityProperties.java](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/java/com/heattrip/heat_trip_backend/config/PublicSecurityProperties.java)
- [PublicSecurityConfig.java](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/java/com/heattrip/heat_trip_backend/config/PublicSecurityConfig.java)
- [ApiRateLimitFilter.java](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/java/com/heattrip/heat_trip_backend/security/ApiRateLimitFilter.java)

## 핵심 결정 사항

### 1. public 저장소를 실제 운영 기준 저장소로 사용

단, secret과 운영 정보는 저장소 밖으로 둔다.

### 2. DB 평문 비밀번호는 제거

`docker-compose.yml`은 `.env` 기반으로 변경했다.

### 3. 고비용 API 공개 범위 축소

- `/api/curation/**` -> 인증 필요
- `/public/**` -> 인증 필요
- Swagger -> 기본 비공개

### 4. public 운영에 맞는 최소 보안 자동화 추가

- `gitleaks` secret scan
- 앱 레벨 최소 rate limit

### 5. Cloudflare + Nginx + Spring Boot 구조를 권장

현재 가장 추천하는 구조:

```text
사용자
 -> Cloudflare
 -> cloudflared tunnel
 -> Nginx
 -> Spring Boot
```

## 빌드 검증

이번 세션에서 아래 명령으로 검증했고 통과했다.

```powershell
.\gradlew.bat compileJava
```

## 아직 안 끝난 것

### 1. Mac mini 실제값 확인

이건 지금 컴퓨터가 운영 컴퓨터가 아니라서 실제로 못 했다.

운영 Mac mini에서 아래를 확인해야 한다.

- cloudflared가 어디로 보내는지
- Nginx가 어디로 보내는지
- Spring Boot가 어디에서 listen 하는지
- 실제 domain / tunnel id / config path

관련 문서:

- [17_operating_machine_discovery_checklist.md](17_operating_machine_discovery_checklist.md)
- [19_mac_mini_command_checklist.md](19_mac_mini_command_checklist.md)

### 2. Nginx 실제 운영값 반영

현재는 템플릿까지만 만들어 둔 상태다.

관련 파일:

- [nginx-production-template.conf](nginx-production-template.conf)

### 3. 새 public 저장소 생성 직전 최종 점검

관련 문서:

- [18_public_release_final_checklist.md](18_public_release_final_checklist.md)
- [12_gitleaks_local_and_release_checklist.md](12_gitleaks_local_and_release_checklist.md)

## 다음 세션에서 가장 먼저 할 일

1. 운영 Mac mini에서 [19_mac_mini_command_checklist.md](19_mac_mini_command_checklist.md) 순서대로 실행
2. 결과를 가져와서 실제 domain / tunnel / nginx / upstream 값 확정
3. `nginx-production-template.conf`를 실사용 설정으로 구체화
4. 필요하면 cloudflared 설정도 실사용 값으로 정리
5. 새 public 저장소 오픈 직전 체크리스트 수행

## 다음 세션 시작용 프롬프트

아래 문장을 다음 세션 첫 메시지로 붙여넣으면 된다.

```text
docs/operations/public-operation-transition/99_session_handoff.md 를 먼저 읽고 이어서 작업해줘.
이번 목표는 public 운영 전환 마무리야.
특히 docs/operations/public-operation-transition/19_mac_mini_command_checklist.md 기준으로 Mac mini에서 확인한 결과를 반영해서
1) 실제 Nginx 설정 확정
2) cloudflared 연결 구조 확정
3) public 저장소 오픈 직전 최종 점검
까지 이어서 해줘.
```

## 마지막 메모

현재 워크트리에는 이번 세션 작업 외에도 기존 변경이 있다.

예:

- `build.gradle`
- `src/main/java/com/heattrip/heat_trip_backend/observability/`

이 부분은 이번 세션에서 건드린 작업과 별도로 존재할 수 있으므로, 다음 세션에서도 함부로 되돌리지 않는 것이 맞다.
