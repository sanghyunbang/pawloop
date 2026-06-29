# Public 운영 보안 체크리스트 및 현재 상태

## 목적

이 문서는 `public 저장소를 실제 운영 저장소로 사용하는 경우` 필요한 보안 체크리스트를 정리하고, 현재 코드베이스 기준으로 실제 상태를 점검한 결과를 남긴다.

## 상태 표기 기준

- `충족`: 현재 코드 기준으로 큰 문제 없이 충족
- `부분 충족`: 일부는 되어 있으나 보완이 필요
- `미충족`: 공개 운영 기준으로 보완이 필요
- `미확인`: 코드만 보고는 판단 불가

## 체크리스트와 현재 상태

| 항목 | 현재 상태 | 근거 | 조치 필요 |
|------|-----------|------|-----------|
| 저장소에 실제 secret이 없다 | 부분 충족 | `docker-compose.yml` 평문 DB 비밀번호 제거 완료. 다만 과거 이력과 미추적 로컬 파일은 별도 확인 필요 | 새 public 저장소 생성 전 secret scan 권장 |
| secret이 환경변수 또는 외부 설정으로 주입된다 | 부분 충족 | DB는 `.env`, 앱은 `application-private.properties` 예시 구조 추가 | 실제 운영 서버에 외부 주입 구성 필요 |
| 운영 경로와 내부 인프라 정보가 저장소에 없다 | 부분 충족 | `deploy-backend.yml` 절대경로 제거 완료 | 운영 방식 자체를 더 숨기려면 workflow private 분리 고려 |
| 인증 구조가 중앙집중적으로 관리된다 | 부분 충족 | Spring Security + JWT filter 사용, 일부 controller는 여전히 수동 검증 | 장기적으로 보안 정책 일원화 권장 |
| 인가(owner check)가 주요 쓰기 API에 적용된다 | 부분 충족 | schedule, journey 등 일부 쓰기 API에 owner check 존재 | 다른 변경성 API 점검 필요 |
| 고비용 API가 무인증으로 과다 호출되지 않는다 | 부분 충족 | `/api/curation/**`를 `authenticated`로 전환 | 추가 rate limit 권장 |
| Swagger/OpenAPI 공개 범위가 의도적으로 관리된다 | 충족 | `APP_SECURITY_DOCS_PUBLIC` 환경변수로 공개 여부 제어 가능 | 운영 기본값은 false 유지 |
| Rate limiting 또는 abuse 방어가 있다 | 부분 충족 | 앱 레벨 in-memory rate limit 추가 완료 | gateway/WAF 레벨 1차 보호 추가 권장 |
| 로그인/민감 API에 brute force 방어가 있다 | 부분 충족 | 로그인 경로에 rate limit 추가 완료 | lockout, captcha 등 추가 보호는 별도 검토 |
| 요청/응답 로그에 민감정보가 남지 않는다 | 부분 충족 | `SensitiveDataMasker` 존재, request logging은 경로 중심 | 다른 로그 출력과 예외 로그 추가 점검 필요 |
| 디버그 로그가 운영에서 과도하게 켜져 있지 않다 | 충족 | `application.properties` 기본값을 INFO/비노출 쪽으로 조정 | 필요 시 환경변수로만 상향 |
| JWT secret이 안전하게 외부 주입된다 | 부분 충족 | 예시 파일 분리 완료, 실제 값은 외부 파일에서 주입 전제 | 운영 서버 secret 관리 필요 |
| CORS 설정이 운영 도메인 기준으로 관리된다 | 부분 충족 | `APP_SECURITY_ALLOWED_ORIGINS` 환경변수로 외부화 | 운영 도메인 반영 필요 |
| CSRF 비활성화가 인증 구조와 맞는다 | 충족 | JWT stateless API 구조 | 유지 가능 |
| 파일 업로드 경로가 검증된다 | 미확인 | validator 관련 코드는 있으나 전체 정책 검증은 별도 확인 필요 | 파일 크기, MIME, 권한 점검 권장 |
| 외부 의존 API key가 public 저장소에 남지 않는다 | 부분 충족 | 예시 설정 파일 분리 완료, secret scan CI 추가 | 새 public 저장소 생성 전 전체 이력 재검사 권장 |
| 배포 workflow가 secret 없이 공개 가능하다 | 부분 충족 | 절대경로 제거 완료, runner에서는 `.env`와 `config` 외부 준비 필요 | 운영 전용 workflow 분리 여부 판단 필요 |
| 민감한 운영 기능이 공개 엔드포인트로 열려 있지 않다 | 부분 충족 | `/public/**`를 Spring Security 레벨에서도 인증 요구로 전환 | 다른 내부성 엔드포인트 추가 점검 필요 |
| 에러/예외 응답이 운영에 과도하게 상세하지 않다 | 충족 | 기본값을 `never`로 조정 | 필요 시 환경변수로만 개방 |
| public이어도 비용 폭주를 막을 수 있다 | 부분 충족 | 인증과 앱 레벨 rate limit은 추가됨 | gateway/WAF, quota, 모니터링 추가 권장 |

## 이번 수정으로 해결된 항목

### 1. 평문 DB 비밀번호 제거

- 파일: [docker-compose.yml](/C:/Users/mm206/git_projects/heat_trip_backend/docker-compose.yml)
- 결과: 고정 문자열 제거, `.env` 기반으로 전환

### 2. 공개 가능한 예시 설정 파일 추가

- 파일: [application-private.properties.example](/C:/Users/mm206/git_projects/heat_trip_backend/application-private.properties.example), [.env.example](/C:/Users/mm206/git_projects/heat_trip_backend/.env.example)
- 결과: public 저장소에 실제 값 없이 설정 구조 설명 가능

### 3. 배포 workflow 절대경로 제거

- 파일: [deploy-backend.yml](/C:/Users/mm206/git_projects/heat_trip_backend/.github/workflows/deploy-backend.yml)
- 결과: `github.workspace` 기준으로 정리

### 4. 공개 범위 축소

- 파일: [SecurityConfig.java](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/java/com/heattrip/heat_trip_backend/config/SecurityConfig.java)
- 결과: `/api/curation/**`, `/public/**` 인증 필요로 변경

### 5. 운영 기본 로그 및 에러 노출 축소

- 파일: [application.properties](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/resources/application.properties)
- 결과: 에러 상세와 DEBUG 로그를 기본값에서 낮춤

### 6. Secret scan CI 추가

- 파일: [secret-scan.yml](/C:/Users/mm206/git_projects/heat_trip_backend/.github/workflows/secret-scan.yml)
- 결과: PR, push, 수동 실행 시 `gitleaks` 검사 수행

### 7. 앱 레벨 최소 rate limit 추가

- 파일: [ApiRateLimitFilter.java](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/java/com/heattrip/heat_trip_backend/security/ApiRateLimitFilter.java)
- 결과: 로그인, 추천, 검색, 피드백, 업로드 경로에 429 보호선 추가

## 아직 남은 주요 작업

1. gateway 또는 WAF 레벨 rate limit 추가
2. 로그인 보호 정책 보강
3. 새 public 저장소 생성 전 전체 이력 secret scan 수행
4. README에 실제 실행 방법과 외부 설정 구조 정리 지속 보강
5. 필요 시 배포 workflow를 별도 private 운영 저장소로 분리

## 결론

현재 상태는 `public 운영 준비 중`에서 `public 운영 기본 정리 완료` 단계로 올라왔다.

아직 남은 핵심 리스크는 아래 세 가지다.

- gateway 레벨 남용 방어 부족
- 로그인 보호 부족
- 새 public 저장소 생성 전 전체 이력 기준 최종 secret scan 미실시

이 세 가지를 추가로 정리하면 public 운영형 구조로 더 안정적으로 갈 수 있다.
