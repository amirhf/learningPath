# Phase 0 - Infrastructure Summary

## What we built
- **VPC/Subnets/NAT**
  - Reused existing VPC. `module "vpc"` exposes `public_subnets` and `private_subnets`.
- **ECS Fargate services (reusable module `iac/modules/ecs_service/`)**
  - `module "service_rag"` (port 8000, desired 1)
  - `module "service_gateway"` (port 8080, desired 1)
  - `module "service_ingestion"` (worker, no port, desired 0)
- **Public ALB for gateway** (`iac/main.tf`)
  - `aws_security_group.alb` allows HTTP(80) from internet
  - `aws_lb.gateway` (internet-facing) in public subnets
  - `aws_lb_target_group.gateway` forwards to gateway on port 8080 (target type `ip`)
  - Listeners:
    - HTTP(80) forwards by default
    - Optional HTTPS(443) with ACM cert and HTTP→HTTPS redirect when `alb_acm_certificate_arn` is set
- **Internal service discovery (Cloud Map) for RAG**
  - `aws_service_discovery_private_dns_namespace.svc` name: `${var.project}.${var.env}.local`
  - `aws_service_discovery_service.rag` name: `rag`
  - `service_rag` registers; `service_gateway` uses `RAG_BASE_URL = "http://rag.${var.project}.${var.env}.local:8000"`
- **Secrets Manager for DB**
  - `aws_secretsmanager_secret.database_url` created
  - Optional version via `var.database_url_value` (`iac/variables_app.tf`)
  - `service_rag` injects secret env `DATABASE_URL`
  - Execution role is granted least-privileged read to only provided secret ARNs
- **SQS IAM for ingestion**
  - Added SQS queue ARN outputs in `iac/modules/sqs/main.tf`
  - `service_ingestion` attaches inline task-role policy for receive/delete/visibility/send on `ingest` and `replan` queues
- **ECS Exec enabled**
  - `enable_execute_command = true` in `iac/modules/ecs_service/main.tf`
- **Outputs**
  - `gateway_alb_dns_name` in `iac/outputs.tf`

## Key fixes during setup
- **Closed terraform block** in `iac/main.tf` to fix parsing errors
- **ALB target group name_prefix** shortened to `"gw-"` (<=6 chars)
- **ALB listener default_action** includes `type = "forward"`

## How services are wired
- **Gateway**: public via ALB. SG allows 8080 only from ALB SG
- **RAG**: private via Cloud Map DNS `rag.${project}.${env}.local`
- **Ingestion**: private worker; IAM scoped to SQS; `desired_count = 0`

---

# Useful commands

## Terraform
```powershell
cd C:\Users\firou\Documents\learningPath\iac
C:\Users\firou\bin\terraform.exe fmt
C:\Users\firou\bin\terraform.exe validate
C:\Users\firou\bin\terraform.exe plan -var-file="envs/dev.tfvars"
C:\Users\firou\bin\terraform.exe apply -var-file="envs/dev.tfvars"
```

Enable HTTPS for ALB by setting in your tfvars:
```hcl
alb_acm_certificate_arn = "arn:aws:acm:us-east-1:<account>:certificate/<uuid>"
```

## ALB and health
```powershell
C:\Users\firou\bin\terraform.exe output -raw gateway_alb_dns_name
```
```bash
curl -I http://<ALB_DNS>/
curl -i http://<ALB_DNS>/healthz
```

## DATABASE_URL secret
- Read value (sanity check):
```powershell
aws secretsmanager get-secret-value --secret-id learning-path/dev/DATABASE_URL --region us-east-1 --query SecretString --output text
```
- Write/update value:
```powershell
aws secretsmanager put-secret-value --secret-id learning-path/dev/DATABASE_URL --region us-east-1 --secret-string "postgres://postgres:<password>@<endpoint>:5432/<db>"
```
- Notes: RDS user is `postgres`; host is `module.rds.rds_endpoint`; password is from AWS-managed RDS master secret.

## ECS Exec (debug inside VPC)
```powershell
# Find a task for gateway, then:
aws ecs execute-command `
  --cluster <CLUSTER_NAME> `
  --task <TASK_ID> `
  --container gateway `
  --command "curl -i http://rag.learning-path.dev.local:8000/healthz" `
  --interactive `
  --region us-east-1
```

## ECR image presence
```powershell
aws ecr describe-images --repository-name learning-path-dev-gateway --region us-east-1 --query "imageDetails[?contains(imageTags, 'latest')].imageTags"
aws ecr describe-images --repository-name learning-path-dev-rag --region us-east-1 --query "imageDetails[?contains(imageTags, 'latest')].imageTags"
```

---

# Findings
- **RDS** uses `manage_master_user_password = true`; master password is in Secrets Manager; we store final `DATABASE_URL` in our app secret.
- **Networking**: Tasks in private subnets; ALB public in public subnets; RAG reachable via Cloud Map.
- **Least-privileged IAM** for secrets and SQS.

# Ready for Phase 1
- **Gateway ↔ RAG**: Use `RAG_BASE_URL` to call RAG. Confirm `/healthz` and API paths.
- **RAG ↔ Postgres**: App reads `DATABASE_URL` and runs migrations on start.
- **Ingestion**: Keep at 0 until code is ready to consume from SQS.

Optional next:
- **Custom domain + HTTPS** (set `alb_acm_certificate_arn` and Route53 ALIAS)
- **Tighten Qdrant SG** to allow only `module.service_rag.sg_id`
- **Basic alarms/dashboards** for ALB 5xx, TG unhealthy, ECS task failures
