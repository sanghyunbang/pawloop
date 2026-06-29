# 4. Security 범위 재설계

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료

## 목적

public 저장소 기반 운영을 전제로, 비용이 크거나 사용자 데이터와 연관된 경로의 공개 범위를 줄인다.

## 변경 내용

- `/api/curation/**`를 `permitAll`에서 `authenticated`로 변경
- `/public/**`를 `permitAll`에서 `authenticated`로 변경
- Swagger/OpenAPI 공개 여부를 `APP_SECURITY_DOCS_PUBLIC` 환경변수로 제어하도록 변경
- CORS 허용 origin을 코드 하드코딩 대신 `APP_SECURITY_ALLOWED_ORIGINS` 기반으로 변경

## 실제 수정 파일

- [src/main/java/com/heattrip/heat_trip_backend/config/SecurityConfig.java](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/java/com/heattrip/heat_trip_backend/config/SecurityConfig.java)
- [src/main/resources/application.properties](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/resources/application.properties)

## 의도

- 추천 API는 점수 계산과 외부 연동 비용이 발생할 수 있으므로 무인증 공개를 피한다.
- `/public/**`는 이름과 달리 사용자 스케줄 데이터이므로 Spring Security 레벨에서도 인증을 요구한다.
- Swagger는 개발 시에만 열고, 운영 기본값은 비공개로 둔다.

## 주의사항

- 프론트에서 비로그인 상태로 `curation`을 호출하고 있었다면 인증 흐름 수정이 필요하다.
- 운영에서 Swagger를 열려면 `APP_SECURITY_DOCS_PUBLIC=true`를 명시해야 한다.
