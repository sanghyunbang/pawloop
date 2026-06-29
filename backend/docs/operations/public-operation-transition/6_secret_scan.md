# 6. Secret Scan 추가

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료

## 이게 뭔가

secret scan은 저장소 안에 비밀값이 실수로 커밋되지 않았는지 자동으로 검사하는 절차다.

예를 들면 아래 같은 값이 커밋되면 안 된다.

- AWS access key
- Slack webhook URL
- OpenAI API key
- DB 비밀번호
- OAuth client secret

public 저장소로 운영하려면 이 검사가 거의 필수다.

## 왜 필요한가

사람은 실수한다.  
`.env`를 잘못 올리거나, 테스트하다가 API key를 코드에 박고 커밋할 수 있다.

secret scan은 이런 실수를 PR 또는 push 단계에서 잡아준다.

즉, 이건 서버 트래픽 보호가 아니라 `저장소 유출 방지 장치`다.

## 이번에 어떻게 붙였나

GitHub Actions workflow로 `gitleaks`를 추가했다.

추가 파일:

- [.github/workflows/secret-scan.yml](/C:/Users/mm206/git_projects/heat_trip_backend/.github/workflows/secret-scan.yml)

동작 시점:

- Pull Request
- `main` 브랜치 push
- 수동 실행

## 기대 효과

- secret이 실수로 커밋되면 CI에서 바로 실패시킬 수 있다.
- public 저장소 운영 시 가장 기본적인 안전장치 역할을 한다.

## 주의사항

- secret scan이 있다고 해서 100% 다 잡는 건 아니다.
- 예시값과 실제값을 잘 구분해서 문서와 설정 파일을 유지해야 한다.
- 새 public 저장소를 만들 때도 한 번 수동으로 전체 스캔하는 것이 좋다.
