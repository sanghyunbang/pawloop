# Terraform 모듈

이 폴더는 env에서 재사용하는 Terraform 모듈을 보관한다.

```text
modules/
  ec2-docker-host/
```

## 모듈 작성 기준

모듈은 특정 환경 이름을 몰라야 한다.

좋은 입력:

- `name`
- `vpc_id`
- `subnet_id`
- `instance_type`
- `key_name`
- `ingress_rules`
- `startup_commands`

나쁜 입력:

- 특정 staging SSM parameter 이름을 모듈 안에 하드코딩
- 특정 GitHub repo URL을 모듈 안에 하드코딩
- 실제 secret 값

환경별 차이는 `envs/staging/backend`, `envs/staging/load-generator`에서 조립한다.
