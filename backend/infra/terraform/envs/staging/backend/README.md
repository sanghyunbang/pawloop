# 스테이징 Backend EC2

이 env는 부하 테스트 대상이 되는 Backend EC2를 만든다.

Backend EC2에서는 Docker Compose로 다음 서비스를 실행한다.

- Spring Boot backend
- MySQL
- Prometheus
- Grafana

Prometheus/Grafana는 `enable_observability = true`일 때 `docker-compose.observability.yml`로 같이 올라간다.

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
| `repo_url` | public Git repo URL |
| `repo_branch` | 배포할 branch |
| `app_env_ssm_parameter_name` | backend `.env`가 들어 있는 SSM SecureString 이름 |
| `backend_app_allowed_cidr_blocks` | 8080 접근 허용 CIDR |
| `enable_observability` | Prometheus/Grafana 같이 실행 여부 |

## SSM에 저장할 backend `.env`

Backend EC2는 부팅 시 SSM Parameter Store에서 `.env` 전체 내용을 가져온다.

```bash
aws ssm put-parameter \
  --name /heat-trip/staging/backend/env \
  --type SecureString \
  --value file://.env \
  --overwrite
```

Loader EC2에서 Backend API를 때리려면 SSM에 저장하는 `.env`에 다음 값이 필요하다.

```text
APP_PUBLISHED_HOST=0.0.0.0
APP_PUBLISHED_PORT=8080
```

Backend 자체 처리량을 보고 싶으면 rate limit을 끈다.

```text
APP_SECURITY_RATE_LIMIT_ENABLED=false
```

단, 보안그룹에서 `8080`은 Loader EC2 또는 VPC private CIDR만 허용해야 한다.

## 실행

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## 출력값

| output | 설명 |
| --- | --- |
| `backend_private_ip` | Loader가 접근할 private IP |
| `backend_public_ip` | SSH 접속용 public IP |
| `backend_security_group_id` | 보안그룹 ID |
| `backend_base_url_for_loader` | Loader env에 넣을 Backend URL |

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

이 env는 staging 부하 테스트 편의를 위한 예시다. 운영 전에는 최소한 다음을 별도로 검토해야 한다.

- RDS 사용 여부
- private subnet 배치
- HTTPS/Nginx/ALB 구성
- CloudWatch log 수집
- SSM Session Manager 접속
- Grafana/Prometheus 접근 제어
