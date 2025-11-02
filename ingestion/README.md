# Ingestion (Celery + SQS)

Seed list → fetch metadata/snippets → embed (e5-base) → Qdrant upsert → Postgres write → optional S3 snippet.
Nightly popularity refresh. Retry/backoff + poison queue.
