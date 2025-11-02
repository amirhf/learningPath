# Implementation Plan

Aligned with `plan.md` and `design.md` (Qdrant: self-hosted on ECS Fargate), this plan details objectives, workstreams, deliverables, acceptance criteria, dependencies, and risks per phase.

## Phase 0 — Project Setup (Days 0–1)
- **Objectives**
  - Initialize repo structure, CI/CD skeleton, and IaC stubs so workstreams can move in parallel.
- **Workstreams**
  - **Repo & Scaffolding**: Create folders: `/frontend`, `/gateway`, `/services/{rag,planner,quiz}`, `/ingestion`, `/iac`, `/ops`, `/shared`.
  - **CI/CD**: Add GitHub Actions skeleton (build-and-push, deploy), ECR repo names, image tags (git SHA).
  - **IaC**: Terraform stubs for VPC, ECR, ECS Services, ALB, RDS, SQS, Cognito, Secrets Manager (remote state S3 + DynamoDB lock).
  - **Shared Schemas**: Place OpenAPI and JSON Schemas in `/shared`.
- **Deliverables**
  - Repo structure, initial Dockerfiles, Makefiles (stubs).
  - CI: build pipelines for all services (no deploy yet).
  - IaC stubs planned with modules outlined.
- **Acceptance Criteria**
  - PR builds pass (lint/build placeholders) on all services.
  - `terraform plan` succeeds per module with no errors (using placeholders).
- **Dependencies**
  - None.
- **Risks/Mitigations**
  - Drift in IaC: use remote state and versioned modules.

## Phase 1 — Catalog & RAG (Week 1)
- **Objectives**
  - Stand up searchable catalog backed by Qdrant + e5-base, with filters and rerank.
  - Ship `/api/resources/search` with a minimal Frontend search UI.
- **Workstreams**
  - **Data Layer**
    - Provision Qdrant (self-hosted on ECS Fargate with EBS gp3 snapshot backups to S3) and Postgres (DDL per plan).
    - Implement DDL in Terraform for RDS; apply in dev.
  - **RAG Service (`/services/rag`)**
    - Endpoints: `/embed`, `/search`, `/summarize`.
    - Implement e5-base embeddings (HF Transformers), Qdrant upsert/search with payload filters.
    - Add bge-reranker-base rerank for top-5.
  - **Ingestion (`/ingestion`)**
    - Celery (SQS transport): seed-list parsing, metadata fetch, snippet (license permitting), embeddings, Qdrant upsert, PG write, optional S3 snippet.
    - Nightly popularity refresh (stubbed).
  - **Gateway (`/gateway`)**
    - `/api/resources/search` pass-through with validation and tracing. JWT middleware scaffold (Cognito placeholder).
  - **Frontend (`/frontend`)**
    - Minimal page: query, filters (level, license, duration), results with why-picked/est_time/citations. TanStack Query.
- **Deliverables**
  - 150–300 seeded resources ingested.
  - Live search (filters + rerank) via `/api/resources/search`.
  - Minimal Search UI page.
- **Acceptance Criteria**
  - p95 search < 800ms at top-k=20.
  - Precision@k baseline eval (gold set 10–20 queries) recorded to `/ops`.
  - Tracing spans visible in X-Ray (or local OTel collector).
- **Dependencies**
  - Qdrant Fargate service, Postgres, S3 buckets, SQS queues provisioned (dev).
- **Risks/Mitigations**
  - License compliance: store only metadata + minimal snippet; always cite source.

## Phase 2 — Planner & Plan UI (Week 2)
- **Objectives**
  - Generate sequenced plans that respect skill prerequisites and user budgets.
  - Deliver end-to-end plan creation via Gateway with usable Plan UI.
- **Workstreams**
  - **Planner Service (`/services/planner`)**
    - Tools (JSON-tool style): `search_resources`, `sequence_plan`, `replan` (quiz call stubbed).
    - Implement skill graph (tables `skill`, `skill_edge`) and sequencing (adjacency lists in PG).
    - Strict JSON schemas for planner input/output (`/shared`).
  - **Gateway (`/gateway`)**
    - Routes: `/api/intake`, `/api/plan`, `/api/plan/:id`, `/api/skills` with tracing.
  - **Frontend (`/frontend`)**
    - Intake form (goal, target_date, hours/week, level, media prefs).
    - Plan view: week cards, lessons with resource chips, time/license/source badges, citations.
  - **Data**
    - Persist plan/lessons (`plan`, `lesson`). Skills listing endpoint.
- **Deliverables**
  - Plan creation flow: intake → plan → UI with citation rendering.
  - Skills API and UI listing.
  - Golden tests for planner JSON output.
- **Acceptance Criteria**
  - Plans meet minutes/week within ±10%.
  - Prerequisite ordering respected.
  - Deterministic JSON under fixed seeds.
- **Dependencies**
  - RAG search from Phase 1 stable.
- **Risks/Mitigations**
  - Planner hallucination: enforce tool calls for search; strict schema validation; retry on schema mismatch.

## Phase 3 — Quizzes, Progress & Replan (Week 3)
- **Objectives**
  - Generate grounded micro-quizzes per lesson. Track progress and implement re-planning.
- **Workstreams**
  - **Quiz Service (`/services/quiz`)**
    - `/generate` and `/grade`. Require grounding spans from cached snippets.
    - MCQ and short-answer; minimal rubric.
  - **Gateway (`/gateway`)**
    - `/api/quiz/lesson/:lessonId`, `/api/progress/lesson/:id`, `/api/plan/:id/replan`.
  - **Frontend (`/frontend`)**
    - Lesson page: grounded summary (from `rag-service`), quiz (2–4 Q) with grading UI.
    - Progress controls: todo/in_progress/done/skipped. Replan button with diff view.
  - **Data**
    - `progress` updates; quiz_score recorded.
- **Deliverables**
  - End-to-end quiz generation and grading.
  - Replan flow that adapts to progress deltas.
  - Basic analytics events (PostHog or CloudWatch events).
- **Acceptance Criteria**
  - ≥90% of quiz items include valid snippet grounding.
  - Replan shortens schedule or swaps long resources when behind by >20%.
  - Snapshot tests for quiz JSON items.
- **Dependencies**
  - Cached snippets from ingestion.
  - Planner-service replan path wired.
- **Risks/Mitigations**
  - LLM cost: cache summaries 24h; cap context; consider smaller models.

## Phase 4 — Auth, Observability, CI/CD to AWS, Polishing (Week 4)
- **Objectives**
  - Productionize MVP on AWS with Cognito auth, tracing, dashboards, shareable links, and demo readiness.
- **Workstreams**
  - **Auth & Security**: Cognito Hosted UI + JWT verification in Gateway; IAM roles per service; KMS encryption for S3/RDS; WAF on ALB (recommended).
  - **Observability**: OTel export to X-Ray; logs to CloudWatch; basic Grafana dashboard (optional).
  - **CI/CD**: GitHub Actions deploy to ECS Fargate (blue/green via CodeDeploy); pre-warm endpoints during CI.
  - **Product Polish**: Read-only shareable plan links; demo users; feature flags (model provider, top-k, rerank toggle).
- **Deliverables**
  - Deployed ECS services: `gateway-go`, `rag-service`, `planner-service`, `quiz-service`, `worker-celery`.
  - ALB public → Gateway; private services behind it; RDS, Qdrant (Fargate), S3, SQS live.
  - Demo script implemented.
- **Acceptance Criteria**
  - End-to-end demo < 5 minutes.
  - Traces across frontend → gateway → services.
  - Blue/green deploy zero downtime.
- **Dependencies**
  - All prior phases feature-complete and stable.
- **Risks/Mitigations**
  - Cold starts: min tasks = 1; CI prewarm.
  - Cost: small Fargate tasks (0.25 vCPU/1GB); cap top-k.

## Cross-Cutting Backlog (Parallel)
- **Schemas & Contracts**: Finalize OpenAPI and JSON Schemas in `/shared` and generate clients.
- **Testing & Evaluation**: Golden tests for RAG and planner; precision@k harness; plan realism checks.
- **Prompts**: Store prompt templates and tool schemas in `/shared/prompts`.
- **Security & Compliance**: Redact PII; secrets via Secrets Manager.
- **Performance**: Tune Qdrant HNSW (M=16, ef_search=64); rerank only for shortlists.

## Timeline & Milestones
- **Week 1**: Catalog & RAG live; ingest 150–300 items.
- **Week 2**: Planner & Plan UI.
- **Week 3**: Quizzes, progress, replan.
- **Week 4**: Auth, tracing, dashboards, ECS deploy, share links.

## Go/No-Go Gates
- **Gate A**: Search quality/latency acceptable; ingestion stable.
- **Gate B**: Plans meet budget/prereqs; UI consumable.
- **Gate C**: Quizzes grounded; replan reliable.
- **Gate D**: Deployed, observable, demo-ready.
