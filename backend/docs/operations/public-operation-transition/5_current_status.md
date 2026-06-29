# 5. 현재 상태

- 작성 시각: 2026-03-18 00:54:24 +09:00

## 이번 단계에서 실제 반영한 항목

- DB 평문 비밀번호 제거
- `.env.example` 추가
- `application-private.properties.example` 추가
- 공개 운영용 `application.properties` 기본값 정리
- self-hosted 배포 workflow 절대경로 제거
- `SecurityConfig` 공개 범위 축소
- `.gitignore`, `.dockerignore`에 secret 파일 패턴 강화
- GitHub Actions `gitleaks` secret scan 추가
- 앱 레벨 rate limit filter 추가
- `.gitleaks.toml` 프로젝트 설정 파일 추가
- gateway / Cloudflare / Nginx rate limit 개념 문서 추가
- Nginx rate limit 샘플 설정 파일 추가
- gitleaks 로컬 실행 및 public 전환 직전 체크리스트 추가
- Cloudflare + Nginx + Mac mini 구조 설명 문서 추가
- Cloudflare Tunnel + Nginx 실전 가이드 추가
- public 전환 및 운영 런북 추가
- 실사용 Nginx 설정 템플릿 추가
- 운영 컴퓨터 확인 체크리스트 추가
- 새 public 저장소 오픈 직전 최종 체크리스트 추가
- Mac mini에서 바로 실행할 명령어 체크리스트 추가
- 세션 인계용 handoff 문서 추가
- 운영 Mac mini 실측 결과 문서 추가
- 운영 secret 분리 / recommender hardening 문서 추가
- CI/CD 선택지 검토 문서 추가
- backend / recommender CI/CD 설계 문서 추가

## 현재 기준 완료 상태

- 1단계 DB 정리: 완료
- 2단계 예시 설정 파일 추가: 완료
- 3단계 배포 workflow 정리: 완료
- 4단계 Security 범위 재설계: 완료
- 6단계 secret scan 추가: 완료
- 7단계 rate limit 추가: 완료
- 8단계 gitleaks 설정 파일 추가: 완료
- 9단계 gateway rate limit 가이드 문서화: 완료
- 10단계 다음 rate limit 계획 정리: 완료
- 11단계 Nginx rate limit 샘플 추가: 완료
- 12단계 gitleaks 로컬 체크리스트 추가: 완료
- 13단계 Cloudflare + Nginx 구조 설명 추가: 완료
- 14단계 Cloudflare Tunnel + Nginx 실전 가이드 추가: 완료
- 15단계 public 전환 런북 추가: 완료
- 16단계 실사용 Nginx 설정 템플릿 추가: 완료
- 17단계 운영 컴퓨터 확인 체크리스트 추가: 완료
- 18단계 public 오픈 직전 체크리스트 추가: 완료
- 19단계 Mac mini 확인 명령어 체크리스트 추가: 완료
- 20단계 Mac mini 실운영 확인 결과 정리: 완료
- 21단계 운영 secret 분리 및 recommender 노출 정리: 완료
- 22단계 CI/CD 및 설정 관리 선택지 검토: 완료
- 23단계 backend / recommender CI/CD 설계서: 완료
- 99단계 세션 handoff 문서 추가: 완료

## 아직 남은 권장 작업

1. `PublicSecurityAssessment.md`를 현재 수정 기준으로 한 번 더 갱신
2. 운영 compose 에 남은 secret 분리
3. `recommender` 외부 바인딩 제거 여부 확정
4. MySQL healthcheck 불일치 수정
5. Nginx 도입 여부를 후속 단계로 별도 결정
6. gateway 또는 WAF 레벨 rate limit 실제 도입
7. 필요 시 Redis 기반 분산 rate limit로 확장
8. backend 저장소 배포 workflow 를 secret 생성형으로 전환
9. recommender 저장소용 배포 workflow 설계 반영

## 2026-03-18 운영 실측 반영

운영 Mac mini 확인 결과, 현재 실제 운영 구조는 권장안인 `Cloudflare -> cloudflared -> Nginx -> Spring Boot` 가 아니라 아래와 같다.

```text
Cloudflare -> cloudflared -> Spring Boot(Docker, localhost:8080)
```

확정된 사실:

- public domain: `api.heattrip.link`
- cloudflared target: `http://localhost:8080`
- Nginx: 미설치, 미사용
- backend: `127.0.0.1:8080` 바인딩
- mysql: `127.0.0.1:3306` 바인딩
- recommender: `*:8000` 바인딩

세부 명령과 결과는 [20_mac_mini_actual_state_2026_03_18.md](20_mac_mini_actual_state_2026_03_18.md) 에 정리했다.

추가로, CI/CD 및 설정 관리 방식은 아래 문서에서 정리했다.

- [22_cicd_option_review.md](22_cicd_option_review.md)
- [23_backend_and_recommender_cicd_design.md](23_backend_and_recommender_cicd_design.md)

## 참고 문서

- [PublicTransitionPlan.md](../PublicTransitionPlan.md)
- [PublicRepoFilePolicy.md](../policy/PublicRepoFilePolicy.md)
- [PublicSecurityAssessment.md](../security/PublicSecurityAssessment.md)
