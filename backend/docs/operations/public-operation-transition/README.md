# 이 폴더를 읽는 법 — 2026-03 의 기록이고, 지금 상태가 아니다

- 이 안내: 2026-10-22
- 폴더 안의 문서들: 2026-03-18 ~ 2026-04

**이 폴더의 문서들은 "지금 이런 상태다" 가 아니라 "그때 이런 상태였고 이렇게 하기로
했다" 는 기록이다.** 그 뒤에 처방이 실행되고 구조가 바뀌었다. 그래서 문서 본문을
현재형으로 읽으면 사실과 어긋난다.

어긋나는 자리를 그냥 지우지 않고 이 안내를 둔 이유는, **왜 그렇게 결정했는지가 결론보다
오래 쓸모 있기** 때문이다. 다만 그걸 읽는 사람이 "지금도 비밀번호가 평문으로 있구나" 로
오해하면 안 되므로, 무엇이 바뀌었는지를 여기 못 박는다.

## 무엇이 바뀌었나

### 1. 처방이 실행됐다 — 저장소를 새로 시작했다

[PublicTransitionPlan.md](../PublicTransitionPlan.md) 의 기본 원칙은 이랬다.

> 현재 private 저장소를 그대로 public 으로 전환하지 않는다.
> 비밀값과 운영 정보를 제거한 새 public 저장소를 만든다.

**그대로 됐다.** 이 저장소의 첫 커밋이 `87ec6f1d`(2026-06-29, "consolidate Flutter +
backend into one monorepo", 735개 파일)이고, **그 전 히스토리는 들어오지 않았다.**
스냅샷으로 새로 시작한 저장소다.

그래서 문서들이 걱정한 "과거 커밋에 남은 값" 은 **이 저장소에 없다.** 그 값들이 있던
커밋은 다른 저장소에 있고, 여기로 오지 않았다. 자세한 것은
[24번 문서의 머리말](24_public_conversion_secret_rotation_and_history_cleanup.md)에
적어 뒀다 — **그 문서의 처방(운영 비밀번호 재발급 + 히스토리 다시 쓰기)은 실행하면 안
된다.**

### 2. 운영 구조가 통째로 달라졌다

| | 문서가 쓰인 때 (2026-03) | 지금 (2026-10) |
|---|---|---|
| 서버 | 집에 둔 Mac mini | AWS EC2 |
| 앞단 | Cloudflare Tunnel (`cloudflared`) | Caddy (`backend/Caddyfile`) |
| 도메인 | 문서에 박혀 있었다 | `{$PAWLOOP_DOMAIN}` 환경변수 |
| 배포 | self-hosted 러너 | `ubuntu-latest` + `scripts/deploy-bluegreen.sh` |
| `recommender` (파이썬) | `*:8000` 으로 떠 있었다 | **그 서비스가 없어졌다** |
| 비밀값 정본 | 호스트의 파일 | SSM 파라미터 하나 (`scripts/set-prod-env.sh`) |

그래서 9·11·13·14·16·17·19·20번(Mac mini·nginx·cloudflared) 문서는 **지금 쓰이지 않는
구조**를 설명한다. 21번이 걱정한 `recommender` 의 `*:8000` 은 그 서비스가 사라져서 해당 사항이
없다.

### 3. 조용히 멈춘 것 — gitleaks 스캔은 한 번도 안 돌았다

[5_current_status.md](5_current_status.md) 가 반영했다고 적은 항목에
`GitHub Actions gitleaks secret scan 추가` 가 있다. 파일은 실제로 있다 —
`backend/.github/workflows/secret-scan.yml`. **그런데 한 번도 돈 적이 없다.**

깃헙 액션은 **저장소 루트의 `.github/workflows/`** 만 읽는다. `backend/` 가 독립
저장소였을 때는 그 자리가 루트였으니 돌았다. 모노레포로 합칠 때(`87ec6f1d`)
`backend/.github/workflows/` 로 한 칸 내려앉았고, 그때부터 깃헙은 그 파일을 **아예
모른다.** 2026-10-22 에 확인한 등록 목록에는 `CI` 하나만 있다.

같은 자리에 `qodana_code_quality.yml` 도 있고 같은 이유로 안 돈다.

> **이 모양이 제일 위험한 종류다.** 파일이 있고, 문서에 "추가했다" 고 적혀 있고,
> 아무 에러도 안 난다. 없는 것보다 나쁘다 — 있다고 믿게 되니까.

고치려면 두 파일을 루트 `.github/workflows/` 로 옮기면 된다. 이슈로 남겼다.

> 덧붙여, 루트의 `CI` 워크플로는 2026-10-22 기준 `disabled_manually` 다. 마지막 실행은
> 2026-09-13 이고 전부 실패했다(지출 한도 — 이슈 #412). 공개로 돌려도 **그것만으로는
> 자동으로 안 돈다.** 한도와 활성화가 함께 필요하다.

### 4. 문서에 박혀 있던 남의 로컬 경로를 치웠다

이 폴더의 문서들은 스스로 이렇게 적었다.

> 서버 주소, 내부 경로, 러너 경로 같은 운영 정보가 없어야 한다.

**그 항목이 그 문서들 안에 있었다.** 2026-10-22 에 치운 것 —

| 있던 것 | 몇 줄 | 바꾼 것 |
|---|---|---|
| `/C:/Users/mm206/git_projects/heat_trip_backend/…` | 41 | 저장소 상대 링크 |
| `/Users/hyun/…` (Mac mini 운영 홈) | 24 | `<운영 홈>` |
| cloudflared 터널 ID | 1 | `<터널 ID>` |

첫째 것은 **마크다운 링크 대상이라 전부 깨져 있었다**(42개). `backend/` 로 다시
가리키게 해서 링크가 살아났고, 계정 이름은 함께 사라졌다. 없어진 파일
(`deploy-backend.yml`) 하나는 링크를 떼고 코드 글자로 두면서 지금 무엇이 그 일을 하는지
적었다.

## 지금 사실은 무엇인가 — 2026-10-22 실측

공개 전환 직전에 24번 문서의 "수동 검증 명령" 을 그대로 돌리고, 그 그물이 놓치는 것을
두 가지 더 쟀다. 숫자 없이 "깨끗하다" 고 쓰지 않으려고 전부 적는다.

| 본 것 | 결과 |
|---|---|
| `.env`·`application-private.properties` 추적 이력 | 0건. 객체에도 없다 |
| `docker-compose*.yml` 의 **과거 판본 14개** 비밀번호 줄 | 전부 `${환경변수}` 참조 |
| 키 패턴 8종 × 히스토리 텍스트 블롭 6,009개 | 적중 8건 — **전부 가짜**(아래) |
| 비밀스러운 이름의 대입문 2,122건의 **값** | 실제 비밀 **0건** |
| 저장소에 적힌 공인 IP | 전부 RFC 5737 예시 대역(`203.0.113.x`·`198.51.100.x`) |
| `sg-`·`vpc-`·`subnet-`·`ami-`·계정번호 | 0건 |
| `.tfstate`·`.tfvars` | 추적 안 됨(`.example` 만) |
| 워크플로 | `runs-on: ubuntu-latest` · `secrets.GITHUB_TOKEN`·`secrets.QODANA_TOKEN` 만 |
| 운영에서 쓰는 비밀 8개 | 문서가 유출됐다고 적은 값들과 **전부 다르다** |

적중 8건이 전부 가짜인 이유 —

- **2건**은 디자인 핸드오프 HTML 에 내장된 이미지의 base64 **한가운데**다. `AIza` 가
  우연히 그 안에 들어 있고, 앞뒤가 `+`/`/`/`=` 로 이어진다.
- **6건**은 애플 로그인 키를 **다루는 코드**의 문자열 리터럴이다 —
  `.replace("-----BEGIN PRIVATE KEY-----", "")` 같은 것. 검사 쪽 둘은
  `KeyPairGenerator` 로 그 자리에서 만든 키를 PEM 모양으로 감싼다.

### ⚠️ 패턴 검사만으로는 이 답을 낼 수 없었다

처음에는 키 패턴(`AKIA`·`AIza`·`ghp_`·`sk-`·`xox`·PEM)만 돌리고 "히스토리 깨끗하다" 고
적었다. **틀린 근거였다.** 24번 문서가 유출됐다고 적은 `supersecret` 같은 **평범한 낱말
비밀번호는 접두사가 없어서 어떤 패턴에도 안 걸린다.**

그래서 셋을 다 해야 근거가 된다.

1. 키 패턴 — 접두사가 있는 것
2. **그 값 자체를 문자열로** 찾기 (`git log --all -S"<값>"`, 전 블롭 훑기)
3. **비밀스러운 이름의 대입문의 값**을 꺼내 보기. 자리표시자·환경변수 참조·코드
   표현식·URL 을 이유를 붙여 뺀 뒤 남는 것만 본다

3번을 엔트로피만으로 하면 긴 메서드 이름과 한국어 산문이 수백 건 걸려서 아무도 안 본다.
`gitleaks` 를 대신한 자리다.

> `git grep <패턴> $(git rev-list --all)` 은 ref 697개 × 트리를 각각 훑어서 20분이 넘어도
> 안 끝난다. `git cat-file --batch-all-objects` 로 블롭을 한 번만 훑으면 같은 답이 1분이다.

## 공개 뒤에도 남는 것

- **`docker-compose.observability.yml` 의 Grafana 기본 비밀번호.**
  `GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD:-change-me-grafana-password}` 의
  그 기본값이 공개된다. 운영 설정에 `GRAFANA_ADMIN_PASSWORD` 가 없고, 어느 배포 경로도
  그 파일을 띄우지 않으니 지금은 자는 위험이다. **그 파일을 켜는 날에는 관리자
  비밀번호가 이미 공개돼 있다.**
- **글 거르기 목록은 히스토리에 남는다.** 이슈 #789 로 코드에서 설정으로 뺐지만, 옛
  목록은 `git log -p` 로 읽힌다. 손실은 생각보다 작다 — 거절 문구가 걸린 낱말을
  안 알려 주더라도 "막혔다" 는 것은 알 수 있고, 말풍선 레이트리밋이 60/분이라
  **밖에서 1분 안에 목록을 떠볼 수 있었다.** 값진 것은 숨기는 쪽이 아니라 목록을 계속
  키우는 쪽이고, 이제 배포 없이 되니 그게 싸다.
- **운영 설정의 `SPRING_DATASOURCE_PASSWORD`(12자)는 쓰이지 않는다.**
  `docker-compose.yml` 의 `environment:` 에 `SPRING_DATASOURCE_PASSWORD=${MYSQL_PASSWORD}`
  가 있어 `env_file` 값을 덮는다. 구멍은 아니지만, 이 줄을 보고 그 값이 쓰인다고 믿게
  되는 자리다.

## 문서별로 무엇을 조심할까

| 문서 | 읽는 법 |
|---|---|
| [`../PublicTransitionPlan.md`](../PublicTransitionPlan.md) | 인벤토리 표와 "현재 위험" 절은 **옛 저장소** 기준. 머리말에 바로잡아 뒀다 |
| [`24_...history_cleanup.md`](24_public_conversion_secret_rotation_and_history_cleanup.md) | **처방을 실행하지 마라.** 머리말 참고 |
| [`1_db_refactoring.md`](1_db_refactoring.md) · [`2_config_examples.md`](2_config_examples.md) · [`3_deployment_publicization.md`](3_deployment_publicization.md) | `상태: 완료`. 옛 저장소에서 한 일의 기록 |
| 9·11·13·14·16·17·19·20번 | Mac mini + nginx + cloudflared. **지금 구조가 아니다** |
| [`5_current_status.md`](5_current_status.md) | 제목이 "현재 상태" 지만 **2026-03-18 의** 상태다. 그 목록의 gitleaks 항목은 위의 3번을 함께 읽어라 |
| [`15_public_launch_runbook.md`](15_public_launch_runbook.md) · [`18_...final_checklist.md`](18_public_release_final_checklist.md) | 옛 구조 기준 런북·체크리스트. 24번의 검증 명령 쪽이 더 최근이다 |
| [`21_secret_separation...md`](21_secret_separation_and_recommender_hardening.md) | `recommender` 는 그 서비스 자체가 없어졌다 |
| [`22_cicd_option_review.md`](22_cicd_option_review.md) · [`23_...cicd_design.md`](23_backend_and_recommender_cicd_design.md) | 지금 CI/CD 는 이슈 #787 에서 다시 세우고 있다 |
| [`6_secret_scan.md`](6_secret_scan.md) · [`8_gitleaks_config.md`](8_gitleaks_config.md) · [`12_gitleaks_local_and_release_checklist.md`](12_gitleaks_local_and_release_checklist.md) | 검사 방법은 아직 쓸모 있다. 다만 위의 "패턴 검사만으로는 안 된다" 를 함께 읽어라 |
