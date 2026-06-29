# Documentation

프로젝트 문서는 `docs` 아래에서 역할별로 관리한다.

## Structure

| 경로 | 역할 |
|---|---|
| `docs/architecture` | 시스템 구조, 모듈화, 아키텍처 전환 계획 |
| `docs/database` | DB 스키마, SQL, 쿼리 최적화 |
| `docs/domains` | Tour, Curation 같은 기능 도메인별 설계와 테스트 문서 |
| `docs/engineering` | CI/CD, 코드 스캔, 개발 프로세스 |
| `docs/logs` | 작업 로그, 리뷰 대응, 의사결정 기록 |
| `docs/operations` | 운영 전환, 배포, 보안, 정책, runbook |

## Domain Docs

도메인에 직접 속한 문서는 `docs/domains/{domain}` 아래에 둔다.

예:

- `docs/domains/tour/external-data-pipeline.md`
- `docs/domains/tour/testing/README.md`
- `docs/domains/curation/curation-architecture-review.md`

도메인 테스트 문서는 공통 `testing` 최상위에 따로 두지 않고, 해당 도메인 아래의 `testing` 폴더에 둔다. 테스트가 특정 도메인의 데이터 구조와 시나리오를 강하게 참조하기 때문이다.

## Operations Docs

운영 관련 문서는 `docs/operations` 아래에서 다시 역할별로 나눈다.

- `docs/operations/public-operation-transition`
- `docs/operations/policy`
- `docs/operations/security`
- `docs/operations/runbooks`

## Convention

- 새 문서는 반드시 `docs` 아래에 추가한다.
- `documents` 또는 `documentation` 폴더는 사용하지 않는다.
- 문서 내부 링크는 절대 경로 대신 상대 경로를 사용한다.
- 코드 줄 번호 링크는 리팩토링 시 쉽게 깨지므로, 일반 설명 문서에서는 파일/클래스/메서드 중심으로 참조한다.
