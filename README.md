# Pawloop(포루프) 🐾

> **반려동물과 함께 걷고, 가족과 나누고, 동네 반려인들과 연결되는 공간.**
> 산책 GPS 트래킹 · 반려동반 장소 지도 · 가족 케어 공유 · 일정 · 커뮤니티 · 채팅 — Flutter 앱과 Spring Boot 서버를 함께 담은 모노레포입니다.

<p>
  <img src="docs/01-design/references/ours-white-home.jpg" width="156" alt="홈" />
  <img src="docs/01-design/references/ours-white-map.jpg" width="156" alt="지도" />
  <img src="docs/01-design/references/ours-white-schedule.jpg" width="156" alt="일정" />
  <img src="docs/01-design/references/ours-white-feed.jpg" width="156" alt="커뮤니티" />
  <img src="docs/01-design/references/ours-white-chat.jpg" width="156" alt="채팅" />
</p>

산책을 좁은 쐐기로 시작해 **반려 일상(산책 → 건강·식사·병원·동네)** 으로 넓히는 앱입니다. 다섯 탭 — 홈 · 지도 · 일정 · 커뮤니티 · 채팅 — 이고 다섯 칸이 같은 폭입니다. 산책은 홈의 "산책 시작" 이 열고, 통계는 홈과 프로필에서 들어갑니다.

---

## 무엇을 하는 앱인가

| | |
| :--- | :--- |
| **산책** | 실 GPS 경로 기록 · 라이브 스탯 · 산책 중 사진 · 끝내면 서버 저장(못 보내면 초안 큐) · 코스로 남기기 |
| **지도** | 반려동반 장소(관광공사) · 동물병원 · 펫샵(행정안전부 인허가) · 산책로(두루누비 · 동네 길 1,302개) · 놀이터 — 전부 실데이터 |
| **일정** | 월 달력 · 반복 · 담당자 · 알림(전날 저녁·당일 아침) · 완료하면 오늘의 케어에 한 줄이 남습니다 |
| **가족** | 초대코드로 묶인 가족 그룹 · 오늘의 케어 공유(밥·물·산책·투약·병원) · 산책 주의사항 |
| **채팅** | 가족 방 · 크루 방 · 사진 · 답장(인용) · 반응 · 미읽음 · 신고/가리기/강퇴 |
| **커뮤니티** | 동네 반려인 게시판 — 글·댓글·반응·사진/영상·저장한 글, 그리고 **크루**(동네 모임 · 품앗이) |
| **통계** | 주간 산책 차트 · 자주 가는 곳 · **AI 주간 요약 두 문장**(규칙 문장이 먼저, AI 는 그 아래) |

---

## 숫자로 보는 저장소

| | 앱 (Flutter) | 서버 (Spring Boot) |
| :--- | ---: | ---: |
| 제품 코드 | 172 파일 · 44,824 줄 | 395 파일 · 38,001 줄 |
| 테스트 코드 | 215 파일 · 35,178 줄 | 208 파일 · 51,951 줄 |
| 테스트 수 | 1,673 | 1,600 |

| | |
| :--- | ---: |
| 화면 | 32 |
| 계약(openapi) 경로 | 78 |
| DB 테이블 | 35 |
| 마이그레이션 스크립트 | 48 |
| 결정 기록(ADR) | 23 |
| 문서 | 43 파일 · 15,972 줄 |

> 서버는 **테스트 코드가 제품 코드보다 깁니다.** 대부분이 목이 아니라 Testcontainers 로 진짜 MySQL 을 띄우는 통합 테스트이고, 나머지는 계약·문서·마이그레이션을 코드와 대조하는 게이트입니다.

---

## 아키텍처

```mermaid
flowchart LR
    subgraph app["Flutter 앱"]
        UI["화면 v2/screens"] --> DATA["저장소·정책 v2/data"]
        UI --> DOMAIN["순수 규칙 v2/domain"]
        DATA --> HTTP["AuthedClient<br/>401 자동 갱신"]
    end

    HTTP -->|"REST · openapi.yaml"| API["Spring Boot"]

    subgraph server["서버 · Spring Modulith 경계"]
        API --> CHAT["chat"]
        API --> WALK["walk"]
        API --> COMMUNITY["community"]
        API --> PLACE["place"]
        API --> SCHEDULE["schedule"]
        API --> MOD["moderation"]
    end

    PLACE -->|"서버만 키를 든다"| KTO["관광공사 · 행정안전부 · 두루누비"]
    WALK --> AI["OpenAI · 주간 요약 두 문장"]
    server --> DB[("MySQL 8<br/>LINESTRING · 격자 캐시")]
    server --> S3[("S3 · 미디어")]
```

| | 무엇 | 왜 이 선택인가 |
| :--- | :--- | :--- |
| 앱 | Flutter 3.44.4 / Dart 3.12.2 · `flutter_naver_map` · `fl_chart` · `go_router` · `provider` | 한 코드베이스로 양대 스토어. 지도는 국내 좌표·POI 품질 때문에 네이버 |
| 서버 | Java 21 · Spring Boot 3.5.4 · Spring Modulith · JPA · JWT | 모듈 경계를 **구조 검사**로 강제하되 이벤트는 들이지 않았습니다([ADR-0012](docs/99-decisions/decision-log.md)) |
| DB | MySQL 8 + `hibernate-spatial` | 경로는 `LINESTRING`, 장소는 0.02° 격자 캐시. **`SPATIAL INDEX` 는 만들지 않습니다**([ADR-0015](docs/99-decisions/decision-log.md)) |
| 계약 | `docs/04-api/openapi.yaml` 하나가 정본 | 앱과 서버가 같은 문서를 보고, 스펙 테스트가 컨트롤러와 대조합니다([ADR-0017](docs/99-decisions/decision-log.md)) |
| 관측 | Micrometer · Prometheus · Grafana | 폴링의 빈 응답 비율처럼 **설계를 바꿀 근거**가 되는 수만 봅니다 |

---

## 엔지니어링에서 볼 만한 것

### 1. 채팅 폴링의 커서는 `id` 가 아니라 방별 순번입니다

`AUTO_INCREMENT` 는 배정 시점에 정해지고 가시성은 커밋 시점에 생깁니다. `id` 를 커서로 쓰면 **늦게 커밋된 작은 id 를 영구히 건너뜁니다.** 그래서 방마다 `room_seq` 를 발급하고, 발급은 MySQL 이 문서로 제시한 한 문장(`UPDATE … SET last_seq = LAST_INSERT_ID(last_seq + 1)`)으로 합니다. 스레드 20개를 같은 방에 붙여 재 보니, 읽고-더해-쓰는 판은 **20개 중 17개가 죽었습니다.**

미읽음은 캐시가 아니라 `room.last_seq − member.last_read_seq` 뺄셈이고, 지워진 말도 목록에서 빼지 않습니다 — 빼면 그 번호가 클라이언트에 도달하지 않아 뱃지가 영원히 안 지워집니다. → [ADR-0011](docs/99-decisions/decision-log.md)

### 2. 이미 보낸 말이 바뀌면 폴링이 못 봅니다 — 축을 하나 더 놨습니다

델타는 커서보다 **큰** 번호만 줍니다. 그래서 남이 지운 말도, 반응이 붙은 말도 영영 오지 않았습니다. 방 단위 **변경 번호**를 따로 발급해 바뀐 행에 찍고 응답에 `changed` 를 더했습니다. `room_seq` 를 다시 발급하는 길은 기각했습니다 — 오래된 말이 대화 맨 아래로 뛰고 모두의 미읽음이 1 늘기 때문입니다. → [ADR-0023](docs/99-decisions/decision-log.md)

<p><img src="docs/01-design/references/ours-452-chat-reaction.jpg" width="680" alt="길게 눌러 고른 반응이 칩으로 붙고, 남이 누른 반응이 폴링에 따라온다" /></p>

### 3. 멱등을 DB 제약 위에 세웁니다

- 전송은 `clientMsgId` 와 `UNIQUE (room_id, sender_user_id, client_msg_id)`. 재전송은 409 가 아니라 **200** 입니다 — 재시도한 쪽 입장에서 그 요청은 성공했습니다.
- 반응·저장은 토글 하나가 아니라 **켜기(`POST`)와 끄기(`DELETE`)** 입니다. 토글이면 네트워크 재시도 한 번이 사용자의 반응을 조용히 되돌립니다.
- 삽입은 `ON DUPLICATE KEY UPDATE id = id` 한 문장입니다. 예외를 삼키는 판은 트랜잭션이 rollback-only 로 표시돼 **동시 요청에서만** 500 이 납니다.

### 4. 좌표와 EXIF 는 기기에서 지우고 올립니다

사진에는 촬영 위치가 실려 있습니다. 앱이 올리기 전에 다시 인코딩해 EXIF 를 지우고, 영상은 위치 상자를 덮은 뒤 흔적이 남으면 **올리지 않습니다.** 테스트가 나간 바이트를 값으로 잽니다. 좌표가 기기를 떠나는 경로 자체도 컴파일 타임 정책 한 곳으로 모았습니다. → [ADR-0018](docs/99-decisions/decision-log.md) · [위치정보법 정리](docs/00-product/legal-lbs-compliance.md)

### 5. 마이그레이션은 문서가 아니라 검사입니다

`backend/mysql/post-start/` 의 48개 스크립트는 전부 **멱등**이고, 사전 점검과 사후 검증(`[D]` 블록)이 붙어 있어 모양이 다르면 스스로 멈춥니다. 스크립트마다 **진짜 MySQL 컨테이너에 돌려 보는 실행 테스트**가 있고, 런북과 확인 스크립트에 빠진 파일이 없는지도 테스트가 잠급니다.

```bash
bash scripts/check-migrations.sh    # 이 DB 에 무엇이 덜 들어갔는지 묻고, 돌릴 파일 이름을 찍는다
```

### 6. 모듈 경계를 테스트가 지킵니다

`chat` 은 `users`·`family_group`·`dog` 로 **FK 를 내지 않습니다.** 걸면 탈퇴 경로가 DB 삭제 순서에 묶이고, `CASCADE` 면 탈퇴 한 번에 남의 대화가 사라집니다. 이 규칙은 주석이 아니라 검사입니다 — 커밋된 DDL 을 빈 DB 에 **실제로 적용해** `chat_*` 의 FK 목록을 읽고, 밖으로 나간 것이 하나라도 있으면 빨간불입니다.

### 7. 문서와 계약이 코드와 어긋나면 빌드가 멈춥니다

계약의 경로 집합과 컨트롤러 매핑, 스키마 문서와 정본 DDL, 결정 기록의 목차와 본문, 화면 문서와 실제 화면 파일 — 넷 다 테스트가 대조합니다. 이 저장소에서 문서는 "나중에 고치는 것" 이 아닙니다.

### 8. "테스트를 넣었다" 를 근거로 치지 않습니다

기능마다 **되돌려서 빨간불**을 남깁니다. 코드에 변형을 하나 넣고(들어갔는지 `grep` 으로 확인), 테스트가 실제로 빨간불인지 보고, 되돌린 뒤 해시로 대조한 표를 PR 에 붙입니다. 이 방법으로 *테스트는 초록인데 아무것도 지키지 못하던* 자리를 여러 번 찾았습니다 — 가장 최근에는 알림 정책이 플러그인을 아는 파일 안에 있어 테스트가 닿지 못하던 것을 순수 함수로 떼어 냈습니다.

---

## 화면 몇 장 더

| 산책 기록과 사진 | AI 주간 요약 | 경로 위 지도 |
| :---: | :---: | :---: |
| <img src="docs/01-design/references/ours-450-walk-photos.jpg" width="240" alt="산책 사진" /> | <img src="docs/01-design/references/ours-486-ai-summary.jpg" width="240" alt="AI 주간 요약" /> | <img src="docs/01-design/references/ours-483-map-ground.jpg" width="240" alt="경로 위 지도" /> |

레퍼런스와 우리 화면의 전·후 캡처는 [`docs/01-design/references/`](docs/01-design/references/) 에 출처와 함께 모여 있습니다.

---

## 시작하기

```bash
git clone https://github.com/sanghyunbang/heattrip.git
cd heattrip

# 앱 — Flutter 3.44.4
cd app
flutter pub get
flutter run --dart-define-from-file=dart-define.json   # 예시는 dart-define.example.json

# 서버 — JDK 21 + MySQL 8 (+ Docker: 통합 테스트가 Testcontainers 를 쓴다)
cd ../backend
./gradlew bootRun --args='--spring.profiles.active=dev'
```

환경값은 `.env` 에셋이 아니라 **컴파일 타임 `--dart-define`** 으로 들어갑니다 — 번들된 `.env` 는 APK 안에 원문 그대로 실려 나갑니다. 외부 API 서비스키는 **서버 환경변수로만** 존재하고 앱에는 지도 SDK 키 하나만 남습니다.

설치·에뮬레이터·소셜 로그인 로컬 테스트는 [개발 환경 세팅](docs/05-build/setup.md)에 있습니다.

## 검증

```bash
bash scripts/local-ci.sh            # 앱 · 서버 · 문서 전부
bash scripts/local-ci.sh backend    # 하나만 (backend | app | docs)
```

깃헙 액션 워크플로(`.github/workflows/ci.yml`)는 **지금 꺼져 있습니다.** private 저장소라 액션이 계정의 Actions 분을 쓰고, 분이 떨어지면 잡이 시작조차 못 합니다. 같은 명령을 로컬에서 돌리고 그 로그를 PR 본문에 근거로 남깁니다 — 워크플로를 다시 켤 때의 잡 구성은 파일에 그대로 있습니다.

---

## 문서

전체 인덱스는 [`docs/README.md`](docs/README.md) 입니다. 이 저장소를 처음 본다면 이 순서를 권합니다.

| | |
| :--- | :--- |
| [구현 현황](docs/05-build/implementation-status.md) | 화면·기능이 지금 어디까지 와 있는가 |
| [결정 기록(ADR) 23건](docs/99-decisions/decision-log.md) | 무엇을 **고르지 않았는지**까지 적혀 있습니다 |
| [시스템 개요](docs/02-architecture/system-overview.md) · [백엔드 구조](docs/02-architecture/backend-structure.md) · [프론트 구조](docs/02-architecture/frontend-structure.md) | 구성도와 패키지 규약 |
| [ERD](docs/03-database/erd.md) · [스키마](docs/03-database/schema.md) | 표 35개의 DDL·제약·인덱스와 그 이유 |
| [openapi.yaml](docs/04-api/openapi.yaml) · [API 명세](docs/04-api/api-spec.md) | 계약 정본과 사람이 읽는 판 |
| [디자인 시스템](docs/01-design/design-system.md) · [화면 명세](docs/01-design/screen-spec.md) | 흰 바탕 · 외곽선 카드 · 코랄레드 하나 |
| [제품 기획](docs/00-product/concept.md) · [페르소나](docs/00-product/personas.md) · [수익화](docs/00-product/monetization.md) | 왜 이 제품인가 |

---

## 지금 상태

커뮤니티 · 실데이터 지도 · 일정 · 크루 · 채팅(사진·답장·반응·변경 피드)까지 서버 연동이 끝났습니다. 남은 것은 **푸시의 Firebase 키 파일 둘**과 **iOS 실기기 QA**, 그 뒤가 확장 로그와 출시입니다. 화면에 아직 자리만 있는 것은 지도 검색창과 기록 화면의 날짜 선택 둘입니다. 마일스톤은 [로드맵](docs/05-build/roadmap.md)에 있습니다.

<details>
<summary><strong>저장소 이름이 <code>heattrip</code> 인 이유</strong></summary>

<br/>

이 프로젝트는 2026-07 에 **감정 여행 앱 heattrip → 반려 앱 Pawloop(포루프)** 로 피벗했습니다. 제품·도메인·화면은 전부 교체됐고, 앱 식별자도 2026-09-17 에 `app.pawloop` 으로 옮겼습니다([#597](https://github.com/sanghyunbang/heattrip/issues/597)) — 사기로 한 도메인 `pawloop.app` 을 뒤집은 것입니다.

[ADR-0002](docs/99-decisions/decision-log.md)가 식별자 변경을 "스토어 등록 시점에 일괄 정리" 로 미뤄 뒀는데, 그 시점이 왔습니다. 식별자를 바꾸면 스토어 등록·재서명·OAuth 콘솔 재등록이 연쇄로 따라오므로, **첫 등록 전이 유일하게 싼 때**입니다.

아직 옛 이름이 남은 곳이 있습니다 — 저장소 이름, Gradle group(`com.heattrip`), DB 이름(`heat_trip_db`), Dart 패키지명(`heat_trip_flutter`). 넷 다 사용자에게 안 보이고 스토어 등록과도 무관해서 미뤄 둔 것입니다. 로그인 콜백 스킴은 이 목록에서 빠졌습니다 — 2026-09 에 `pawloop://login-callback` 으로 옮겼습니다([#649](https://github.com/sanghyunbang/heattrip/issues/649)). 같은 스킴을 주장하는 예전 앱이 콜백을 가로채서, 미룰 수 있는 이름이 아니었습니다. 운영 API 주소도 `api.pawloop.app` 입니다([#682](https://github.com/sanghyunbang/heattrip/issues/682)). 감정 여행 시절의 서버 패키지와 앱 셸은 2026-09-06 에 지웠습니다. **문서와 UI 표기는 언제나 Pawloop(포루프)** 입니다.

</details>

## 라이선스

아직 라이선스 파일이 없습니다. 라이선스가 명시되지 않은 저장소는 저작권자에게 모든 권리가 있으며 복제·수정·재배포가 허용되지 않습니다. 공개 전환 시 무엇을 붙일지는 소유자가 정할 사항이라 임의로 고르지 않았습니다.

---

*cetaceaLab*
