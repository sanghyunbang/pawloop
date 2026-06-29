# 19. Mac mini 확인 명령어 체크리스트

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료
- 목적: 운영 Mac mini에서 Cloudflare, cloudflared, Nginx, Spring Boot, Docker 상태를 직접 확인하기 위한 명령어 모음

## 이 문서의 사용 방법

이 문서는 운영 Mac mini에서 직접 실행하는 체크리스트다.

즉, 지금 이 컴퓨터에서는 실행하지 않고,  
실제 Mac mini 터미널에서 한 줄씩 실행해서 결과를 확인하면 된다.

가능하면 결과를 복사해서 아래 문서에 반영하면 좋다.

- [17_operating_machine_discovery_checklist.md](17_operating_machine_discovery_checklist.md)
- [16_real_nginx_config_template.md](16_real_nginx_config_template.md)

## 1. cloudflared 확인

### 실행 중인지 확인

```bash
ps aux | grep cloudflared
```

확인할 것:

- cloudflared 프로세스가 있는지
- 어떤 옵션으로 실행되는지

### launchd 서비스인지 확인

```bash
launchctl list | grep cloudflared
```

확인할 것:

- 서비스 등록 여부

### 설정 파일 위치 찾기

```bash
find /usr/local/etc /opt/homebrew/etc ~/.cloudflared /etc -name "config.yml" 2>/dev/null
```

확인할 것:

- 실제 cloudflared 설정 파일 경로

### tunnel 관련 파일 찾기

```bash
find ~/.cloudflared /etc/cloudflared /usr/local/etc/cloudflared /opt/homebrew/etc/cloudflared -type f 2>/dev/null
```

확인할 것:

- tunnel id가 들어간 json 파일
- credentials file 경로

## 2. Nginx 확인

### Nginx 프로세스 확인

```bash
ps aux | grep nginx
```

### Nginx 설치 위치 확인

```bash
which nginx
```

### Nginx 버전 확인

```bash
nginx -v
```

### 실제 설정 파일 경로 확인

```bash
nginx -T
```

확인할 것:

- `server_name`
- `listen`
- `proxy_pass`
- `limit_req_zone`
- `limit_req`
- `client_max_body_size`
- `access_log`
- `error_log`

주의:

- `nginx -T` 출력이 길다.
- 전체를 파일로 저장해두는 것도 좋다.

예:

```bash
nginx -T > ~/nginx-full-config.txt 2>&1
```

## 3. 어떤 포트가 실제로 열려 있는지 확인

```bash
lsof -i -P -n | grep LISTEN
```

확인할 것:

- Nginx가 어떤 포트에 listen 중인지
- Spring Boot가 어떤 포트에 listen 중인지
- cloudflared가 어떤 연결을 유지하는지

## 4. Docker 사용 여부 확인

### 컨테이너 목록

```bash
docker ps
```

### compose 실행 경로 후보 찾기

```bash
find ~ -name "docker-compose.yml" -o -name "compose.yml" 2>/dev/null
```

확인할 것:

- 실제 운영 compose 파일 위치
- 컨테이너 이름
- 앱/DB가 컨테이너인지 여부

## 5. 앱 프로세스 직접 실행 여부 확인

```bash
ps aux | grep java
```

확인할 것:

- jar 직접 실행인지
- 어떤 포트 설정으로 뜨는지
- 어떤 경로에서 실행되는지

## 6. 환경 파일 위치 확인

### .env 후보 찾기

```bash
find ~ -name ".env" 2>/dev/null
```

### private properties 후보 찾기

```bash
find ~ -name "application-private.properties" 2>/dev/null
```

### config 디렉터리 후보 찾기

```bash
find ~ -type d -name "config" 2>/dev/null
```

확인할 것:

- 실제 운영 `.env`
- 실제 `application-private.properties`
- Docker mount 대상 경로

## 7. Cloudflare Tunnel이 어디로 보내는지 확인

cloudflared 설정 파일을 찾았다면 그 안에서 아래를 본다.

- `hostname`
- `service`

예를 들면:

- `hostname: api.example.com`
- `service: http://127.0.0.1:80`

이게 보이면 Cloudflare -> cloudflared -> Nginx 구조인지,
Cloudflare -> cloudflared -> Spring Boot 직결인지 구분할 수 있다.

## 8. Nginx가 어디로 보내는지 확인

`nginx -T` 결과에서 아래를 본다.

- `proxy_pass http://127.0.0.1:8080`
- 또는 upstream 블록

이걸 보면 Nginx -> Spring Boot 연결 구조를 확정할 수 있다.

## 9. 실제값 기록 표

운영 Mac mini에서 확인 후 아래 표를 채우면 된다.

| 항목 | 실제값 |
|------|--------|
| public domain | |
| cloudflared config path | |
| tunnel id | |
| cloudflared service target | |
| nginx config path | |
| nginx listen port | |
| nginx server_name | |
| nginx upstream target | |
| spring boot listen port | |
| docker compose path | |
| .env path | |
| application-private.properties path | |

## 10. 결과를 반영할 문서

확인한 값은 아래 문서에 반영하면 된다.

- [17_operating_machine_discovery_checklist.md](17_operating_machine_discovery_checklist.md)
- [16_real_nginx_config_template.md](16_real_nginx_config_template.md)
- [15_public_launch_runbook.md](15_public_launch_runbook.md)
- [20_mac_mini_actual_state_2026_03_18.md](20_mac_mini_actual_state_2026_03_18.md)

## 결론

운영 Mac mini에서 지금 당장 가장 중요한 건 세 가지다.

1. cloudflared가 어디로 보내는지
2. Nginx가 어디로 보내는지
3. Spring Boot가 어디에서 listen 중인지

이 세 가지만 확인해도 실운영 구조를 거의 확정할 수 있다.

## 2026-03-18 실행 결과 요약

이번 실제 확인으로 확정된 값:

- `cloudflared` 는 실행 중
- 실제 domain 은 `api.heattrip.link`
- 실제 target 은 `http://localhost:8080`
- Nginx 는 현재 없음
- backend 는 `127.0.0.1:8080`
- mysql 은 `127.0.0.1:3306`
- recommender 는 `*:8000`

즉 현재 운영 구조는 `Cloudflare -> cloudflared -> backend direct` 이다.
