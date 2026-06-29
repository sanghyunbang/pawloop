# 18. 새 public 저장소 오픈 직전 최종 체크리스트

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료

## 목적

새 public 저장소를 열기 직전, 실무적으로 마지막 점검에 쓸 체크리스트다.

## 1. 저장소 파일 점검

- `.env`가 커밋되지 않았다
- `application-private.properties`가 커밋되지 않았다
- `config/`가 커밋되지 않았다
- `docker-compose.yml`에 평문 비밀번호가 없다
- 운영용 compose 에서도 평문 비밀번호를 제거했다
- workflow에 실제 경로나 실제 credential이 없다

## 2. 예시 설정 점검

- `.env.example`만 public에 있다
- `application-private.properties.example`만 public에 있다
- 예시 파일에는 `change-me` 같은 placeholder만 있다

## 3. secret scan 점검

- GitHub Actions `secret-scan.yml`이 존재한다
- `.gitleaks.toml`이 존재한다
- 로컬에서 `gitleaks detect --source .` 수행
- 가능하면 `gitleaks git .` 수행

## 4. 보안 설정 점검

- `/api/curation/**`가 인증 필요
- `/public/**`가 인증 필요
- Swagger 기본 비공개
- 에러 상세 기본 비노출
- DEBUG 로그 기본 비활성

## 5. rate limit 점검

- 앱 레벨 rate limit 동작
- 로그인 제한 확인
- 추천 제한 확인
- 업로드 제한 확인
- 검색 제한 확인

## 6. 운영 구조 점검

- Cloudflare 구조 이해 완료
- 현재 실운영은 `cloudflared -> backend direct` 구조임을 확인
- Nginx는 현재 미도입이며 TODO로 관리
- cloudflared 실제 값은 운영 컴퓨터에서 확인 완료
- 운영 구조 증적 문서가 최신 상태다
- recommender 가 host 전체 인터페이스에 노출되지 않는다

## 7. 문서 점검

- README 최신화
- `docs/operations/public-operation-transition` 계획 문서 최신화
- public 운영 구조 설명 문서 최신화

## 8. 최종 권장 순서

1. 현재 private 저장소에서 최종 정리
2. local `gitleaks` 실행
3. 새 public 저장소 생성
4. 정리된 파일만 푸시
5. GitHub Actions secret scan 확인
6. 운영 컴퓨터에서 Nginx / cloudflared 실제값 반영

현재는 아래 순서가 더 현실적이다.

1. 현재 private 저장소에서 최종 정리
2. local `gitleaks` 실행
3. 운영 compose 에서 secret 분리
4. recommender 외부 바인딩 정리
5. 새 public 저장소 생성
6. 정리된 파일만 푸시
7. GitHub Actions secret scan 확인
8. Nginx 도입은 후속 단계로 진행

## 결론

이 체크리스트를 통과하면 "공개는 했는데 secret이 남아 있었다" 같은 기본 실수를 크게 줄일 수 있다.
