# ec2-docker-host 모듈

이 모듈은 Docker 기반 workload를 실행할 수 있는 EC2 host를 만든다.

Backend EC2와 Loader EC2가 공통으로 사용한다.

## 생성 리소스

| 리소스 | 설명 |
| --- | --- |
| `aws_instance.this` | Amazon Linux 2023 EC2 |
| `aws_security_group.this` | SSH와 추가 ingress rule 관리 |
| `aws_iam_role.this` | EC2 instance role |
| `aws_iam_instance_profile.this` | EC2에 role 연결 |
| `aws_iam_role_policy.ssm` | 선택적으로 SSM/KMS read 권한 부여 |

## 기본 설치

`user_data.sh.tftpl`에서 다음을 설치한다.

- Docker
- Git
- AWS CLI
- Docker Compose plugin 가능 시 설치

그 후 env에서 넘긴 `startup_commands`를 실행한다.

## 입력 변수

| 변수 | 설명 |
| --- | --- |
| `name` | resource name prefix |
| `vpc_id` | 보안그룹을 만들 VPC |
| `subnet_id` | EC2 subnet |
| `ami_id` | 비워두면 최신 Amazon Linux 2023 사용 |
| `instance_type` | EC2 instance type |
| `key_name` | SSH key pair |
| `allowed_ssh_cidr_blocks` | SSH 허용 CIDR |
| `ingress_rules` | 추가 ingress rule |
| `iam_ssm_parameter_arns` | 읽을 수 있는 SSM parameter ARN |
| `kms_key_arns` | SecureString 복호화 KMS key ARN |
| `startup_commands` | Docker 설치 후 실행할 bootstrap shell |

## 출력값

| output | 설명 |
| --- | --- |
| `instance_id` | EC2 instance ID |
| `private_ip` | private IP |
| `public_ip` | public IP |
| `security_group_id` | security group ID |

## 보안 기준

- SSH는 `allowed_ssh_cidr_blocks`에 명시된 CIDR만 허용한다.
- 추가 ingress는 env에서 명시적으로 넘긴다.
- SSM parameter read 권한은 필요한 parameter ARN만 부여한다.
- SecureString 복호화가 필요할 때만 `kms_key_arns`를 준다.
- 실제 secret 값은 모듈 변수로 넘기지 않는다.

## 재사용 예시

Backend env는 `startup_commands`로 repo clone, SSM `.env` 다운로드, Docker Compose 실행을 넘긴다.

Load Generator env는 repo clone 후 `run-heattrip-k6` helper script 생성을 넘긴다.

