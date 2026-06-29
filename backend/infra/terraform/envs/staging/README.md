# 스테이징 Terraform

이 폴더는 부하 테스트용 staging 인프라를 정의한다.

## 구성

```text
staging/
  backend/
  load-generator/
```

## 실행 순서

먼저 Backend를 만든다.

```bash
cd infra/terraform/envs/staging/backend
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

Backend apply 후 출력되는 값을 확인한다.

```text
backend_base_url_for_loader = "http://<backend-private-ip>:8080"
```

그 다음 Loader를 만든다.

```bash
cd ../load-generator
cp terraform.tfvars.example terraform.tfvars
# backend_base_url 값을 위 output으로 수정
terraform init
terraform apply
```

## 삭제 순서

테스트 후에는 Loader부터 삭제한다.

```bash
cd infra/terraform/envs/staging/load-generator
terraform destroy
```

Backend는 필요할 때만 따로 삭제한다.

```bash
cd ../backend
terraform destroy
```

## 주의

staging이라도 실제 AWS 비용이 발생한다.

- EC2 instance
- EBS volume
- Elastic IP를 붙이면 EIP 비용
- NAT Gateway를 쓰는 VPC라면 NAT 비용
- CloudWatch/SSM/KMS 사용량

Loader는 테스트가 끝나면 바로 삭제하는 것을 전제로 한다.
