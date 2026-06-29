# 17. 운영 컴퓨터 확인 체크리스트

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료

## 먼저 답

지금은 운영 컴퓨터가 아니기 때문에, 실제 Cloudflare Tunnel 설정과 실제 Nginx 값을 내가 직접 확인할 수는 없다.

그래서 이 문서는 운영 컴퓨터에 가서 무엇을 확인해야 하는지 적어둔 문서다.

즉, `2번`은 지금 당장 "실제값 확정"은 못 하고,  
`운영 컴퓨터에서 확인해야 할 항목을 구조화`하는 식으로 진행한 것이다.

## 운영 컴퓨터에서 확인해야 할 항목

### Cloudflare / cloudflared

1. `cloudflared`가 설치되어 있는가
2. 서비스로 실행 중인가
3. 설정 파일 위치가 어디인가
4. `tunnel id`가 무엇인가
5. `hostname`이 무엇인가
6. cloudflared가 어떤 로컬 주소로 전달하는가

예:

- `http://127.0.0.1:80`
- `http://127.0.0.1:8080`

### Nginx

1. Nginx가 설치되어 있는가
2. 설정 파일 위치가 어디인가
3. 실제 listen 포트가 무엇인가
4. 실제 `server_name`이 무엇인가
5. 현재 upstream이 무엇을 가리키는가
6. access log / error log 위치가 어디인가

### Spring Boot 앱

1. 실제 앱 listen 포트가 무엇인가
2. 앱이 `127.0.0.1`에만 바인딩되는가
3. Docker인지, 직접 프로세스인지
4. `.env`와 `application-private.properties` 위치가 어디인가

## 운영 컴퓨터에서 확인 명령 예시

아래는 개념 예시다.

### cloudflared 확인

```powershell
Get-Process | Where-Object { $_.ProcessName -like "*cloudflared*" }
```

또는 서비스 확인

```powershell
Get-Service | Where-Object { $_.Name -like "*cloudflared*" }
```

### Nginx 확인

```powershell
Get-Process | Where-Object { $_.ProcessName -like "*nginx*" }
```

### 어떤 포트가 열려 있는지 확인

```powershell
Get-NetTCPConnection -State Listen | Sort-Object LocalPort
```

### Docker 컨테이너 확인

```powershell
docker ps
```

## 운영 컴퓨터에서 최종적으로 알아내야 하는 값

| 항목 | 예시 | 실제값 기입 |
|------|------|-------------|
| public 도메인 | `api.example.com` | |
| cloudflared ingress 대상 | `http://127.0.0.1:80` | |
| Nginx listen 포트 | `80` | |
| Spring Boot 포트 | `8080` | |
| Nginx 설정 파일 경로 | `/etc/nginx/conf.d/app.conf` | |
| cloudflared 설정 파일 경로 | `/etc/cloudflared/config.yml` | |

## 이 문서의 의미

지금 이 컴퓨터에서는 운영값을 알 수 없기 때문에,  
운영 컴퓨터에 가서 `무엇을 확인하면 되는지`를 정리한 것이다.

즉, `2번을 못 하는 것`이 아니라, `지금 환경에서는 확인 단계까지가 한계`라는 뜻이다.

## 2026-03-18 확인 결과

운영 Mac mini 실측 결과, 아래 항목은 이미 확인되었다.

| 항목 | 실제값 |
|------|--------|
| public 도메인 | `api.heattrip.link` |
| cloudflared ingress 대상 | `http://localhost:8080` |
| Nginx listen 포트 | 없음 |
| Spring Boot 포트 | host `127.0.0.1:8080`, container `0.0.0.0:8080` |
| Nginx 설정 파일 경로 | 없음 |
| cloudflared 설정 파일 경로 | `/opt/homebrew/etc/cloudflared/config.yml` |

세부 근거는 [20_mac_mini_actual_state_2026_03_18.md](20_mac_mini_actual_state_2026_03_18.md) 를 본다.
