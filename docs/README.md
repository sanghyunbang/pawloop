# Pawloop(포루프) 문서 인덱스

> 반려동물(강아지 중심) **산책 · 동반장소 지도 · 커뮤니티** 앱 Pawloop(포루프)의 전체 문서 허브. 설계부터 의사결정까지 폴더(01~99) 순서대로 읽으면 시스템 전체 그림이 잡힙니다. — by cetaceaLab

---

## 한 줄 소개

**Pawloop(포루프)** = "반려동물과 함께 걷고, 동네 반려인들과 연결되는 공간".
산책을 wedge로 좁게 시작해 **반려 일상 로그(산책→건강·식사·병원·동네) + 동반장소 지도 + 커뮤니티**로 확장하는 앱입니다. (기존 감정 여행 heattrip에서 2026-07 피벗, 감정 요소 전부 제거)

- **프론트**: Flutter 3.44.4 / Dart 3.12.2 · flutter_naver_map · fl_chart · Fluent Emoji 3D · Pretendard
- **백엔드**: Spring Boot + MySQL(공간형 POINT/LINESTRING, SPATIAL INDEX)
- **외부 데이터**: 관광공사 KorPetTourService2(반려동반), LOCALDATA(동물병원), 두루누비(산책로)

---

## 읽는 순서

`① 설계·디자인(01) → ② 아키텍처(02) → ③ DB(03) → ④ API(04) → ⑤ 빌드(05) → ⑥ 테스트(06) → ⑦ 의사결정(99)`

---

## 폴더별 문서 목록

### 01-design — 설계·디자인
| 문서 | 설명 |
|:---|:---|
| [정보구조(IA)](01-design/information-architecture.md) | 5탭 + 화면 트리 (mermaid) |
| [사용자 플로우](01-design/user-flows.md) | 산책·장소·커뮤니티·온보딩 플로우 (mermaid) |
| [기능 명세](01-design/feature-spec.md) | MVP + 확장 기능 상세 |
| [디자인 시스템](01-design/design-system.md) | 오라 배경 · 글래스 카드 · 토큰 · Fluent Emoji |
| [화면 명세](01-design/screen-spec.md) | 화면별 구성·상호작용·데이터 |

### 02-architecture — 아키텍처
| 문서 | 설명 |
|:---|:---|
| [시스템 개요](02-architecture/system-overview.md) | 앱·백엔드·DB·공공데이터 구성도 (mermaid) |
| [기술 스택](02-architecture/tech-stack.md) | 버전·패키지·툴체인 표 |
| [프론트엔드 구조](02-architecture/frontend-structure.md) | lib/v2 · 상태관리 · 라우팅 |
| [백엔드 구조](02-architecture/backend-structure.md) | Spring 패키지 · 레이어 |
| [외부 데이터 연동](02-architecture/external-data.md) | KTO · LOCALDATA · 두루누비 · 좌표변환 |

### 03-database — 데이터베이스
| 문서 | 설명 |
|:---|:---|
| [ERD](03-database/erd.md) | 개체-관계도 (mermaid erDiagram) |
| [스키마](03-database/schema.md) | 테이블별 DDL · 인덱스(SPATIAL) |
| [마이그레이션](03-database/migration.md) | 스키마 관리 · 공공데이터 동기화 배치 |

### 04-api — API
| 문서 | 설명 |
|:---|:---|
| [API 명세](04-api/api-spec.md) | 장소·산책·커뮤니티·인증·프로필 엔드포인트 |

### 05-build — 빌드·운영
| 문서 | 설명 |
|:---|:---|
| [MVP 범위](05-build/mvp-scope.md) | In/Out-of-scope · 완료 정의 |
| [로드맵](05-build/roadmap.md) | 마일스톤(위치→로그인→실데이터→확장로그→출시) |
| [구현 현황](05-build/implementation-status.md) | 화면·기능별 상태(완료/더미/미구현) |
| [개발 환경 세팅](05-build/setup.md) | Flutter · `--dart-define` · 에뮬 · 빌드 명령 |

### 06-testing — 테스트
| 문서 | 설명 |
|:---|:---|
| [테스트 체크리스트](06-testing/test-checklist.md) | 화면별 수동 검증 + 자동화 계획 |

### 99-decisions — 의사결정 기록
| 문서 | 설명 |
|:---|:---|
| [결정 기록(ADR)](99-decisions/decision-log.md) | 피벗·Pawloop·RDB중심·KTO·Flutter 업그레이드 등 |

---

## 참고

- 문서 언어: **한국어** / 앱 이름 표기: 항상 **Pawloop(포루프)**
- 소스 기준 경로: 프론트 [`app/lib/v2`](../app/lib/v2), 도메인 [`app/lib/v2/domain/pet.dart`](../app/lib/v2/domain/pet.dart), KTO 연동 [`app/lib/v2/data/pet_places_repository.dart`](../app/lib/v2/data/pet_places_repository.dart)
