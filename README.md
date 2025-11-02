# Learning Path Designer (MVP)

Cloud-native MVP that turns a user goal + constraints into a sequenced plan with curated resources, grounded summaries, micro-quizzes, progress tracking, and adaptive re-planning.

- Frontend: Next.js (TS), Tailwind, shadcn/ui, TanStack Query
- Gateway: Go (Gin)
- Services: FastAPI (rag, planner, quiz)
- Data: Postgres, Qdrant (self-hosted on ECS Fargate), S3
- Jobs: Celery on SQS
- Auth: Cognito
- Observability: OTel → X-Ray, CloudWatch

See `planning/implementation_plan.md` for phases and milestones.
