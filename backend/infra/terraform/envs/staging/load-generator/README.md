# 스테이징 Load Generator EC2

이 env는 k6 부하를 발생시키는 Loader EC2를 만든다.

Loader EC2에는 k6를 직접 설치하지 않는다. Docker로 `grafana/k6` 이미지를 실행한다.

## 파일 구성

```text
load-generator/
  versions.tf
  variables.tf
  main.tf
  outputs.tf
  user_data_load_generator.sh.tftpl
  terraform.tfvars.example
  backend.tf.example
  README.md
```

## 주요 변수

| 변수 | 설명 |
| --- | --- |
| `vpc_id` | Loader EC2를 만들 VPC |
| `subnet_id` | Loader EC2 subnet |
| `key_name` | SSH key pair 이름 |
| `repo_url` | public Git repo URL |
| `repo_branch` | k6 스크립트가 있는 branch |
| `backend_base_url` | Backend EC2 private URL |
| `k6_env_ssm_parameter_name` | k6 env를 담은 SSM SecureString 이름 |
| `default_vus` | SSM env가 없을 때 기본 VU |
| `default_duration` | SSM env가 없을 때 기본 duration |

## Backend URL 설정

Backend env를 먼저 apply하면 다음 output이 나온다.

```text
backend_base_url_for_loader = "http://<backend-private-ip>:8080"
```

이 값을 `terraform.tfvars`에 넣는다.

```hcl
backend_base_url = "http://<backend-private-ip>:8080"
```

## k6 env

인증 없는 테스트는 기본 env만으로 실행할 수 있다.

```text
BASE_URL=http://<backend-private-ip>:8080
VUS=20
DURATION=10m
```

Journey CRUD처럼 JWT가 필요한 테스트는 `ACCESS_TOKEN`이 필요하다.

```text
BASE_URL=http://<backend-private-ip>:8080
ACCESS_TOKEN=<jwt>
VUS=20
DURATION=10m
```

이 값에는 token이 들어가므로 파일을 커밋하지 않는다. 필요하면 SSM SecureString으로 저장한다.

```bash
aws ssm put-parameter \
  --name /heat-trip/staging/k6/env \
  --type SecureString \
  --value file://k6.env \
  --overwrite
```

그리고 Terraform 변수에 이름만 넣는다.

```hcl
k6_env_ssm_parameter_name = "/heat-trip/staging/k6/env"
```

## 실행

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

SSH 접속 후 실행한다.

```bash
run-heattrip-k6 domains/explore/explore-read-baseline.js
run-heattrip-k6 domains/journey/journey-crud.js
run-heattrip-k6 domains/curation/curation-non-llm-baseline.js
run-heattrip-k6 operations/mysql-ddl/journey-body-ddl-traffic.js
```

## DDL 테스트

운영성 검증용 DDL 테스트는 다음 스크립트를 사용한다.

```bash
run-heattrip-k6 operations/mysql-ddl/journey-body-ddl-traffic.js
```

이 스크립트는 ALTER TABLE을 실행하지 않는다. Journey API read/write 트래픽만 만든다. ALTER TABLE은 staging MySQL 세션에서 따로 실행하고, Grafana와 MySQL processlist를 같이 본다.

## 삭제

Loader는 테스트 후 삭제하는 것을 기본으로 한다.

```bash
terraform destroy
```

Backend state와 분리되어 있으므로 Loader만 지울 수 있다.
