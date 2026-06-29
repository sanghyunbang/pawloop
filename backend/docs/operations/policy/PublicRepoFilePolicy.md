# Public 저장소 파일 분류표

## 목적

이 문서는 `public 저장소를 실제 운영 코드 저장소로 사용할 때` 어떤 파일을 남기고, 어떤 파일을 빼거나 분리해야 하는지 정리한다.

## 남겨도 되는 파일

| 분류 | 예시 | 공개 가능 여부 | 이유 | 조치 |
|------|------|----------------|------|------|
| 애플리케이션 소스코드 | `src/main/java/**` | 가능 | public이어도 동작 구조 공개는 허용 가능 | 다만 secret 하드코딩 여부 점검 필요 |
| 테스트 코드 | `src/test/**` | 가능 | 품질 검증 정보 | 테스트용 민감값 제거 필요 |
| 기본 설정 파일 | `src/main/resources/application.properties` | 가능 | 예시 설정 구조 제공 가능 | 실제 비밀값은 placeholder만 유지 |
| 빌드 파일 | `build.gradle`, `settings.gradle`, `gradlew*`, `gradle/**` | 가능 | public 프로젝트에 필수 | 그대로 유지 가능 |
| Dockerfile | `Dockerfile` | 가능 | 빌드 재현에 필요 | 내부 주소, credential 유출 여부만 점검 |
| 문서 | `README.md`, `docs/**` | 가능 | public 저장소 목적상 필요 | 운영 민감정보는 제거 |
| API 문서 설정 | Swagger/OpenAPI 설정 코드 | 가능 | 개발자 사용성 향상 | 운영 URL만 노출되지 않게 주의 |
| 일반 CI | build/test/lint/check workflow | 가능 | public 저장소 운영에 적합 | secret 없는 workflow만 유지 |
| 예시 환경 파일 | `.env.example`, `application-private.properties.example` | 가능 | 실행 가이드 제공 | 반드시 예시값만 사용 |

## 조건부로 남길 수 있는 파일

| 분류 | 예시 | 공개 가능 여부 | 이유 | 조치 |
|------|------|----------------|------|------|
| `docker-compose.yml` | 로컬 개발용 compose | 조건부 | 개발 편의상 유용 | 실제 비밀번호, 운영 DB 정보 제거 필요 |
| 배포 workflow | `.github/workflows/deploy*.yml` | 조건부 | 자동배포 자체는 public도 가능 | self-hosted runner 경로, 운영 명령, 내부 구조 제거 필요 |
| S3 bucket / CDN 설정 키 | app 설정 내부 property 이름 | 조건부 | key 이름 자체는 공개 가능 | 실제 운영 값은 외부 주입 |
| 내부 연동 endpoint 이름 | property key 수준 | 조건부 | 구조 설명에는 도움 | 실제 운영 주소는 외부 설정 권장 |

## public 저장소에서 빼야 하는 파일 또는 정보

| 분류 | 예시 | 공개 가능 여부 | 이유 | 조치 |
|------|------|----------------|------|------|
| 실제 secret 파일 | `application-private.properties`, `.env`, `.env.prod` | 불가 | 즉시 위험 | 커밋 금지, 서버 외부 보관 |
| 평문 비밀번호 | compose 내부 `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD` | 불가 | 즉시 위험 | env 또는 secret로 분리 |
| 실제 OAuth secret | Google/Kakao/Naver secret 값 | 불가 | 외부 오용 가능 | 외부 주입 |
| 실제 AWS key | access key, secret key | 불가 | 즉시 위험 | 외부 주입 또는 role 사용 |
| 실제 API key | OpenAI, Tour API, Slack webhook | 불가 | 비용/오용 위험 | 외부 주입 |
| 실제 운영 경로 | self-hosted runner path, 서버 절대경로 | 불가 | 인프라 단서 제공 | workflow에서 제거 또는 private 분리 |
| 실제 내부망 주소 | internal host, private URL | 불가 | 내부 구조 노출 | 예시값 또는 외부 설정 |
| 운영 데이터 덤프 | DB dump, seed 중 민감 데이터 포함 파일 | 불가 | 개인정보/운영정보 포함 가능 | public 저장소 제외 |
| 민감한 운영 스크립트 | 서버 접속/배포 전용 script | 불가 또는 조건부 | 인프라 구조 노출 | private 운영 저장소로 이동 권장 |

## 현재 저장소 기준 즉시 조치 우선순위

1. `docker-compose.yml`의 평문 DB 비밀번호 제거
2. `.github/workflows/deploy-backend.yml`의 self-hosted runner 경로 및 운영 세부정보 제거 또는 private 분리
3. 예시 환경 파일 추가
4. 실제 secret 파일이 커밋되지 않도록 `.gitignore` 재점검
5. public 저장소 공개 전 secret scan 수행
