Perfect—let’s lock the scope and design the MVP around **Option B (skill-graph + RAG)** with a touch of **Option A (fast path to demo)**, targeted for **AWS**. Below is a crisp, *build-ready* plan you can hand to your repo and start implementing.

# 1) MVP Objective

Showcase **AI integration + RAG + light agent orchestration** that turns:

* a user goal (e.g., “event-driven microservices interview in 4 weeks”)
* constraints (hours/week, level, media prefs)
  into a **sequenced learning path** with **curated resources**, **micro-quizzes**, **progress tracking**, and **auto-replanning**.

# 2) Final Tech Choices (confirmed)

* **Frontend:** Next.js (TS), Tailwind, shadcn/ui, TanStack Query
* **Gateway (Edge/API):** **Go (Gin/Fiber)** — auth, rate-limits, request shaping, tracing, fan-out
* **AI Services:** **FastAPI (Python)** microservices

  * `rag-service` (retrieval, rerank, summarization)
  * `planner-service` (path sequencing, replan)
  * `quiz-service` (quiz generation & grading)
* **LLM Generation:** **OpenRouter** (hosted SOTA; pluggable)
* **Embeddings:** **e5-base** (intfloat/e5-base or e5-base-v2) via local **HF Transformers**
* **Vector DB:** **Qdrant** (start from day 1)
* **Relational DB:** **Postgres (RDS)** for users/goals/plans/progress/skills
* **Object Store:** **S3** (resource snapshots, small cached snippets)
* **Async Jobs:** **Celery on SQS** (kombu SQS transport) for ingestion, re-scoring, re-planning
* **Auth:** **Cognito** (User Pools + Hosted UI)
* **Secrets/Config:** **AWS Secrets Manager + SSM Parameter Store**
* **Observability:** OpenTelemetry → **AWS X-Ray** (traces), **CloudWatch** (logs/metrics), optional **Amazon Managed Grafana**
* **CI/CD:** GitHub Actions → **ECS Fargate** deploy (blue/green via CodeDeploy)
* **Networking:** VPC, ALB (public) → Go gateway → private services

> Optional later: **Neo4j** for richer prerequisite graphs; for MVP we’ll model prerequisites in Postgres adjacency lists.

---

# 3) High-Level Architecture

**Client (Next.js)**
⬇️ HTTPS (JWT from Cognito)
**Go Gateway**

* AuthN/AuthZ (Cognito JWT verify)
* Rate limiting (token bucket; Redis optional later)
* Request shaping & schema validation (Zod-style in Go)
* Fan-out to AI services; propagate trace context
  ⬇️
  **Python Services (FastAPI)**
* `rag-service` → Qdrant (dense search w/ e5), rerank (bge-reranker-base), S3 snippets
* `planner-service` → sequences units/lessons using skills + prerequisites + user budget
* `quiz-service` → generates 2–4 Q micro-quizzes per lesson, auto-grades MCQ/short answers
  ⬇️
  **Data Layer**
* **Qdrant**: `resources` collection (dense vectors + payload: skills, duration, level, license, provider, recency)
* **Postgres**: users, goals, plans, lessons, progress, skills, edges(prereq)
* **S3**: cached metadata & tiny content snippets (for quiz generation grounding)
* **SQS**: ingestion & periodic re-planning queues

---

# 4) Minimal Data Model (DDL sketch)

```sql
-- Skills & prerequisites
CREATE TABLE skill (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT UNIQUE,
  level_hint INT DEFAULT 0  -- 0=basic,1=intermediate,2=advanced
);

CREATE TABLE skill_edge (
  from_skill UUID REFERENCES skill(id) ON DELETE CASCADE,
  to_skill   UUID REFERENCES skill(id) ON DELETE CASCADE,
  PRIMARY KEY (from_skill, to_skill)   -- from -> to means "from" is a prerequisite of "to"
);

-- Content catalog (relational metadata; vectors live in Qdrant)
CREATE TABLE resource (
  id UUID PRIMARY KEY,
  title TEXT NOT NULL,
  url TEXT NOT NULL,
  provider TEXT,
  license TEXT,
  duration_min INT,
  level INT,                 -- 0..2
  skills UUID[] NOT NULL,    -- coarse tags; normalized later if preferred
  recency_date DATE,
  s3_cache_key TEXT          -- optional; cached snippet for quiz/RAG grounding
);

-- Users & goals
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
  prefs JSONB                 -- media prefs, constraints
);

-- Plans & lessons
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

-- Progress & quizzes
CREATE TABLE progress (
  id UUID PRIMARY KEY,
  lesson_id UUID REFERENCES lesson(id),
  status TEXT CHECK (status IN ('todo','in_progress','done','skipped')),
  actual_minutes INT,
  quiz_score NUMERIC
);
```

**Qdrant collection: `resources`**

* vector: e5-base (768 dims)
* payload fields: `resource_id`, `skills` (string list), `level`, `duration_min`, `provider`, `license`, `recency_date`, `popularity`, `media_type`

---

# 5) Ingestion Pipeline (SQS + Celery)

* Seed a **curated list** of CC-friendly & official docs for the domain:

  * Kafka (Apache docs), event-driven patterns (microservices.io—link out; don’t cache bodies), Redis Streams (redis.io), Postgres WAL/CDC (postgresql.org), Go Concurrency (go.dev), Cloud design (AWS Prescriptive Guidance—link out).
* For each URL: fetch **metadata only** + short safe snippet (first 2–3 paragraphs if license allows), compute **e5 embeddings**, write:

  * Postgres row in `resource`
  * Upsert into Qdrant (payload + vector)
  * Optional: store snippet in S3 as a tiny text object
* Nightly job re-scores `popularity` (clicks, completion rates) and refreshes embeddings for changed docs.

---

# 6) Retrieval & Ranking

**Query pipeline (rag-service):**

1. Make an *instructional* query: `"Retrieve concise, foundational resources for: {skills} at {level}, target duration ≤ {cap}, prefer {media}"`.
2. **Embed** with e5-base → **Qdrant search** (top-k=20, HNSW + cosine) with **payload filters** (level ≤ user level, license in allowlist).
3. **Rerank** with **bge-reranker-base** (cross-encoder) down to top-5.
4. Return compact JSON cards (title, URL, why-picked, est_time, license, skills matched).

> For long-form LLM answers (summaries, lesson outlines), we ground with the 2–3 top resources’ cached snippets and always **cite** (URLs).

---

# 7) Agent Orchestration (lightweight, JSON-tool style)

A single **Planner Agent** (LLM via OpenRouter) that can call these tools:

* `search_resources(query, skill_targets[], max_time, level, media_prefs) -> ResourceCard[]`
* `sequence_plan(skills[], prereq_graph, hours_per_week, target_date) -> Weeks[Lessons[]]`
* `generate_quiz(resources[], level) -> Quiz{items: [MCQ|ShortAnswer]}`
* `replan(plan, progress_delta, remaining_weeks) -> UpdatedPlan`

**Flow**

1. Intake → Planner calls `sequence_plan` using skill graph + budget.
2. For each lesson, Planner calls `search_resources` to pick 1–2 best items.
3. For each lesson, `quiz-service` creates 2–4 Qs grounded on cached snippets.
4. On “behind schedule,” Planner calls `replan` to compress: swap long reads for shorter talks, reduce expansion topics, keep prerequisites.

---

# 8) API Surface (Go Gateway routes)

```
POST /api/intake                  -> create goal
POST /api/plan                    -> invoke Planner; returns plan + lessons
GET  /api/plan/:id                -> plan detail
POST /api/plan/:id/replan         -> re-plan from progress deltas
POST /api/quiz/lesson/:lessonId   -> generate quiz now (idempotent)
POST /api/progress/lesson/:id     -> update status/actual_minutes/quiz_score
GET  /api/resources/search        -> pass-through to RAG search (for manual browsing)
GET  /api/skills                  -> list skills for domain (with prereqs)
```

**Gateway responsibilities**

* Validate JWT (Cognito), enforce per-user rate limits (burst + sustained)
* Attach `traceparent` headers; log request IDs
* Fan-out orchestration (e.g., /plan triggers `planner-service` which internally calls `rag-service`)
* Return **deterministic JSON** suitable for the Next.js UI

---

# 9) Prompting (concise, testable)

**Planner system prompt (snippet)**

> You design compact learning plans for software engineers. Respect prerequisites, time budgets, and user level. Prefer official docs & CC resources. Output strictly in the provided JSON schema. Avoid hallucinations; if uncertain, ask the `search_resources` tool.

**Quiz generation guardrails**

* Require **verbatim grounding spans** from cached snippets for answer keys
* Disallow questions if grounding < N tokens

---

# 10) Frontend UX (Next.js)

* **Intake form:** goal, deadline, hours/week, level, medium prefs
* **Plan view:** week cards → lessons (resource chips with badges: time, license, source)
* **Lesson page:** why-chosen, quick summary (LLM), quiz (2–4 Q), mark done
* **Progress bar & Replan button:** if behind by >20%, show suggestion diff
* **Shareable plan link** (read-only) for portfolio reviewers

---

# 11) AWS Deployment Topology

* **ECS Fargate services** in private subnets:

  * `gateway-go`, `rag-service`, `planner-service`, `quiz-service`, `worker-celery`
* **Qdrant**:

  * Option A: **Qdrant Cloud** (fastest)
  * Option B: Self-hosted on Fargate with EBS gp3; enable snapshots to S3
* **RDS Postgres** (Multi-AZ), **S3** for snippets, **SQS** queues (`ingest`, `replan`)
* **ALB** (public) → `gateway-go` target group
* **Cognito** for auth; **ACM** certs via Route53; **WAF** optional
* **IAM**: task roles per service; least privilege to S3/SQS/Secrets Manager
* **OTel**: sidecar or SDK export to **X-Ray**; logs → **CloudWatch**
* **CI/CD**: GitHub Actions build containers → ECR → deploy to ECS (blue/green)

---

# 12) Milestones (4 weeks, part-time)

**Week 1 – Searchable Catalog**

* DDL, Qdrant up, e5 embeddings wired
* Ingest 150–300 resources (domain seed list)
* `/resources/search` live with filters + rerank

**Week 2 – Planner & Plan UI**

* Skill graph + prerequisites (PG)
* `planner-service` JSON tool calls; plan creation end-to-end
* Plan & lesson UIs; citations

**Week 3 – Quizzes & Progress**

* `quiz-service` grounded MCQ/short; grading
* Progress model + “Replan” path
* Basic analytics events (PostHog or CloudWatch)

**Week 4 – Hardening & AWS polish**

* Cognito auth, rate limits, tracing, dashboards
* Read-only share links; demo script; seed demo users
* Cost pass & feature flags (model provider, top-k, rerank on/off)

---

# 13) Demo Script (for portfolio reviewers)

1. Login (Cognito demo user). Create goal: “Event-driven microservices interview in 4 weeks, 6h/week, intermediate.”
2. Instantly show **Plan** with 4 weeks, each 3–4 lessons. Every lesson shows **Why this** + **time** + **citations**.
3. Open a lesson → 2-minute LLM **summary** grounded in sources → **quiz** (2–4 Q) → submit → instant grading.
4. Mark a lesson “skipped” → **Replan** → watch compressed schedule and swapped shorter resources.
5. Share read-only link.

---

# 14) Evaluation & Safety

* **No PII in prompts**, redact emails/usernames
* **Deterministic tests** for tools (golden JSON snapshots)
* **Offline eval set**: 10 target skills, expected resource picks (precision@k), plan realism rubric (minutes/week), quiz validity (grounded-rate)

---

# 15) What I’ll prepare next (once you say “go”)

* Service-by-service folder structure & Makefiles
* Qdrant collection schema + HNSW params
* Ingestion scripts (Python) with a seed resource list
* Concrete **OpenAPI** specs for gateway & services
* Prompt templates + JSON Schemas
* GitHub Actions YAMLs (build, push, deploy)
* Terraform stubs (VPC, ECS, RDS, SQS, Cognito, ALB) — optional for v1

---

If this matches your vision, I’ll produce the **detailed API contracts**, **prompt JSON schemas**, **Qdrant payload schema**, and **initial seed list** (50–80 URLs) so you can open the repo and start coding.
