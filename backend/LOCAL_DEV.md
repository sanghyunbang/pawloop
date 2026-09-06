# 로컬 개발 환경 (운영 api.heattrip.link 와 분리)

운영 서버를 건드리지 않고, 로컬에서 **backend(Spring)** 를 띄워 Flutter 앱을 거기에 붙이는 방법.
DB 는 호스트에서 이미 도는 MySQL(3306, `heat_trip_db`)을 그대로 쓴다.

> 2026-09-06 까지는 추천 서버(recsys · FastAPI · OpenAI 키)도 함께 띄웠다. 감정 추천을 #94 로 지워
> 이제 백엔드 하나다.

## 1. 변수 채우기
```bash
cd backend
cp .env.local.example .env.local   # DB 이름·계정
```
비밀값(OAuth·공공데이터 키·DB 비밀번호)은 `.env` 를 그대로 재사용한다(`docker-compose.local.yml` 의 `env_file`).

## 2. 기동 (도커)
```bash
docker compose --env-file .env.local -f docker-compose.local.yml up -d --build
# 상태: docker compose -f docker-compose.local.yml ps
# 로그: docker compose -f docker-compose.local.yml logs -f backend
```
- backend → http://localhost:8080, mysql → 호스트의 localhost:3306
- `SPRING_PROFILES_ACTIVE=dev`, `ddl-auto=update` → 엔티티로 스키마가 맞춰진다.

## 3. 데이터
장소 카탈로그는 부팅 예열이 공공데이터에서 직접 받아 온다(#279 · #291) — 서비스키가 `.env` 에 있어야 한다.
사용자·반려동물·산책은 앱에서 만든다. 운영 DB 덤프를 쓰려면 `mysql/init/` 에 넣고 최초 기동한다.

## 4. Flutter 연결
운영 대신 **로컬**로 붙여 실행:
```bash
cd ../app
flutter run --dart-define=API_BASE=http://10.0.2.2:8080
```
(`10.0.2.2` = 안드로이드 에뮬레이터에서 본 호스트 PC. 실기기는 PC LAN IP 사용.)

## 빠른 대안 (도커로 Spring 빌드가 느릴 때)
백엔드를 호스트에서 직접:
```bash
./gradlew bootRun --args='--spring.profiles.active=dev'   # JDK 21 필요
```
