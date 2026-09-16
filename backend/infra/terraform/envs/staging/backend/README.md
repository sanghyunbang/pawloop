# 스테이징 Backend EC2

이 env는 Backend EC2 한 대를 만든다. 원래는 부하 테스트 대상으로 쓰려고 쓰였고, 지금은
staging 을 처음 띄우는 자리로도 쓴다.

Backend EC2에서는 Docker Compose로 다음 서비스를 실행한다.

- Spring Boot backend
- MySQL
- Prometheus
- Grafana

Prometheus/Grafana는 `enable_observability = true`일 때 `docker-compose.observability.yml`로 같이 올라간다.

## 이 env가 만들지 않는 것

나중에 물릴 때 놀라지 않도록 적어 둔다.

- **RDS 없다.** MySQL은 이 EC2 안의 컨테이너다. 인스턴스를 지우면 DB도 같이 사라진다
- **로드밸런서·HTTPS 없다.** `http://<공인 IP>:8080`으로 답한다
- **Elastic IP 없다.** 인스턴스를 껐다 켜면 공인 IP가 바뀐다
- VPC·subnet·key pair는 만들지 않는다. **이미 있는 것**을 가져다 쓴다

## 파일 구성

```text
backend/
  versions.tf
  variables.tf
  main.tf
  outputs.tf
  user_data_backend.sh.tftpl
  terraform.tfvars.example
  backend.tf.example
  README.md
```

## 주요 변수

| 변수 | 설명 |
| --- | --- |
| `vpc_id` | EC2를 만들 VPC |
| `subnet_id` | Backend EC2 subnet |
| `key_name` | SSH key pair 이름 |
| `repo_url` | Git repo URL. private이면 SSH 형식(`git@github.com:소유자/저장소.git`) |
| `repo_branch` | 배포할 branch |
| `repo_deploy_key_ssm_parameter_name` | 읽기 전용 deploy key가 들어 있는 SSM SecureString 이름 |
| `app_env_ssm_parameter_name` | backend `.env`가 들어 있는 SSM SecureString 이름 |
| `backend_app_allowed_cidr_blocks` | 8080 접근 허용 CIDR |
| `enable_observability` | Prometheus/Grafana 같이 실행 여부 |

## private 저장소용 deploy key

이 저장소는 private이다. EC2가 인증 없이 `git clone`하면 코드를 못 받고, 부팅만 끝난다.
읽기 전용 deploy key를 SSM에 넣어 두고 부트스트랩이 받아 쓴다.

deploy key는 **저장소 하나에만** 붙고 **읽기 전용**이다. 개인 계정 키를 서버에 두는 것과
다르다. 서버가 털려도 그 키로 할 수 있는 일은 이 저장소를 읽는 것뿐이다.

```bash
# 1. 키 한 쌍을 만든다. 암호는 걸지 않는다 — 서버가 사람 없이 읽어야 한다.
ssh-keygen -t ed25519 -C "heat-trip-staging-backend" -f ./heattrip_deploy_key -N ""

# 2. 공개키를 저장소에 읽기 전용으로 단다. --allow-write 를 주지 않으면 읽기 전용이다.
gh repo deploy-key add ./heattrip_deploy_key.pub --title "heat-trip-staging-backend"

# 3. 개인키를 SSM SecureString으로 올린다.
aws ssm put-parameter \
  --name /heat-trip/staging/backend/deploy-key \
  --type SecureString \
  --value file://heattrip_deploy_key \
  --region ap-northeast-2 \
  --overwrite

# 4. 이 기계에서 개인키를 지운다. SSM에 있으면 여기 둘 이유가 없다.
rm -f ./heattrip_deploy_key ./heattrip_deploy_key.pub
```

부트스트랩은 이 키로 clone하면서 `github.com`의 호스트 키를 **미리 적어 둔 값과 대조한다**.
깃헙이 호스트 키를 바꾸면 거기서 부팅이 멈춘다. 그건 고장이 아니라 알아채라는 뜻이다 —
`user_data_backend.sh.tftpl`의 그 줄을 바꾼다.

## SSM에 저장할 backend `.env`

Backend EC2는 부팅할 때 SSM Parameter Store에서 `.env` 전체 내용을 가져온다.

**표준 등급 parameter의 값 한도는 4KB다.** 개발용 `backend/.env`는 주석이 많아 그대로는
넘는다. 주석과 빈 줄을 빼면 들어간다 — 서버에는 주석이 필요 없다.

```bash
# 크기부터 잰다. 4096을 넘으면 put-parameter가 ValidationException으로 거절한다.
grep -vE '^[[:space:]]*(#|$)' .env | wc -c

# 주석·빈 줄을 뺀 사본을 만들어 올린다. CR(\r)이 섞여 있으면 값 끝에 \r이 붙으므로 같이 턴다.
grep -vE '^[[:space:]]*(#|$)' .env | tr -d '\r' > .env.ssm

aws ssm put-parameter \
  --name /heat-trip/staging/backend/env \
  --type SecureString \
  --value file://.env.ssm \
  --region ap-northeast-2 \
  --overwrite

rm -f .env.ssm
```

그래도 4KB를 넘으면 `--tier Advanced`를 준다. 8KB까지 늘지만 **요금이 붙고, 표준으로 되돌릴
수 없다**(지웠다 다시 만들어야 한다).

밖에서 API를 때리려면 SSM에 넣는 `.env`에 다음 값이 필요하다. 없으면 compose가 컨테이너
포트를 `127.0.0.1`에만 묶어서, 보안그룹을 열어도 답하지 않는다.

```text
APP_PUBLISHED_HOST=0.0.0.0
APP_PUBLISHED_PORT=8080
```

Backend 자체 처리량을 보고 싶으면 rate limit을 끈다.

```text
APP_SECURITY_RATE_LIMIT_ENABLED=false
```

단, 보안그룹에서 `8080`은 Loader EC2 또는 VPC private CIDR, 아니면 내 공인 IP 하나만
허용해야 한다.

## 실행

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

`backend.tf`를 만들지 않으면 상태가 이 기계의 `terraform.tfstate` 파일로 남는다. 혼자
처음 띄울 때는 그래도 된다. 여러 기계·여러 사람이 되면 `backend.tf.example`을 쓴다.

## 출력값

| output | 설명 |
| --- | --- |
| `backend_private_ip` | Loader가 접근할 private IP |
| `backend_public_ip` | SSH 접속용 public IP |
| `backend_security_group_id` | 보안그룹 ID |
| `backend_base_url_for_loader` | Loader env에 넣을 Backend URL |

## 떴는지 확인

`apply`가 끝나도 앱이 바로 답하지는 않는다. 부팅 스크립트가 Docker를 깔고, 저장소를
받고, Gradle로 이미지를 굽는다. 처음에는 몇 분 걸린다.

```bash
# 부팅 스크립트가 어디까지 갔는지
ssh ec2-user@<backend-public-ip> 'sudo tail -f /var/log/cloud-init-output.log'

# 컨테이너가 떴는지
ssh ec2-user@<backend-public-ip> 'sudo docker compose -f /opt/heattrip-backend/repo/backend/docker-compose.yml ps'

# 앱이 답하는지
curl http://<backend-public-ip>:8080/actuator/health
```

## Grafana 확인

Grafana는 기본적으로 localhost에만 열린다.

```bash
ssh -L 3000:127.0.0.1:3000 ec2-user@<backend-public-ip>
```

브라우저에서:

```text
http://127.0.0.1:3000
```

## 운영 전 주의

이 env는 staging 편의를 위한 예시다. 운영 전에는 최소한 다음을 별도로 검토해야 한다.

- RDS 사용 여부 (지금은 EC2 안의 컨테이너라 인스턴스와 수명이 같다)
- Elastic IP 또는 도메인 (지금은 재부팅마다 공인 IP가 바뀐다)
- private subnet 배치
- HTTPS/Nginx/ALB 구성
- CloudWatch log 수집
- SSM Session Manager 접속
- Grafana/Prometheus 접근 제어
