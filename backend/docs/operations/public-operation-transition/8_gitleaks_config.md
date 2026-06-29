# 8. gitleaks 설정 파일 추가

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료

## gitleaks가 정확히 뭔가

`gitleaks`는 저장소 안에서 비밀값처럼 보이는 문자열을 찾아내는 도구다.

쉽게 말하면 이런 걸 잡는 역할이다.

- API key
- access token
- webhook URL
- 비밀번호
- private key
- OAuth secret

즉, 사람이 실수로 코드를 커밋했을 때:

- `application.properties`에 secret을 넣어버리거나
- `.env`를 올려버리거나
- 테스트용 key를 코드에 박아 넣은 채 push하는 실수

를 잡아주는 보안 검사 도구다.

## 왜 굳이 설정 파일이 필요한가

`gitleaks` 기본 규칙만 써도 많이 잡는다.  
하지만 public 저장소로 운영하다 보면 아래 문제가 생긴다.

- 예시 설정 파일의 `change-me-secret-key` 같은 값도 의심 대상으로 볼 수 있다.
- 문서에 `example.com`, `localhost`, `change-me` 같은 설명용 값이 반복된다.
- 이런 것까지 전부 경고로 뜨면 오탐이 많아져서 CI가 시끄러워진다.

그래서 `이건 실제 secret이 아니라 예시값이다` 라는 범위를 일부 알려주는 설정 파일이 필요하다.

## 이번에 어떻게 했나

루트에 [.gitleaks.toml](/C:/Users/mm206/git_projects/heat_trip_backend/.gitleaks.toml) 파일을 추가했다.

이 파일은 공식 문서 기준으로 아래 방식으로 동작한다.

1. gitleaks 기본 내장 규칙을 그대로 사용한다.
2. 그 위에 프로젝트 전용 allowlist를 얹는다.

즉, 기본 탐지력은 유지하고 오탐만 줄이는 방식이다.

## 이번 설정의 핵심

### 1. 기본 규칙 확장

`[extend] useDefault = true`

의미:

- gitleaks 기본 내장 룰셋을 그대로 가져다 쓴다.
- 우리가 별도로 모든 탐지 규칙을 다시 만들지 않는다.

이게 가장 안전한 시작점이다.

### 2. 예시 설정 파일 allowlist

이번에는 아래 파일을 allowlist에 넣었다.

- `.env.example`
- `application-private.properties.example`

이유:

- 여기는 원래 placeholder를 적는 자리다.
- `change-me-root-password`
- `change-me-jwt-secret-with-enough-length`

같은 값이 있어도 실제 유출로 보면 안 된다.

### 3. 문서용 placeholder allowlist

예시 문서와 설정에서 자주 나오는 placeholder도 일부 허용했다.

예:

- `change-me`
- `example.com`
- `localhost`
- `127.0.0.1`

이건 실제 운영 비밀값이 아니라 설명용 문자열이라서 오탐을 줄이기 위해 넣었다.

## 중요한 주의사항

allowlist는 너무 넓게 잡으면 안 된다.

예를 들어:

- 문서 전체 폴더를 통째로 무시
- `secret`, `password`, `token` 같은 단어를 전부 무시

이런 식이면 진짜 유출도 못 잡는다.

그래서 이번 설정은 아주 좁게 잡았다.

- 예시 설정 파일만 경로로 허용
- 정말 설명용으로만 반복되는 placeholder만 허용

## 이 파일이 언제 사용되나

공식 문서 기준으로 gitleaks는 루트의 `.gitleaks.toml`을 자동으로 읽을 수 있다.

즉, 이번에 추가한 GitHub Actions workflow의 `gitleaks` 실행 시에도 적용된다.

## 앞으로 더 할 수 있는 것

필요하면 나중에 추가할 수 있다.

- 특정 테스트 fixture 파일만 허용
- 특정 false positive rule만 비활성화
- 특정 커밋 해시만 예외 처리

하지만 초반에는 지금처럼 좁고 단순하게 두는 것이 좋다.

## 요약

- gitleaks는 저장소 안의 secret 유출을 잡는 도구다.
- `.gitleaks.toml`은 오탐을 줄이기 위한 프로젝트별 설정 파일이다.
- 이번 설정은 기본 탐지는 유지하고, 예시 파일과 placeholder만 좁게 허용한다.
