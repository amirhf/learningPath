Learning Path Designer — MVP: Detailed Design &
Implementation Plan
1. Executive Summary
This document specifies the Learning Path Designer MVP, a cloud-native application that converts a user's learning
goal and constraints into a sequenced, credible learning plan with curated resources, grounded summaries,
micro-quizzes, progress tracking, and adaptive re-planning. It showcases AI integration, Retrieval-Augmented
Generation (RAG), and a lightweight agent orchestration pattern. The target domain for the initial dataset is
‘Event-driven Microservices Interview Prep.’ Deployment targets AWS (ECS Fargate, RDS Postgres, S3, SQS,
Cognito), with Qdrant for vector search and e5-base embeddings. The LLM provider is OpenRouter for generation.

2. Objectives & Non-Goals
Objectives: (a) Demonstrate end-to-end AI/RAG/agent orchestration; (b) Deliver a working, shareable web app with
authenticated plans and quizzes; (c) Build an ingestion pipeline and a searchable catalog using Qdrant with e5-base
embeddings; (d) Provide a clean API layer for future teams/tools. Non-Goals: (a) Enterprise-grade multi-tenancy
and SSO; (b) Proprietary paid content ingestion; (c) Complex multi-agent collaboration beyond a single planner
agent; (d) Mobile apps.

3. Scope & Success Criteria
Scope includes: data ingestion (150–300 CC/official sources), RAG search with filters + rerank, plan sequencing
with prerequisites, grounded lesson summaries, auto-generated quizzes, progress tracking, and re-planning.
Success: a reviewer can log in, create a 4-week plan, study a lesson with citations, answer a quiz, and trigger a
re-plan in under 5 minutes.

4. Architecture Overview
Frontend (Next.js) ↔ Go Gateway (auth, rate limit, fan-out, tracing) ↔ Python microservices (rag-service,
planner-service, quiz-service) ↔ Qdrant (vectors), Postgres (metadata & plans), S3 (snippets), SQS (jobs).
Observability via OpenTelemetry → AWS X-Ray & CloudWatch. Auth by AWS Cognito. CI/CD using GitHub Actions
→ ECR → ECS Fargate (blue/green).

Frontend: Next.js (TS), Tailwind, shadcn/ui, TanStack Query.
Gateway: Go (Gin/Fiber). Validates Cognito JWTs, shapes requests, rate-limits, traces.
AI services: FastAPI. rag-service (embed/search/rerank/summarize), planner-service (sequencing/replan),
quiz-service (grounded MCQ/short-answer).
Data: Qdrant (resources vectors), Postgres (users, goals, skills, plans, lessons, progress), S3 (snippets), SQS
(ingestion, re-plan).
Models: e5-base for embeddings; bge-reranker-base for rerank; OpenRouter for LLM generation.
5. AWS Deployment Topology
VPC with public and private subnets across at least two AZs.
ALB (public) → ECS Service: gateway-go (Fargate, private subnets).
Private ECS Services: rag-service, planner-service, quiz-service, worker-celery.
RDS Postgres (Multi-AZ), Qdrant (Qdrant Cloud or self-hosted Fargate), S3 buckets for snippets and snapshots.
SQS queues: ingest, replan.
Secrets Manager & Parameter Store for API keys and configuration.
OpenTelemetry SDK exporting to X-Ray; logs to CloudWatch; optional Grafana dashboards.
6. Repository Structure
/frontend # Next.js app (TypeScript)
/gateway # Go (Gin) gateway
/services/rag # FastAPI RAG (embed/search/rerank/summarize)
/services/planner # FastAPI planner (agent with JSON tools)
/services/quiz # FastAPI quiz generator & grader
/ingestion # Ingestion workers (Celery), seed lists, parsers
/iac # Terraform (VPC, ECS, RDS, SQS, ALB, Cognito, etc.)
/ops # GitHub Actions workflows, Dockerfiles, Makefiles
/shared # Protos/schemas, OpenAPI, config, utilities

7. Data Model (Postgres DDL)
CREATE TABLE skill (
id UUID PRIMARY KEY,
name TEXT NOT NULL,
slug TEXT UNIQUE,
level_hint INT DEFAULT 0
);
CREATE TABLE skill_edge (
from_skill UUID REFERENCES skill(id) ON DELETE CASCADE,
to_skill UUID REFERENCES skill(id) ON DELETE CASCADE,
PRIMARY KEY (from_skill, to_skill)
);
CREATE TABLE resource (
id UUID PRIMARY KEY,
title TEXT NOT NULL,
url TEXT NOT NULL,
provider TEXT,
license TEXT,
duration_min INT,
level INT,
skills UUID[] NOT NULL,
recency_date DATE,
s3_cache_key TEXT
);
CREATE TABLE app_user (
id UUID PRIMARY KEY,
email TEXT UNIQUE NOT NULL,
cognito_sub TEXT UNIQUE
);
CREATE TABLE goal (
id UUID PRIMARY KEY,
user_id UUID REFERENCES app_user(id),
title TEXT NOT NULL,
target_date DATE,
hours_per_week INT,
level INT,
prefs JSONB
);
CREATE TABLE plan (
id UUID PRIMARY KEY,
goal_id UUID REFERENCES goal(id),
total_weeks INT,
created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE lesson (

id UUID PRIMARY KEY,
plan_id UUID REFERENCES plan(id),
week INT,
seq INT,
title TEXT,
resource_ids UUID[],
est_minutes INT
);
CREATE TABLE progress (
id UUID PRIMARY KEY,
lesson_id UUID REFERENCES lesson(id),
status TEXT CHECK (status IN ('todo','in_progress','done','skipped')),
actual_minutes INT,
quiz_score NUMERIC
);

8. Qdrant Collection & Payload Schema
Collection: resources
Vector: e5-base (768 dims), metric=cosine, HNSW (M=16, ef_construction=128)
Payload:
{
"resource_id": "uuid",
"title": "string",
"url": "string",
"skills": ["string"],
"level": "integer",
"duration_min": "integer",
"provider": "string",
"license": "string",
"recency_date": "date",
"popularity": "float",
"media_type": "string"
}
Recommended filters: level <= user.level, license in allowlist, duration_min <= cap.
Rerank: bge-reranker-base on top-k=20 → top-5.

9. API Contracts — Go Gateway (OpenAPI Sketch)
POST /api/intake
Req: { title, target_date, hours_per_week, level, prefs }
Res: { goal_id }

POST /api/plan
Req: { goal_id }
Res: { plan_id, total_weeks, lessons: [{lesson_id, week, seq, title, est_minutes, resources:
[...] }] }

GET /api/plan/{id}
Res: { ...plan }

POST /api/plan/{id}/replan
Req: { progress_delta, remaining_weeks }
Res: { ...updatedPlan }

POST /api/quiz/lesson/{lessonId}
Res: { quiz_id, items: [...] }

POST /api/progress/lesson/{lessonId}
Req: { status, actual_minutes?, quiz_score? }
Res: 200 OK

GET /api/resources/search?query=...&level;=...&max;_time=...&media;=...
Res: [ ResourceCard ]

GET /api/skills
Res: { nodes: [...], edges: [...] }

10. Service Contracts — Internal APIs
rag-service:
POST /embed { texts: string[] } -> { vectors: number[][] }
POST /search { query, filters, top_k } -> { hits: [ {resource_id, score, payload} ] }
POST /summarize { resource_ids[], question? } -> { summary, citations: [url] }

planner-service:
POST /plan { goal_id } -> plan JSON (strict schema)
POST /replan { plan_id, progress_delta } -> updated plan

quiz-service:
POST /generate { lesson_id, resource_ids[] } -> { quiz_id, items: [...] }
POST /grade { quiz_id, answers: [...] } -> { score, feedback }

11. JSON Schemas (Prompts & Tools)
Planner Input:
{
"goal": "string",
"skills": ["string"],
"hours_per_week": 6,
"target_date": "YYYY-MM-DD",
"level": 1,
"media_prefs": ["video","reading"]
}

Planner Output:
{
"weeks":[
{"week":1,"lessons":[
{"title":"Foundations of Event-Driven Systems","resource_ids":["uuid"],"est_minutes":90}
]}
]
}

SearchResources Tool Input:
{ "query":"kafka partitions and keys", "skill_targets":["kafka","partitioning"],
"max_time":60, "level":1, "media_prefs":["reading"] }
SearchResources Tool Output:
[ {"resource_id":"uuid","title":"...","url":"...","why":"...","est_minutes":25,"skills":["kafk
a","partitioning"]} ]

Quiz Item:
{ "type":"mcq","question":"...","options":["A","B","C","D"],"answer":"B","grounding":{"resourc
e_id":"uuid","span":"quoted text"} }

12. Prompt Templates (LLM via OpenRouter)
Planner System Prompt:
"You are a precise learning planner for software engineers. Respect prerequisites, user time budgets, and level.
Prefer official docs and CC resources. If you need content, call the search_resources tool. Output strictly in the
JSON schema."

Lesson Summary Prompt (grounded):
"Summarize the key ideas the learner should grasp from the following resources to complete this lesson. Use only
the snippets provided, and cite URLs. Audience level: {level}."

Quiz Generation Prompt (guarded):
"Create 2–4 questions assessing comprehension of the provided snippets. Each question must include a correct
answer and a short explanation citing the exact snippet span."

13. Ingestion Pipeline & Algorithms
Seed list (CSV/JSON) with title, URL, provider, license, duration, level, tags.
Fetch metadata (HTTP GET) and, when allowed, a short snippet (first 2–3 paragraphs).
Compute e5-base embedding; store in Qdrant with payload; write Postgres resource record; upload snippet to
S3.
Classify media_type and map tags to skills (heuristics + curated mapping).
Nightly job recalculates popularity (clicks, completion) and refreshes changed embeddings.
Error handling: retry with backoff; poison queue for failed fetches.
14. Evaluation, Testing, and Safety
Retrieval: precision@k against a small gold set (10–20 queries).
Plans: heuristic checks (minutes/week within ±10%, prerequisites respected).
Quizzes: grounding coverage ≥ 90%; no question without snippet span.
Redaction: strip PII from prompts; do not store user text in logs.
Unit & golden tests for JSON outputs; contract tests for internal APIs.
15. Phase-by-Phase Plan (4 Weeks)
Week Workstream Deliverables
1 Catalog & RAG Qdrant up; e5-base embeddings; ingest 150–300 resources; /resources/search API + UI.
2 Planner Skill graph; planner-service; generate plan; Plan UI with citations.
3 Quizzes & Progress quiz-service; grounded questions; progress model; replan logic; Replan UI.
4 AWS & Polishing Cognito auth; tracing; dashboards; CI/CD to ECS; demo users; shareable read-only plan.
16. Implementation Notes & Defaults
Embeddings: intfloat/e5-base (HF Transformers). Batch size 16; FP16 on CPU acceptable for
MVP.
Reranker: bge-reranker-base via sentence-transformers cross-encoder (top-20 → top-5).
Qdrant: HNSW (M=16, ef_search=64). Payload filter for level/license/duration.
Gateway: Gin + middleware (JWT verify, request ID, rate limit). go-playground/validator for
schema validation.
FastAPI: Pydantic v2 models; Uvicorn workers=2; gunicorn optional.
Celery: SQS transport; visibility timeout > 3x job p95.
Observability: traceparent propagation; sample user journey traces from frontend.
17. Security & Cost Considerations
IAM least privilege per ECS task; KMS-encrypt S3 and RDS; WAF on ALB recommended.
Secrets in AWS Secrets Manager; rotate OpenRouter keys.
Cost control: cap top-k, cache summaries for 24h, disable rerank for >N tokens, small Fargate tasks (0.
vCPU/1GB) for MVP.
18. Demo Script
Login with demo user. 2) Create goal (4 weeks, 6h/week, Intermediate). 3) Plan appears with 3–4 lessons/week.
Open one lesson: see grounded summary + citations. 5) Take quiz (2–4 Q) and get score. 6) Skip a lesson →
Replan → observe compressed schedule and swapped shorter resources. 7) Copy shareable link.
19. Initial Seed Resource List (≈60 URLs)
https://microservices.io/patterns/index.html
https://martinfowler.com/articles/microservices.html
https://www.confluent.io/blog/event-driven-architecture/
https://kafka.apache.org/documentation/
https://docs.confluent.io/platform/current/kafka-introduction.html
https://redpanda.com/blog
https://www.redpanda.com/documentation/
https://event-driven.io/en/
https://redis.io/docs/latest/develop/streams/
https://redis.io/docs/latest/develop/pubsub/
https://www.postgresql.org/docs/current/logicaldecoding-explanation.html
https://debezium.io/documentation/
https://grpc.io/docs/
https://12factor.net/
https://aws.amazon.com/prescriptive-guidance/
https://aws.amazon.com/architecture/well-architected/
https://docs.aws.amazon.com/sqs/latest/dg/welcome.html
https://docs.aws.amazon.com/sns/latest/dg/welcome.html
https://docs.aws.amazon.com/eventbridge/latest/userguide/what-is-amazon-eventbridge.html
https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html
https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Welcome.html
https://www.postgresql.org/docs/current/index.html
https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html
https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/WhatIsCloudWatch.html
https://docs.aws.amazon.com/xray/latest/devguide/aws-xray.html
https://opentelemetry.io/docs/
https://docs.qdrant.tech/
https://huggingface.co/intfloat/e5-base
https://huggingface.co/BAAI/bge-reranker-base
https://fastapi.tiangolo.com/
https://gin-gonic.com/docs/
https://go.dev/doc/effective_go
https://go.dev/blog/pipelines
https://pydantic.dev/
https://www.celeryq.dev/
https://docs.celeryq.dev/en/stable/getting-started/introduction.html
https://kombu.readthedocs.io/en/stable/reference/kombu.transport.SQS.html
https://docs.github.com/actions
https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html
https://docs.aws.amazon.com/AmazonECS/latest/developerguide/Welcome.html
https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html
https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/WhatIsCloudWatchLogs.html
https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-update-rules.html
https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-identity-pools.html
https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html
https://www.openpolicyagent.org/docs/latest/
https://docs.docker.com/
https://www.jaegertracing.io/docs/
https://grafana.com/docs/grafana/latest/
https://kubernetes.io/docs/concepts/overview/
https://www.nginx.com/blog/building-microservices-using-an-api-gateway/
https://microservices.io/patterns/data/transactional-outbox.html
https://microservices.io/patterns/data/cqrs.html
https://microservices.io/patterns/data/saga.html
https://martinfowler.com/eaaDev/EventSourcing.html
https://docs.temporal.io/
https://learn.microsoft.com/azure/architecture/patterns/
https://learn.microsoft.com/azure/architecture/guide/architecture-styles/event-driven
https://www.cloudflare.com/learning/serverless/what-is-event-driven-architecture/
https://testing.googleblog.com/
https://go.dev/doc/effective_go#testing
https://www.docker.com/blog/container-security-best-practices/
20. CI/CD & IaC Stubs
GitHub Actions:

jobs: build-and-push (docker login ECR, docker buildx, push), deploy (update ECS services via
aws-actions/amazon-ecs-deploy-task-definition).
matrix across services; tag images with git sha.
Terraform:

Modules for VPC, ALB, ECS services, RDS, SQS, Cognito. Remote state (S3 + DynamoDB lock).
21. Risks & Mitigations
LLM cost spikes: cache summaries; cap context; prefer smaller models when possible.
Licensing: store minimal snippets; always link to source; prefer CC/official docs.
Vector drift: schedule re-embeddings; version your collections.
Cold-start: prewarm embeddings and search endpoints during CI.
