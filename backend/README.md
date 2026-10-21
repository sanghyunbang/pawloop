# Pawloop 백엔드 (`backend/`)

반려동물 산책·가족 케어·채팅·커뮤니티·반려동반 장소 지도를 받치는 Spring Boot API 서버입니다. 제품 전체의 소개는 [저장소 루트 README](../README.md), 구조 서술은 [백엔드 구조](../docs/02-architecture/backend-structure.md), 계약은 [`docs/04-api/openapi.yaml`](../docs/04-api/openapi.yaml) 이 정본입니다.

[![Java](https://img.shields.io/badge/Java-21-007396?style=flat-square&logo=openjdk&logoColor=white)](https://openjdk.org/)
[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-3.5.x-6DB33F?style=flat-square&logo=springboot&logoColor=white)](https://spring.io/projects/spring-boot)
[![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1?style=flat-square&logo=mysql&logoColor=white)](https://www.mysql.com/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?style=flat-square&logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![AWS S3](https://img.shields.io/badge/AWS-S3-FF9900?style=flat-square&logo=amazonaws&logoColor=white)](https://aws.amazon.com/s3/)

## 무엇을 하는 서버인가

| 축 | 경로 | 한 줄 |
| --- | --- | --- |
| 인증 | `/auth/*`, `/oauth2/*` | 카카오·구글(·iOS 출시 시 Apple) 소셜 로그인 + JWT(access/refresh 회전) |
| 반려동물 | `/api/dogs` | 프로필(종·크기·나이·중성화), 소프트 삭제 |
| 산책 | `/api/walks` | GPS 경로를 `LINESTRING` 으로 저장, 주간 통계, 회고 |
| 가족 · 케어 | `/api/groups`, `/api/groups/{id}/care-logs` | 초대코드 가족 그룹, 오늘의 케어(밥·물·산책·투약·병원), 산책 주의사항 |
| 채팅 | `/api/chat/*` | 방·메시지(폴링)·미읽음·초대·신고·차단·강퇴 |
| 커뮤니티 | `/api/community/*` | 게시판 글·댓글·반응·신고 (읽기는 로그인 없이) |
| 장소 | `/api/places/*` | 관광공사 반려동반 장소 프록시 + 전국 한 벌 카탈로그 + 행정안전부 인허가(동물병원·펫샵) + 두루누비 산책로(선 포함) |
| 미디어 | `/media/*` | S3 presigned 업로드 |
| 동의 | `/api/consents` | 약관 동의 이력(위치정보법 포함) |

감정 여행(heattrip) 시절의 패키지(관광 수집·탐색·감정 추천·감정카드·여정·v1 북마크·피드백·카카오 백필)는 2026-09-06 에 [#94](https://github.com/sanghyunbang/pawloop/issues/94) 로 지웠습니다. 표는 운영 DB 에 남아 있고 코드만 없습니다.

## 기술 스택

- Java 21 · Spring Boot 3.5.x (Web · WebFlux `WebClient` · Data JPA · Validation · Security/OAuth2 Client)
- MySQL 8 + `hibernate-spatial` (산책 경로 `LINESTRING SRID 4326`)
- Spring Modulith — 모듈 경계 구조 검사만([ADR-0012](../docs/99-decisions/decision-log.md))
- AWS S3 / CloudFront — 미디어
- Spring AI(OpenAI) — 운영 오류 요약(`observability/ai`)에만
- Actuator + Micrometer + Prometheus · Grafana(`grafana/`)
- Testcontainers(MySQL) — 스프링 컨텍스트를 띄우는 테스트는 전부 진짜 MySQL 위에서 돕니다. **Docker 가 필요합니다.**

## 빠른 시작

```bash
cp .env.example .env          # 값을 채웁니다 — 비밀값은 여기에만
docker compose up -d --build  # MySQL + backend
```

Gradle 로 직접 띄우려면(JDK 21 · MySQL 8 필요):

```bash
SPRING_PROFILES_ACTIVE=dev ./gradlew bootRun
```

Windows:

```powershell
$env:SPRING_PROFILES_ACTIVE="dev"
.\gradlew.bat bootRun
```

운영 DB 를 건드리지 않고 로컬에서 돌리는 방법은 [LOCAL_DEV.md](LOCAL_DEV.md) 에 있습니다.

## 검증

```bash
./gradlew test jacocoTestReport jacocoTestCoverageVerification
```

- 커버리지 게이트는 인증 패키지에 걸려 있고 내리지 않습니다.
- `ModularityBaselineTest` 가 모듈 경계 위반 수를 기준선으로 잠급니다 — 늘면 빨간불이고, 줄었으면 기준선을 내립니다.
- `SchemaDdlDriftTest` 가 엔티티와 `mysql/init/01_schema.sql` 을 대조합니다. 스키마 정본을 손으로 고치지 않습니다 — [mysql/README.md](mysql/README.md).
- 문서 드리프트 검사(`DocDriftTest` · `StructureDocDriftTest` 등)가 `docs/` 를 코드와 대조합니다.

## 설정 구조

- 공통: `src/main/resources/application.properties` — 비밀값이 아닌 기본값만
- 프로필: `application-dev.properties` · `application-prod.properties` (prod 는 `ddl-auto=validate`)
- 비밀값: `.env`(로컬·서버) 또는 환경변수 — DB 비밀번호, JWT secret, OAuth client secret, AWS 키, 공공데이터 서비스키, Apple 키, OpenAI 키, Slack webhook. **Git 에 커밋하지 않습니다.**

Docker MySQL 초기화 값(`MYSQL_ROOT_PASSWORD` · `MYSQL_DATABASE` · `MYSQL_USER` · `MYSQL_PASSWORD`)은 `mysql_data` 볼륨이 처음 생성될 때만 적용됩니다.

## 공공데이터 키

세 API 가 같은 `TOUR_API_SECRET`(data.go.kr 서비스키)을 쓰지만 **활용신청은 각각** 해야 합니다 — 한국관광공사 반려동반(`KorPetTourService2`) · 행정안전부 동물병원/동물판매업 인허가 · 두루누비 걷기여행길. 키가 없거나 미등록이면 서버는 뜨고 그 레이어만 비어 있습니다(#291).

## 운영 메모

- 레이트리밋은 `security/ApiRateLimitFilter` 가 경로별 버킷으로 겁니다. 공개 경로는 표에 없으면 한도가 **무한**이라, 공개 매처를 더할 때 버킷도 함께 더합니다(`PublicPathsAreRateLimitedTest` 가 잽니다).
- 비밀값 스캔: `.github/workflows/secret-scan.yml`(gitleaks).
- 관측: `docker-compose.observability.yml` 로 Prometheus·Grafana 를 띄웁니다 — [grafana/README.md](grafana/README.md).

## 문서

- 이 디렉터리의 `docs/` 는 감정 여행 시절부터 이어진 **운영·전환 기록**입니다. 제품 문서의 정본은 저장소 루트의 [`docs/`](../docs/README.md) 입니다.
