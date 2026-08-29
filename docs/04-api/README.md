# API 계약 사용법 (design-first)

Pawloop은 **프론트 먼저(design-first)** 개발이라, [`openapi.yaml`](openapi.yaml)(OpenAPI 3.1)이 프론트-백 사이의 **단일 계약(SSOT)** 입니다. 이 파일 하나로 ① 문서 ② 목 서버 ③ 코드 생성을 모두 할 수 있습니다.

- 사람이 읽는 서술 명세: [`api-spec.md`](api-spec.md)
- 기계가 읽는 계약: [`openapi.yaml`](openapi.yaml) ← 코드 생성·목·문서의 소스

> 스펙 검증: `npx @redocly/cli lint docs/04-api/openapi.yaml` (현재 valid, operationId 경고만).

> ⚠️ **Windows `cmd` 사용자** — 아래 명령은 모두 **한 줄**입니다(복붙 그대로 OK). `\`로 줄을 나누는 건 bash(리눅스/맥) 문법이라 `cmd`에선 깨집니다. cmd에서 굳이 여러 줄로 쓰려면 줄 끝에 `^`, PowerShell이면 백틱(`` ` ``)을 쓰세요. npx가 처음이면 `Ok to proceed? (y)`에 `y`.

---

## 1. 인터랙티브 문서 (Redoc / Swagger UI)

```bash
# Redoc 정적 HTML 생성(redocly v2 — preview-docs는 없어졌고 build-docs 사용)
npx @redocly/cli build-docs docs/04-api/openapi.yaml -o docs/04-api/index.html
# → 생성된 docs/04-api/index.html 을 브라우저로 열기

# (대안) Swagger UI 라이브
npx swagger-ui-watcher docs/04-api/openapi.yaml
```

백엔드엔 이미 `springdoc-openapi`가 있어, 구현 후 `/swagger-ui.html`·`/v3/api-docs`가 **자동 생성**됩니다. 그 자동 스펙과 이 `openapi.yaml`을 대조해 계약 일치를 검증하세요.

---

## 2. 목(mock) 서버 — 백엔드 없이 프론트 붙이기 (Prism)

```bash
# 계약대로 응답하는 가짜 서버(예시/스키마 기반)
npx @stoplight/prism-cli mock docs/04-api/openapi.yaml
# → http://127.0.0.1:4010 에서 대기 (openapi.yaml servers에 등록됨)

# 동적 예시(스키마로 랜덤 생성)로 띄우려면
npx @stoplight/prism-cli mock -d docs/04-api/openapi.yaml
```

호출 예:
```bash
curl "http://127.0.0.1:4010/api/places/nearby?lat=37.5665&lng=126.9816"
curl "http://127.0.0.1:4010/api/walks/stats/weekly"
```

Flutter에서 목 서버로 붙이려면 `--dart-define`으로 베이스 URL만 바꾸면 됩니다(에뮬레이터는 `10.0.2.2`가 호스트):
```bash
flutter run --dart-define=API_BASE=http://10.0.2.2:4010
```

---

## 3. 코드 생성 (openapi-generator)

### 3.1 백엔드 — Spring Boot 서버 스텁
```bash
npx @openapitools/openapi-generator-cli generate -i docs/04-api/openapi.yaml -g spring -o build/gen/spring --additional-properties=interfaceOnly=true,useSpringBoot3=true
```
→ 컨트롤러 인터페이스 + DTO 생성. 백엔드는 인터페이스만 `implements` 해서 **로직만** 채우면 계약이 강제됩니다.

### 3.2 프론트 — Dart(dio) 클라이언트
```bash
npx @openapitools/openapi-generator-cli generate -i docs/04-api/openapi.yaml -g dart-dio -o build/gen/dart_client
```
→ 타입 안전한 API 클라이언트 + 모델(Place/Dog/Walk/Post…) 생성. 현재 수제 레포(`pet_places_repository.dart` 등)를 점진적으로 대체 가능.

> 대안: `dart run build_runner` 기반 `openapi_generator`(pub 패키지)로 프로젝트 내 생성도 가능.

---

## 권장 워크플로

1. 프론트 요구 변화 → `openapi.yaml` 먼저 수정 (계약 갱신).
2. `redocly lint`로 검증.
3. Prism 목으로 프론트 개발/테스트.
4. 백엔드는 스텁 생성 후 구현, `springdoc` 자동 스펙과 대조.
5. 배포 후 Dart 클라 재생성 → 프론트 연결.
