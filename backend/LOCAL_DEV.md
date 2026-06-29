# 로컬 개발 환경 (운영 api.heattrip.link 와 분리)

운영 서버를 건드리지 않고, 로컬에서 **mysql + recsys(FastAPI) + backend(Spring)** 전체를 띄우고
Flutter 앱을 거기에 붙이는 방법.

## 1. 변수 채우기
```bash
cd heat_trip_backend
cp .env.local.example .env.local
# .env.local 에 OPENAI_API_KEY 입력 (추천 LLM에 필요)
```

## 2. 스택 기동 (도커)
```bash
docker compose --env-file .env.local -f docker-compose.local.yml up -d --build
# 상태: docker compose -f docker-compose.local.yml ps
# 로그: docker compose -f docker-compose.local.yml logs -f backend
```
- backend → http://localhost:8080, recsys → http://localhost:8000, mysql → localhost:3306
- `SPRING_PROFILES_ACTIVE=dev`, `ddl-auto=update` → 엔티티로 스키마 자동 생성.

## 3. 데이터
로컬 MySQL은 **비어 있음**(피드/추천 후보가 안 보임). 둘 중 하나:
- 운영 DB 덤프(.sql)를 `mysql/init/` 에 넣고 최초 기동 → 자동 시드, 또는
- 기동 후 수동 import: `docker exec -i heattrip-mysql-local mysql -uroot -p$MYSQL_ROOT_PASSWORD heat_trip_db < dump.sql`

시드 후 감정 데이터 배치(선택):
```bash
curl -X POST "http://localhost:8080/api/curation/admin/seed-emotions?overwrite=false"
curl -X POST "http://localhost:8080/api/curation/admin/aggregate-ugc-emotions"
```

## 4. Flutter 연결
운영(.env의 API_BASE_URL) 대신 **로컬**로 붙여 실행:
```bash
cd heat_trip_flutter
flutter run --dart-define=API_BASE=http://10.0.2.2:8080
```
(`10.0.2.2` = 안드로이드 에뮬레이터에서 본 호스트 PC. 실기기는 PC LAN IP 사용.)

## 빠른 대안 (도커로 Spring 빌드가 느릴 때)
mysql/recsys만 도커로, 백엔드는 호스트에서 직접:
```bash
docker compose --env-file .env.local -f docker-compose.local.yml up -d mysql recsys
./gradlew bootRun --args='--spring.profiles.active=dev'   # JDK 21 필요
```

## 필요한 자격증명 (당신만 가진 것)
- `OPENAI_API_KEY` — 추천 LLM. 없으면 recommend가 500.
- 운영 DB 덤프(또는 staging DB 접속정보) — 로컬 데이터.
