# prod backend

Pawloop 운영 서버. 이슈 #609 가 정본이고, 만든 뒤 반복해서 쓰는 명령은 #607 에 있습니다.

## staging 과 무엇이 다른가

| | staging | **prod** |
|:---|:---|:---|
| 방화벽 | 22·8080 을 내 IP 하나에만 | **443·80 을 세상에**, 22 는 내 IP |
| 주소 | 인스턴스를 교체할 때마다 바뀜 | **Elastic IP + `api.pawloop.app`** |
| HTTPS | 없음 | **Caddy 가 자동 발급** |
| DB | 서버와 같은 디스크 — 교체하면 사라짐 | **별도 EBS 볼륨** — 교체해도 남음 |
| 앱 포트 | 8080 을 밖에 | 루프백에만. 밖은 전부 Caddy 를 지남 |

## 만들어지는 것

```
        인터넷
          │ 443 · 80 (전 세계)
          ▼
   ┌──────────────────────────────────┐
   │ EC2 (Elastic IP)                 │
   │                                  │
   │  Caddy ── 인증서 자동 발급        │
   │    │  · X-Real-IP 주입            │
   │    │  · /actuator/* 차단          │
   │    ▼                             │
   │  백엔드 (127.0.0.1:8080)          │
   │    │                             │
   │    ▼                             │
   │  MySQL ─────────┐                │
   └─────────────────┼────────────────┘
                     ▼
              별도 EBS 볼륨 (/mnt/data)
              ← 인스턴스를 교체해도 남는다
```

Route 53 에 `api.pawloop.app` A 레코드도 함께 만듭니다. **인증서를 받으려면 이름이 먼저
이 서버를 가리켜야** 해서, 인스턴스가 그 레코드에 의존하게 해 뒀습니다.

## 처음 만들 때

```
cp terraform.tfvars.example terraform.tfvars   # 값을 채운다 (파일 안 주석 참고)
terraform init
terraform plan
terraform apply
```

SSM 에 두 값이 먼저 있어야 합니다 — 넣는 절차는 #600 에 있습니다.

| 이름 | 무엇 |
|:---|:---|
| `/pawloop/prod/backend/deploy-key` | 저장소 배포 키(개인키). 없으면 clone 이 안 된다 |
| `/pawloop/prod/backend/env` | 앱 `.env`. 없으면 앱이 안 뜬다 |

### ⚠️ `.env` 는 staging 것을 그대로 쓰지 않습니다

MySQL 비밀번호와 JWT 시크릿은 **prod 용으로 새로 만듭니다.** `APP_BASE_URL` 은
`https://api.pawloop.app` 입니다 — 소셜 로그인 리다이렉트가 이 값에서 만들어집니다.

`APP_PUBLISHED_HOST` 는 신경 쓰지 않아도 됩니다. 부팅 스크립트가 `127.0.0.1` 로 덮습니다.

## 고칠 때 — 무엇이 인스턴스를 교체하나

`plan` 에 이 줄이 보이면 **인스턴스가 통째로 새로 만들어집니다.**

```
# module.backend_host.aws_instance.this must be replaced
      ~ user_data = "..." -> "..." # forces replacement
```

부팅 스크립트(`user_data_backend.sh.tftpl`)나 모듈의 설치 스크립트를 고치면 그렇게 됩니다.
부팅 스크립트는 켜질 때 한 번만 도는 것이라 이미 켜진 서버에 다시 먹일 방법이 없습니다.

**DB 는 안전합니다** — 별도 볼륨이고, 새 인스턴스가 그것을 다시 붙입니다. 붙이는 코드는
이미 파일시스템이 있으면 **포맷하지 않습니다.**

다만 교체되는 동안 **서비스가 몇 분 멈춥니다.** Elastic IP 덕분에 주소는 안 바뀝니다.

### 코드만 바뀌었을 때는 terraform 을 쓰지 않습니다

```
ssh -i <키> ec2-user@api.pawloop.app
cd /opt/pawloop-backend/repo && sudo git pull
cd backend && sudo docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

## 지울 때

`terraform destroy` 는 **DB 볼륨에서 멈춥니다.** `prevent_destroy` 를 걸어 뒀습니다.

진짜로 지우려면 `main.tf` 의 그 `lifecycle` 블록을 먼저 지워야 하고, 그 편집 자체가 한 번
더 생각하게 만듭니다. **그것이 의도입니다.**

Elastic IP 는 인스턴스에서 떼어 두면 시간당 요금이 붙습니다. 서버를 오래 안 쓸 거면
`destroy` 로 EIP 까지 반납하는 편이 낫습니다 — 다만 그러면 **주소가 영원히 바뀌고**,
구글·카카오·애플 콘솔의 리다이렉트를 전부 다시 등록해야 합니다.

## 확인

```
curl -s -o /dev/null -w '%{http_code}\n' https://api.pawloop.app/actuator/health   # 200
curl -s -o /dev/null -w '%{http_code}\n' https://api.pawloop.app/actuator/prometheus # 404 여야 한다
```

두 번째가 **404 가 아니면 actuator 차단이 안 걸린 것**입니다 (#613).
