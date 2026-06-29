# 15. Public 전환 및 운영 런북

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료

## 목적

새 public 저장소를 실제 운영 기준 저장소로 만들기 직전에, 무엇을 어떤 순서로 해야 하는지 실전용으로 정리한다.

## 전환 목표

- 새 저장소를 public으로 연다
- 실제 secret은 저장소에 두지 않는다
- 현재 구조를 기준으로 public 전환을 먼저 마무리한다
- Nginx 도입은 후속 TODO로 분리한다
- 최소한의 보안 자동화와 rate limit을 갖춘다

## 현재 운영 구조

2026-03-18 실측 기준 현재 운영은 아래 구조다.

```text
사용자
 -> Cloudflare
 -> cloudflared
 -> localhost:8080
 -> Spring Boot Docker 컨테이너
```

즉, Nginx는 아직 없다.

관련 실측 문서:

- [20_mac_mini_actual_state_2026_03_18.md](20_mac_mini_actual_state_2026_03_18.md)

## 실행 순서

### 1. 현재 private 저장소에서 최종 정리

확인할 것:

- `.env` 미커밋
- `application-private.properties` 미커밋
- `config/` 미커밋
- `docker-compose.yml` 평문 비밀번호 없음
- workflow에 운영 절대경로 없음

### 2. 로컬 secret scan

- `gitleaks detect --source .`
- 필요하면 `gitleaks git .`

### 3. 새 public 저장소 생성

권장:

- 기존 private 저장소를 그대로 public 전환하지 않고
- 새 public 저장소를 새로 만들어 정리된 파일만 올림

### 4. 예시 설정 파일 확인

반드시 있어야 할 파일:

- `.env.example`
- `application-private.properties.example`

### 5. 문서 확인

반드시 읽을 문서:

- [0_plan.md](0_plan.md)
- [5_current_status.md](5_current_status.md)
- [12_gitleaks_local_and_release_checklist.md](12_gitleaks_local_and_release_checklist.md)
- [14_cloudflare_tunnel_and_nginx_practical_guide.md](14_cloudflare_tunnel_and_nginx_practical_guide.md)
- [22_cicd_option_review.md](22_cicd_option_review.md)
- [23_backend_and_recommender_cicd_design.md](23_backend_and_recommender_cicd_design.md)

### 6. Mac mini 운영 구성

준비할 것:

- `.env`
- `config/application-private.properties`
- cloudflared 설정
- 운영 compose secret 정리
- recommender host port 제거 또는 loopback 제한

TODO:

- Nginx 설정은 public 전환 이후 단계에서 도입 검토

### 7. 앞단 연결

- Cloudflare 도메인
- Tunnel
- Spring Boot local port

순서대로 연결 테스트

### 8. 보안 점검

- Swagger 기본 비공개
- 로그인/추천/업로드 rate limit 확인
- CORS origin 확인
- 업로드 body size 확인

### 9. 최종 공개

- 새 저장소 public
- GitHub Actions secret scan 확인
- README 최종 점검

## 운영 직후 확인 항목

1. 도메인 접속 정상 여부
2. 로그인 정상 여부
3. 추천 API 정상 여부
4. 업로드 정상 여부
5. 429 동작 여부
6. 로그에 민감정보가 안 찍히는지 확인

## 이 런북의 핵심

public 전환은 "코드 공개"만의 문제가 아니다.

실제로는:

- secret 분리
- 배포 구조 정리
- 앞단 프록시 구성
- 최소 보안 자동화

를 같이 맞춰야 한다.

## 결론

지금 저장소는 public 운영형으로 가기 위한 기반 정리 단계까지는 왔다.

이제 실제 운영 관점에서는:

- 운영 compose secret 분리
- recommender `*:8000` 노출 제거
- Cloudflare Tunnel 실제 값 반영 문서화
- 새 public 저장소 생성

이 세 단계가 다음 핵심이다.
