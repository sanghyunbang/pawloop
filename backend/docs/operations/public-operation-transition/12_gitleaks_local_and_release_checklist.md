# 12. gitleaks 로컬 실행 및 public 전환 직전 체크리스트

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료

## 이 문서의 목적

public 저장소를 만들기 직전에 무엇을 확인해야 하는지, 그리고 `gitleaks`를 로컬에서 어떻게 돌리는지 정리한다.

## 왜 로컬에서도 실행하나

GitHub Actions에서 secret scan을 해도 좋지만, push 전에 내 컴퓨터에서 한 번 확인하면 더 빠르다.

장점:

- PR 올리기 전에 바로 확인 가능
- 실수 수정 속도가 빠름
- public 전환 직전 마지막 점검 가능

## gitleaks 로컬 실행 개념

`gitleaks`는 로컬 저장소를 스캔해서 secret 패턴을 찾는다.

보통 두 방식이 있다.

### 1. 현재 작업 트리 스캔

지금 내 파일 상태를 검사

### 2. git 이력 전체 스캔

과거 커밋까지 검사

public 저장소를 새로 만들기 직전에는 2번이 특히 중요하다.

## 설치 방법 개념

OS마다 다르지만 보통:

- 직접 바이너리 설치
- 패키지 매니저 설치
- Docker로 실행

실무적으로는 로컬에 설치하거나 CI에 맡기는 방식 둘 다 쓴다.

## 로컬 실행 예시 개념

### 작업 트리 검사

```bash
gitleaks detect --source .
```

### git 이력 검사

```bash
gitleaks git .
```

### 설정 파일을 명시하는 경우

```bash
gitleaks detect --source . --config .gitleaks.toml
```

## public 전환 직전 체크리스트

### 1. secret 파일 점검

- `.env`
- `application-private.properties`
- `config/`

이런 파일이 커밋되지 않았는지 확인

### 2. 예시 파일만 남았는지 확인

- `.env.example`
- `application-private.properties.example`

실제 값이 아닌 placeholder만 있는지 확인

### 3. compose 점검

- `docker-compose.yml`에 평문 비밀번호 없는지 확인
- 운영 주소, 내부 IP, 민감한 host 정보 없는지 확인

### 4. workflow 점검

- self-hosted runner 절대경로 없는지 확인
- 실제 운영 secret이 workflow에 없는지 확인

### 5. 문서 점검

- README에 실제 운영값이 적혀 있지 않은지 확인
- 샘플 도메인만 들어 있는지 확인

### 6. 앱 설정 점검

- `application.properties`에 실제 key가 없는지 확인
- debug/stacktrace 기본값이 과하지 않은지 확인

### 7. git 이력 점검

- `gitleaks git .` 또는 비슷한 방식으로 과거 이력까지 검사

### 8. 새 public 저장소로 옮길 때 최종 확인

- private 저장소를 그대로 public 전환하지 말고
- 정리된 파일만 새 저장소로 옮기는 방식이 더 안전한지 다시 확인

## 추천 순서

1. 로컬 작업 트리 검사
2. CI secret scan 확인
3. git 이력 검사
4. 새 public 저장소 생성
5. 마지막 수동 확인 후 공개

## 이 문서의 결론

- `gitleaks`는 CI에서만 돌리는 도구가 아니라 로컬에서도 유용하다.
- public 전환 직전에는 현재 파일뿐 아니라 과거 이력까지 검사하는 것이 좋다.
- 예시 파일과 실제 secret 파일을 엄격히 분리해야 한다.
