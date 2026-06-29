# 24. Public Conversion Secret Rotation And History Cleanup

- 작성 시각: 2026-03-19
- 상태: 초안
- 목적: 현재 private repo 를 public 으로 전환하기 전에 필요한 secret 재발급 범위, history rewrite 절차, 수동 검증 명령을 한 번에 정리한다.

## 결론

현재 repo 는 `public` 전환 자체는 가능하다. 다만 바로 전환하면 안 된다.

이번 로컬 확인에서 확실히 드러난 과거 노출은 `docker-compose.yml` 안의 MySQL 자격증명이다.

- `MYSQL_ROOT_PASSWORD`
- `MYSQL_PASSWORD`
- MySQL healthcheck 에 들어간 `-p...` 인자

따라서 최소한 아래 두 작업이 먼저다.

1. 운영 중인 DB 자격증명 교체
2. Git history 에서 해당 값이 포함된 과거 commit 제거

그 외 OAuth, AWS, OpenAI, Slack, Tour API 계열은 현재 이 repo 의 Git-tracked history 에서 실제 값이 확인되지는 않았다. 하지만 예전 수동 배포나 로컬 private 파일 커밋 가능성을 완전히 배제하지 못하면 함께 재발급하는 편이 안전하다.

## 이번 확인에서 나온 사실

### 1. 확실히 과거 history 에 있었던 값

- 파일: `docker-compose.yml`
- 최초 확인 commit: `45bd86c7ba43da3c605aa666fcd9b0efa785d80b`
- 노출된 항목:
  - `MYSQL_ROOT_PASSWORD: supersecret`
  - `MYSQL_PASSWORD: prod_pass`
  - `mysqladmin ping ... -pprod_pass`

즉, DB root 비밀번호와 앱 계정 비밀번호는 `유출된 것으로 간주`하는 것이 맞다.

### 2. 현재까지 확인되지 않은 항목

아래 파일이 Git 에 추적된 흔적은 이번 로컬 점검에서 찾지 못했다.

- `application-private.properties`
- `config/application-private.properties`
- `.env`
- `.env.prod`

또한 일반적인 토큰 패턴을 history 전체에서 찾았을 때 다음 종류의 실제 값은 검출되지 않았다.

- AWS access key 패턴
- GitHub personal access token 패턴
- Google API key 패턴
- OpenAI key 패턴
- Slack webhook URL 패턴

주의:

- 이 결과는 현재 로컬 환경에서 수행한 grep/패턴 기반 점검이다.
- `gitleaks`가 설치되어 있지 않아 entropy 기반 정밀 스캔은 아직 수행하지 못했다.

## 재발급 체크리스트

### A. 반드시 재발급

#### 1. MySQL root password

- GitHub Secret: `PROD_MYSQL_ROOT_PASSWORD`
- 영향:
  - MySQL root 계정 접근
  - compose / `.env` / 운영 DB 초기화 및 점검 절차
- 해야 할 일:
  - 운영 DB root 비밀번호 변경
  - GitHub Actions secret 갱신
  - 운영 서버 `.env` 갱신
  - 필요 시 비상 접속 문서/개인 메모 갱신

#### 2. MySQL app user password

- GitHub Secret: `PROD_MYSQL_PASSWORD`
- 연관 값:
  - `PROD_MYSQL_USER`
  - `PROD_MYSQL_DATABASE`
- 영향:
  - Spring datasource 접속
  - MySQL healthcheck
  - 운영 `.env`
  - `config/application-private.properties`
- 해야 할 일:
  - 운영 DB 사용자 비밀번호 변경
  - GitHub Actions secret 갱신
  - 운영 서버 `.env` 와 `config/application-private.properties` 갱신
  - 배포 후 애플리케이션 DB 연결 확인

### B. 조건부 재발급

아래는 이번 점검에서 Git history 유출이 확인되지는 않았다. 다만 과거 private 파일 커밋 가능성이나 외부 공유 가능성이 조금이라도 있으면 같이 교체하는 편이 안전하다.

#### 1. JWT

- `PROD_JWT_SECRET`
- 영향:
  - 기존 access/refresh token 무효화
- 교체 권장 상황:
  - 예전에 `application-private.properties` 를 개인 브랜치나 임시 repo 에 올린 적이 있는 경우

#### 2. OAuth client secrets

- `PROD_GOOGLE_CLIENT_SECRET`
- `PROD_KAKAO_CLIENT_SECRET`
- `PROD_NAVER_CLIENT_SECRET`
- 관련 client id:
  - `PROD_GOOGLE_CLIENT_ID`
  - `PROD_KAKAO_CLIENT_ID`
  - `PROD_NAVER_CLIENT_ID`
- 영향:
  - 소셜 로그인 연동

#### 3. Kakao / Tour API

- `PROD_KAKAO_REST_KEY`
- `PROD_TOUR_API_SECRET`

#### 4. AWS / S3 / CloudFront

- `PROD_AWS_ACCESS_KEY`
- `PROD_AWS_SECRET_KEY`
- 관련 비밀 아님:
  - `PROD_AWS_REGION`
  - `PROD_S3_BUCKET`
  - `PROD_CLOUDFRONT_DOMAIN`

#### 5. Slack / OpenAI

- `PROD_SLACK_WEBHOOK_URL`
- `PROD_OPENAI_API_KEY`
- 관련 비밀 아님:
  - `PROD_SLACK_CHANNEL`
  - `PROD_SLACK_BOT_NAME`
  - `PROD_OPENAI_MODEL`

### C. 비밀이 아니거나 우선순위 낮음

아래는 보통 재발급 대상은 아니다.

- `PROD_MYSQL_DATABASE`
- `PROD_MYSQL_USER`
- `PROD_GOOGLE_CLIENT_ID`
- `PROD_KAKAO_CLIENT_ID`
- `PROD_NAVER_CLIENT_ID`
- `PROD_AWS_REGION`
- `PROD_S3_BUCKET`
- `PROD_CLOUDFRONT_DOMAIN`
- `PROD_LLM_RECOMMENDER_BASE_URL`
- `PROD_APP_SECURITY_*`
- `PROD_SERVER_ERROR_*`
- `PROD_LOG_LEVEL_*`
- `PROD_OPENAI_MODEL`
- `PROD_SLACK_CHANNEL`
- `PROD_SLACK_BOT_NAME`

## 실제 진행 순서

### 1단계. 운영에서 사용 중인 현재 값 확정

확인 대상:

- GitHub Actions repository secrets
- 운영 서버 `.env`
- 운영 서버 `config/application-private.properties`
- DB 내부 사용자 목록과 권한

이 단계 목적은 "어떤 값이 실제 운영에 쓰이고 있는지"를 먼저 확정하는 것이다.

### 2단계. 새 secret 발급

최소 필수:

- 새 `PROD_MYSQL_ROOT_PASSWORD`
- 새 `PROD_MYSQL_PASSWORD`

조건부:

- JWT / OAuth / AWS / Slack / OpenAI / Tour / Kakao 계열 새 값

원칙:

- 새 값을 먼저 발급하고 저장한 뒤, old value 는 아직 폐기하지 않는다.

### 3단계. 운영 환경 반영

반영 위치:

- GitHub repository secrets
- 운영 서버 `.env`
- 운영 서버 `config/application-private.properties`
- MySQL 사용자 비밀번호

검증:

- `docker compose config`
- `docker compose up -d --build --no-deps app`
- `docker compose logs app`
- 실제 로그인 / DB 연결 / 파일 업로드 / 외부 API 호출 점검

### 4단계. old secret 폐기

새 값이 정상 동작하는 것이 확인된 뒤 아래를 폐기한다.

- 기존 DB root 비밀번호
- 기존 DB app 비밀번호
- 조건부로 교체한 기타 key / secret

### 5단계. Git history rewrite

이 단계부터는 협업자에게 반드시 공지해야 한다. commit hash 가 모두 바뀐다.

정리 대상 우선순위:

1. `docker-compose.yml` 과거 버전에 포함된 DB 자격증명
2. 공개하고 싶지 않은 운영 workflow 세부정보가 있으면 함께 정리
3. 혹시 추가로 발견된 민감 파일/문자열

### 6단계. force push 와 clone 재정리

- rewritten branch 를 `--force` push
- tags 도 쓰고 있다면 tags 재검토
- 협업자는 기존 clone 폐기 후 재클론

### 7단계. 최종 스캔 후 public 전환

최종 확인:

- 전체 history secret scan
- 현재 working tree secret scan
- GitHub repository visibility 변경

## Git History Rewrite 계획

## 원칙

- `git filter-repo` 사용 권장
- 기존 repo 를 바로 만지기 전에 mirror 또는 bare 백업 생성
- rewrite 후에는 원격 push 가 강제 갱신된다

## 추천 절차

### 0. 백업

```bash
git clone --mirror https://github.com/sanghyunbang/heat_trip_backend.git heat_trip_backend.backup.git
```

### 1. 작업용 clone 준비

```bash
git clone https://github.com/sanghyunbang/heat_trip_backend.git heat_trip_backend_rewrite
cd heat_trip_backend_rewrite
```

### 2. `git-filter-repo` 설치

예시:

```bash
pip install git-filter-repo
```

### 3. replacement rules 파일 작성

예시 `replacements.txt`:

```text
regex:MYSQL_ROOT_PASSWORD:\s*supersecret==>MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
regex:MYSQL_PASSWORD:\s*prod_pass==>MYSQL_PASSWORD: ${MYSQL_PASSWORD}
regex:mysqladmin ping -h localhost -uheattrip -pprod_pass \|\| exit 1==>mysqladmin ping -h localhost -u$$MYSQL_USER -p$$MYSQL_PASSWORD || exit 1
```

주의:

- 실제 old value 가 더 있었으면 모두 포함해야 한다.
- 문자열이 여러 변형으로 존재하면 각 변형을 추가한다.

### 4. rewrite 실행

```bash
git filter-repo --replace-text replacements.txt
```

필요하면 파일 자체 rewrite 도 추가한다.

### 5. rewrite 결과 검증

```bash
git log --all -S"supersecret" -- docker-compose.yml
git log --all -S"prod_pass" -- docker-compose.yml
git grep -I -n -E "(supersecret|prod_pass)" $(git rev-list --all)
```

결과가 비어야 한다.

### 6. force push

```bash
git remote -v
git push origin --force --all
git push origin --force --tags
```

### 7. 협업자 공지

공지 내용:

- history rewrite 완료
- 기존 clone 폐기 필요
- `git fetch && git reset --hard` 로 버티지 말고 재클론 권장

## 수동 검증 명령

아래 명령은 public 전환 직전에 다시 한 번 돌리는 용도다.

### 1. 민감 파일이 Git tracked 인지 확인

```bash
git log --all --full-history --name-status -- application-private.properties config/application-private.properties src/main/resources/application-private.properties .env .env.prod
git rev-list --all --objects | rg "(application-private\.properties|\.env|\.env\.prod)$"
```

### 2. 이미 알려진 DB 자격증명 재검사

```bash
git log --all -S"MYSQL_ROOT_PASSWORD: supersecret" -- docker-compose.yml
git grep -I -n -E "(supersecret|prod_pass)" $(git rev-list --all)
```

### 3. 일반적인 key/token 패턴 검사

```bash
git grep -I -n -E "(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[0-9A-Za-z\\-_]{20,}|ghp_[0-9A-Za-z]{20,}|github_pat_[0-9A-Za-z_]{20,}|sk-[A-Za-z0-9\\-_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|https://hooks\\.slack\\.com/services/[A-Za-z0-9/_-]+|ya29\\.[A-Za-z0-9\\-_]+)" $(git rev-list --all)
```

### 4. workflow 에서 실제 값 대신 secret 참조만 남았는지 확인

```bash
rg -n "secrets\\.[A-Z0-9_]+|PROD_[A-Z0-9_]+" .github/workflows -S
```

### 5. 현재 working tree 에 민감 파일이 없는지 확인

```bash
git status --short
rg -n "(MYSQL_ROOT_PASSWORD|MYSQL_PASSWORD|jwt\\.secret=|OPENAI_API_KEY=|SLACK_WEBHOOK_URL=|cloud\\.aws\\.credentials\\.secret-key=)" -g "!*.example" .
```

### 6. `gitleaks` 정밀 스캔

설치 후 권장:

```bash
gitleaks detect --source . --verbose
gitleaks git --verbose
```

## public 전환 직전 최종 체크

1. 운영에서 old DB 비밀번호가 더 이상 통하지 않는다.
2. GitHub Actions secrets, 서버 `.env`, `config/application-private.properties` 가 모두 새 값이다.
3. `supersecret`, `prod_pass` 가 Git history 어디에도 남아 있지 않다.
4. `application-private.properties`, `.env` 류 파일이 Git tracked 이력이 없다.
5. `gitleaks` 전체 history 스캔 결과가 비어 있거나 허용 가능한 false positive 만 남는다.
6. workflow 에 운영 절대경로나 불필요한 내부 정보가 남아 있지 않다.
7. 그 다음에만 repo visibility 를 `public` 으로 변경한다.

