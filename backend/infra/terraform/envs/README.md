# Terraform 환경 구성

이 폴더는 실제 배포 단위별 Terraform env를 담는다.

```text
envs/
  staging/
    backend/
    load-generator/
```

## env 분리 기준

같은 AWS 계정과 VPC를 쓰더라도 수명과 책임이 다르면 env를 나눈다.

| env | 이유 |
| --- | --- |
| `staging/backend` | Spring Boot와 MySQL을 유지하는 서버 |
| `staging/load-generator` | 부하 테스트 때만 켜는 k6 실행 서버 |

## 파일 규칙

각 env는 다음 파일을 가진다.

| 파일 | 설명 |
| --- | --- |
| `versions.tf` | Terraform/provider version |
| `variables.tf` | 입력 변수 |
| `main.tf` | 실제 resource/module 조립 |
| `outputs.tf` | 다음 단계에서 사용할 출력값 |
| `terraform.tfvars.example` | public-safe 예시 변수 |
| `backend.tf.example` | S3 remote state 예시 |
| `README.md` | env 사용법 |

실제 `terraform.tfvars`, `backend.tf`는 커밋하지 않는다.
