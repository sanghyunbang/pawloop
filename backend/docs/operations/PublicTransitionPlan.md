# 공개 운영형 전환 계획

## 목적

- 새 저장소를 `public`으로 만들고, 그 저장소를 앞으로 실제 개발 및 운영의 기준 저장소로 사용한다.
- 다만 비밀값, 운영 인프라 정보, 민감한 배포 세부사항은 저장소 밖으로 분리한다.
- 즉, `코드는 public`, `운영 비밀값은 외부 주입` 구조로 전환한다.

## 이 문서에서 전제하는 운영 방식

이 문서는 아래 전제를 기준으로 작성한다.

- public 저장소를 단순 참고용이 아니라 실제 운영 코드 저장소로 사용한다.
- 현재 prod 사용자가 거의 없으므로, 필요하면 서버를 잠시 내려도 된다.
- 무중단 이전은 필수가 아니다.
- 핵심은 "회전" 그 자체보다 "public 저장소에 실리면 안 되는 것을 제거하는 것"이다.

## public 저장소여도 운영 가능한가

가능하다. 다만 아래 조건을 반드시 만족해야 한다.

- 저장소에 실제 secret이 없어야 한다.
- 서버 주소, 내부 경로, 러너 경로 같은 운영 정보가 없어야 한다.
- 인증/인가가 코드가 공개되어도 안전한 수준이어야 한다.
- 비용 유발 API는 남용 방어가 있어야 한다.
- 배포 시 필요한 민감 정보는 GitHub Secrets, 서버 환경변수, 외부 설정 파일로만 주입해야 한다.

즉, `숨겨져 있어서 안전한 구조`가 아니라 `드러나도 안전한 구조`여야 한다.

## 현재 저장소에서 보이는 주요 위험

- `docker-compose.yml`에 MySQL 계정과 비밀번호가 평문으로 들어 있다.
- 배포 workflow에 self-hosted runner 경로와 운영 방식이 직접 드러난다.
- 일부 보안상 민감한 API가 인증 없이 열려 있거나, 고비용 API가 공개 호출 가능 상태일 수 있다.
- 과거 커밋 이력에 민감한 값이 남아 있을 수 있으므로, 현재 저장소를 그대로 public으로 바꾸는 것은 신중해야 한다.

## 기본 원칙

- 현재 private 저장소를 그대로 public으로 전환하지 않는다.
- 비밀값과 운영 정보를 제거한 새 public 저장소를 만든다.
- 실제 비밀값은 커밋하지 않고 외부에서 주입한다.
- 운영형 public 저장소라도, 운영 세부 배포 정보 일부는 private로 유지할 수 있다.

## 1단계. 비밀값 및 민감정보 인벤토리 작성

현재 코드베이스 기준으로 확인 가능한 1차 인벤토리 표는 아래와 같다.

| 항목 | 용도 | 현재 위치 | 공개 가능 여부 | 조치 방식 | 비고 |
|------|------|-----------|----------------|-----------|------|
| MySQL root 비밀번호 | DB root 계정 접속 | `docker-compose.yml` | 불가 | 삭제 후 외부 주입 | 현재 `MYSQL_ROOT_PASSWORD` 평문 존재 |
| MySQL 애플리케이션 계정 비밀번호 | 앱 DB 접속 | `docker-compose.yml` | 불가 | 삭제 후 외부 주입 | 현재 `MYSQL_PASSWORD` 평문 존재, healthcheck에도 직접 사용 |
| `jwt.secret` | JWT 서명 및 검증 | `src/main/java/com/heattrip/heat_trip_backend/OAuth/jwt/JWTProvider.java`, 실제 값은 외부 설정 추정 | 불가 | 외부 설정 파일 또는 환경변수 사용 | public 저장소에는 예시값만 남김 |
| Google OAuth client id / secret | 구글 소셜 로그인 | 실제 값은 외부 설정 추정, 관련 코드는 `src/main/java/com/heattrip/heat_trip_backend/config/SecurityConfig.java` | 불가 | 외부 주입 | redirect URI도 운영값 분리 권장 |
| Kakao OAuth 또는 REST key / secret | 카카오 로그인 또는 카카오 로컬 API 호출 | `src/main/java/com/heattrip/heat_trip_backend/config/WebClientConfig.java`, 실제 값은 `kakao.api.rest-key` 외부 설정 추정 | 불가 | 외부 주입 | 실제 값은 절대 커밋 금지 |
| Naver OAuth client id / secret | 네이버 소셜 로그인 | 실제 값은 외부 설정 추정, 관련 코드는 `src/main/java/com/heattrip/heat_trip_backend/OAuth/service/CustomOAuth2UserService.java` | 불가 | 외부 주입 | public 저장소에는 placeholder만 유지 |
| AWS access key / secret key | S3 접근 | `src/main/java/com/heattrip/heat_trip_backend/S3/AmazonS3Config.java` | 불가 | 외부 주입 또는 IAM role 전환 | 장기적으로는 정적 key보다 role 구조 권장 |
| S3 bucket 설정 | 파일 저장 대상 | `src/main/java/com/heattrip/heat_trip_backend/S3/S3FileStorageService.java` | 조건부 | 예시값 또는 환경별 외부 설정 | secret은 아니지만 운영 정보일 수 있음 |
| CloudFront 도메인 | 공개 URL 생성 | `src/main/java/com/heattrip/heat_trip_backend/S3/S3FileStorageService.java` | 조건부 | 예시값 또는 외부 설정 | 운영 도메인을 숨기고 싶으면 외부화 |
| Slack webhook URL | 장애 및 알림 전송 | `src/main/resources/application.properties`에서 `SLACK_WEBHOOK_URL` 참조 | 불가 | 외부 주입 | 현재 env 참조 구조 |
| OpenAI API key | AI 요약 및 분석 | `src/main/resources/application.properties`에서 `OPENAI_API_KEY` 참조 | 불가 | 외부 주입 | 현재 env 참조 구조 |
| Tour API key | 공공데이터 관광 API 호출 | `src/main/java/com/heattrip/heat_trip_backend/tour/service/TourApiClient.java`의 `TOUR.API.SECRET` | 불가 | 외부 주입 | query param에 직접 사용 |
| 내부 LLM 추천기 URL 또는 내부 서비스 인증값 | 내부 추천 서비스 호출 | `src/main/java/com/heattrip/heat_trip_backend/config/LlmWebClientConfig.java`, `src/main/java/com/heattrip/heat_trip_backend/llm/RecommenderHealthChecker.java` | 조건부 | 외부 설정 | 내부망 주소면 public 저장소에 직접 두지 않는 편이 안전 |
| self-hosted runner 경로 | 배포 러너 경로 및 서버 구조 | `.github/workflows/deploy-backend.yml` | 불가 | public 저장소에서 제거 또는 private workflow 분리 | `/Users/hyun/apps/heattrip-backend` 노출 |

## 2단계. 현재 상황 기준 현실적인 방향

현재는 다음 방향이 가장 현실적이다.

1. 기존 서버를 잠시 중지한다.
2. 현재 저장소를 기준으로 public에 실리면 안 되는 값과 파일을 정리한다.
3. 새 public 저장소를 만든다.
4. public 저장소에는 코드, 문서, 예시 설정만 남긴다.
5. 실제 운영값은 GitHub Secrets, 서버 환경변수, 외부 설정 파일로 주입한다.
6. 필요하면 운영 workflow 일부는 private 저장소나 private 환경에 둔다.

## 3단계. 새 public 저장소에 포함할 것과 제외할 것

요약 원칙:

- 포함: 애플리케이션 코드, 문서, 예시 설정, 빌드 파일
- 제외: 실제 비밀값, 실제 운영 경로, 실제 배포 세부정보, 내부 주소

자세한 파일 분류표는 `docs/operations/policy/PublicRepoFilePolicy.md`를 따른다.

## 4단계. 공개용 설정 구조

public 저장소에는 아래 구조를 사용한다.

- `src/main/resources/application.properties`
- `application-private.properties.example`
- `.env.example`
- `README.md`

원칙:

- 실제 비밀값은 절대 커밋하지 않는다.
- placeholder만 커밋한다.
- 운영값은 런타임에 주입한다.

예시:

```properties
jwt.secret=${JWT_SECRET:change-me}
spring.ai.openai.api-key=${OPENAI_API_KEY:}
observability.slack.webhook-url=${SLACK_WEBHOOK_URL:}
cloud.aws.credentials.access-key=${AWS_ACCESS_KEY_ID:}
cloud.aws.credentials.secret-key=${AWS_SECRET_ACCESS_KEY:}
```

## 5단계. 운영 방식

public 저장소를 실제 운영 저장소로 쓰더라도, 아래는 저장소 밖에 둔다.

- GitHub Secrets
- 서버 환경변수
- 서버의 `application-private.properties`
- 배포용 실제 credential
- 민감한 운영 workflow 또는 운영 전용 script

권장 구조:

- public 저장소: 앱 코드, 예시 설정, 문서, 테스트, 일반 CI
- private 운영 환경: 실제 secret, 실제 서버 주소, 운영 배포 실행 정보

## 6단계. 실제 진행 순서

1. 현재 서버 중지
2. `docker-compose.yml`의 평문 비밀번호 제거
3. 실제 secret 값을 참조하는 예시 파일 추가
4. 운영 경로와 self-hosted runner 정보 제거 또는 분리
5. public 저장소에 남겨도 되는 파일만 선별
6. 새 public 저장소 생성
7. GitHub Secrets 및 서버 외부 설정 구성
8. 새 저장소 기준으로 다시 배포

## 7단계. 공개 운영 전 최종 점검

아래 조건을 만족해야 한다.

- 저장소에 실제 secret literal이 없다.
- 운영 서버 경로, 내부 주소, 러너 정보가 없다.
- 고비용 API에 대한 보호 방안이 있다.
- 인증/인가가 코드 공개 상태에서도 안전하다.
- public 저장소만 봐도 제3자가 구조를 이해할 수 있다.

자세한 보안 체크와 현재 상태 평가는 `docs/operations/security/PublicSecurityAssessment.md`를 따른다.

## 최종 결론

- public 저장소를 실제 운영 저장소로 사용하는 것은 가능하다.
- 다만 그 경우에도 secret과 운영 정보는 저장소 밖으로 분리해야 한다.
- 현재 상황에서는 `기존 private 저장소를 그대로 public 전환`하는 것보다, `정리된 새 public 저장소를 만들어 운영 기준 저장소로 쓰는 방식`이 가장 안전하다.
