# 기여 안내

포루프(Pawloop)의 이슈·브랜치·커밋·PR 을 어떻게 쓰는지 한 장으로 줄였습니다. 자세한 규칙과 이유는 **[프로젝트 규약 #4](https://github.com/sanghyunbang/pawloop/issues/4)** 에 있습니다.

## 일을 묶는 법 — 목표(🎯)와 하위 이슈

- 모든 작업은 어느 **목표(🎯)** 의 하위 이슈입니다. 목표는 끝이 있는 큰 일이고, 하위 이슈가 모두 닫히면 끝납니다.
- 지금의 목표는 **[목표 목록 #20](https://github.com/sanghyunbang/pawloop/issues/20)**, 진행 상황은 **[프로젝트 보드](https://github.com/users/sanghyunbang/projects/2)** 에서 봅니다.
- 닫지 않고 두는 참조 문서는 **[문서 목차 #823](https://github.com/sanghyunbang/pawloop/issues/823)** 에 모여 있습니다.

## 이슈

- 템플릿(작업 · 버그 · 목표 · 결정 필요)으로 만들고, 목표 아래에 붙입니다.
  ```bash
  gh issue create --parent <목표 번호> --label area/map --label type/bug --label prio/P2
  ```
- **라벨은 3개까지** — 기능 `area/` 하나 · 종류 `type/` 하나 · 우선순위 `prio/` 하나. 3개로 안 되면 이슈가 너무 큰 것이니 쪼갭니다.
- 제목에는 결과 상태를 적습니다. 예: `JWT subject를 users.id로 통일 — 인증 주체 추출 한 곳으로`

## 브랜치

```
<type>/<이슈번호>-<영문-슬러그>
```

예: `fix/782-trail-route-course-id-80`, `feat/718-operator-channel`

## 커밋 — Conventional Commits, 한국어 제목

```
<type>(<scope>): <한국어 제목>
```

- **type** — `feat` · `fix` · `refactor` · `perf` · `style` · `test` · `chore` · `docs`
- **scope** — 고친 코드의 위치: `app`(Flutter 앱) · `server`(Spring Boot) · `infra`(배포·인프라·스크립트) · `docs`(문서) · 여럿이면 `repo`
- 제목은 마침표 없이, 무엇을 왜 바꿨는지 드러나게

```
fix(server): 추천 코스 번호가 들어가게 trail_route.course_id 를 80 으로 넓힌다
```

## PR

- 템플릿을 채웁니다. **어떻게 확인했나**에는 실제로 돌린 것과 테스트 개수를 적습니다 — "빌드됨" 은 확인이 아닙니다.
- 본문의 `Closes #번호` 는 그 PR 하나로 이슈가 끝날 때만 씁니다. 여러 PR 에 걸친 이슈나 목표에는 `관련: #번호` 로 적습니다.
- 스쿼시 머지합니다 — PR 제목이 곧 `main` 의 커밋 제목입니다.

## 결정 기록

되돌리기 비싼 결정은 [`docs/99-decisions/decision-log.md`](docs/99-decisions/decision-log.md) 에 ADR 로 남기고, '결정 필요' 템플릿 이슈에서 논의합니다.
