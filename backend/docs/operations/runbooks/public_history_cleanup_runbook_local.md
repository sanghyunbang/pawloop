# Public History Cleanup Runbook (Local Only)

이 문서는 로컬에서만 유지한다.
`documents/` 는 `.gitignore` 에 들어가 있으므로 Git 추적 대상이 아니다.

## 목표

- `documents/` 전체를 Git 현재 브랜치와 과거 히스토리에서 제거
- `replacements.txt` 를 로컬 전용으로 유지
- public 전환 전 추가 위험 요소를 마지막으로 점검

## 이미 반영된 상태

- `.gitignore` 에 `documents/` 추가
- `.gitignore` 에 `replacements.txt` 추가
- `git rm --cached -r documents`
- `git rm --cached replacements.txt`

즉, 다음 커밋부터는 `documents/` 와 `replacements.txt` 가 새 커밋에 포함되지 않는다.
하지만 과거 히스토리에는 아직 남아 있다.

## 추천 방식

`git filter-repo` 로 히스토리를 rewrite 한다.

## 0. 사전 확인

```bash
git status --short
git log --oneline --all -- documents
git log --oneline --all -- replacements.txt
```

## 1. 백업

별도 위치에 mirror 백업을 만든다.

```bash
git clone --mirror https://github.com/sanghyunbang/heat_trip_backend.git heat_trip_backend.backup.git
```

## 2. rewrite 작업용 clone

기존 작업 디렉터리에서 바로 하기보다 별도 clone 에서 수행하는 편이 안전하다.

```bash
git clone https://github.com/sanghyunbang/heat_trip_backend.git heat_trip_backend_rewrite
cd heat_trip_backend_rewrite
```

## 3. git-filter-repo 설치

```bash
pip install git-filter-repo
```

설치 확인:

```bash
git filter-repo --help
```

## 4. documents 와 replacements.txt 를 히스토리에서 제거

```bash
git filter-repo --path documents --path replacements.txt --invert-paths
```

의미:

- `documents/` 전체 삭제
- `replacements.txt` 삭제
- 모든 커밋에서 위 경로를 제거한 새 히스토리 생성

## 5. 추가 문자열 검증

기존에 확인된 DB 문자열이 히스토리에 남아 있지 않은지 확인한다.

```bash
git log --all -S"supersecret" -- docker-compose.yml
git log --all -S"prod_pass" -- docker-compose.yml
git grep -I -n -E "(supersecret|prod_pass)" $(git rev-list --all)
```

결과가 비어야 한다.

## 6. 문서 흔적 검증

```bash
git log --all -- documents
git log --all -- replacements.txt
git rev-list --all --objects | rg "documents/|replacements.txt"
```

결과가 비어야 한다.

## 7. 공개 전 추가 grep

```bash
git grep -I -n -E "(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[0-9A-Za-z\\-_]{20,}|ghp_[0-9A-Za-z]{20,}|github_pat_[0-9A-Za-z_]{20,}|sk-[A-Za-z0-9\\-_]{20,}|https://hooks\\.slack\\.com/services/[A-Za-z0-9/_-]+|jwt\\.secret=|cloud\\.aws\\.credentials\\.secret-key=|TOUR\\.API\\.SECRET=)" $(git rev-list --all)
```

## 8. push

주의: force push 이므로 협업자와 먼저 합의한다.

```bash
git remote -v
git push origin --force --all
git push origin --force --tags
```

## 9. 공지

rewrite 후에는 commit hash 가 바뀌므로 기존 clone 은 재클론 권장이다.

권장 공지 문구:

```text
Git history was rewritten to remove internal-only documents and cleanup artifacts before public conversion.
Please re-clone the repository instead of rebasing or resetting an old clone.
```

## public 전환 전 추가 위험 요소

### 1. self-hosted workflow 노출

현재 다음 workflow 가 self-hosted 실행 구조를 드러낸다.

- `.github/workflows/deploy-backend.yml`
- `.github/workflows/smoke.yml`

키 자체는 노출하지 않더라도 아래 정보는 공개 저장소에서 운영 단서가 된다.

- self-hosted runner 사용 여부
- 배포 구조가 GitHub Actions 기반임
- secret 을 `.env` 와 `config/application-private.properties` 로 렌더링한다는 운영 방식

권장:

- public 전환 전 `deploy-backend.yml` 은 private ops repo 로 분리하거나
- 최소한 manual dispatch 전용으로 두고 운영 디테일을 더 줄인다
- `smoke.yml` 도 public 에 꼭 필요 없으면 제거 또는 GitHub-hosted 테스트로 전환

### 2. README 내부문서 링크

README 에 `documents/` 경로와 로컬 절대경로 링크가 남아 있으면 public 에서 부자연스럽다.

권장:

- `documents/` 관련 링크 제거
- 절대경로 링크를 상대경로 또는 코드 표기로 변경

### 3. replacements.txt 자체 민감

현재 `replacements.txt` 에 과거 secret 문자열이 들어 있다.
이미 `.gitignore` 처리했지만 히스토리에서도 반드시 제거해야 한다.

### 4. secret rotation

이번 로컬 확인 기준으로 강하게 의심되거나 이미 문서에 정리된 회전 대상:

- DB root password
- DB app password

조건부 회전 권장:

- JWT secret
- OAuth client secret
- Kakao/Tour API key
- AWS access key / secret key
- Slack webhook
- OpenAI API key

## 최종 체크리스트

1. `git status --short` 에 `documents/` 가 untracked 또는 ignored 상태인지 확인
2. `git log --all -- documents` 결과가 비는지 확인
3. `git log --all -- replacements.txt` 결과가 비는지 확인
4. `deploy-backend.yml`, `smoke.yml` 공개 여부 최종 결정
5. README 내부문서 링크 정리
6. `gitleaks detect --source .`
7. `gitleaks git`
8. secret rotation 완료 확인
9. 그 다음에만 repository visibility 를 public 으로 전환
