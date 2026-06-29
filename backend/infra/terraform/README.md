# Heat Trip Terraform 구성

이 디렉터리는 k6 부하 테스트를 AWS EC2에서 재현하기 위한 Terraform 코드다.

Backend EC2와 Load Generator EC2를 일부러 분리했다. Backend는 오래 살아 있는 서버이고, Loader는 부하 테스트가 끝나면 바로 지울 수 있는 일회성 성격이 강하기 때문이다.

## 전체 구조

```text
infra/terraform/
  modules/
    ec2-docker-host/          # Docker가 설치된 EC2 공통 모듈
  envs/
    staging/
      backend/                # Spring Boot + MySQL + Prometheus/Grafana
      load-generator/         # k6 실행 전용 EC2
```

## 역할 분리

| 영역 | 책임 | 수명 |
| --- | --- | --- |
| `envs/staging/backend` | Backend EC2, Docker Compose 실행, observability stack | 비교적 오래 유지 |
| `envs/staging/load-generator` | k6 실행용 Loader EC2 | 테스트 전 생성, 테스트 후 삭제 가능 |
| `modules/ec2-docker-host` | EC2, Security Group, IAM Role, Docker 설치 공통화 | 재사용 모듈 |

## 왜 state를 나누는가

Backend와 Loader를 같은 Terraform state에 넣으면 Loader만 지우고 싶을 때 실수로 Backend까지 건드릴 가능성이 커진다.

그래서 권장 state는 다음처럼 분리한다.

```text
heat-trip/staging/backend/terraform.tfstate
heat-trip/staging/load-generator/terraform.tfstate
```

각 env에는 `backend.tf.example`만 커밋되어 있다. 실제 S3 bucket, DynamoDB lock table 이름은 계정별 정보이므로 `backend.tf`로 로컬에서 복사해서 사용하고 커밋하지 않는다.

```bash
cp backend.tf.example backend.tf
```

`.gitignore`에서 `infra/terraform/**/backend.tf`, `*.tfvars`, `*.tfstate`를 무시한다.

## public repo secret 정책

이 Terraform 코드는 public repo 기준으로 작성했다.

커밋해도 되는 것:

- `terraform.tfvars.example`
- `backend.tf.example`
- placeholder 값
- SSM Parameter Store 이름
- 보안그룹 설계 예시

커밋하면 안 되는 것:

- 실제 `terraform.tfvars`
- 실제 `backend.tf`
- AWS access key/secret key
- DB 비밀번호
- JWT secret
- OpenAI key
- OAuth client secret
- k6 `ACCESS_TOKEN`

애플리케이션 `.env`는 AWS SSM Parameter Store의 `SecureString`에 저장한다.

예시:

```bash
aws ssm put-parameter \
  --name /heat-trip/staging/backend/env \
  --type SecureString \
  --value file://.env \
  --overwrite
```

k6 토큰이나 테스트 계정이 들어간 env도 필요하면 별도 SecureString으로 저장한다.

```bash
aws ssm put-parameter \
  --name /heat-trip/staging/k6/env \
  --type SecureString \
  --value file://k6.env \
  --overwrite
```

## 실행 순서

1. Backend용 `.env`를 만든다.
2. Backend용 `.env`를 SSM SecureString에 저장한다.
3. `envs/staging/backend`를 apply한다.
4. output의 `backend_base_url_for_loader`를 확인한다.
5. `envs/staging/load-generator/terraform.tfvars`의 `backend_base_url`에 넣는다.
6. `envs/staging/load-generator`를 apply한다.
7. Loader EC2에 SSH 접속해서 `run-heattrip-k6`를 실행한다.
8. 테스트가 끝나면 load-generator env만 destroy한다.

## 보안그룹 기준

Backend EC2:

- `8080`: Loader EC2 private CIDR 또는 VPC CIDR만 허용
- `22`: 내 IP만 허용
- `3000`, `9090`: 기본적으로 외부 공개하지 않음. SSH tunnel 사용
- `3306`: 외부 공개하지 않음

Loader EC2:

- `22`: 내 IP만 허용
- outbound: Backend EC2 `8080` 접근 가능

## Terraform CLI 검증

로컬에 Terraform이 설치되어 있으면 각 env에서 실행한다.

```bash
terraform fmt -recursive
terraform init
terraform validate
terraform plan
```

현재 작업 환경에는 Terraform CLI가 없어 이 검증은 실행하지 못했다. 대신 public-safe placeholder와 파일 구조는 정적으로 점검했다.
