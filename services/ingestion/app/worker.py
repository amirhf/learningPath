import os
from celery import Celery

# SQS broker URL example: sqs://<aws_access_key_id>:<aws_secret_access_key>@
# In ECS, the SDK uses IAM; Celery will pick up credentials via boto3 under the hood.

broker_url = os.getenv("CELERY_BROKER_URL", "sqs://")
backend_url = os.getenv("CELERY_RESULT_BACKEND", None)

app = Celery("ingestion", broker=broker_url, backend=backend_url)

# Minimal Celery config for SQS
app.conf.update(
    task_default_queue=os.getenv("CELERY_QUEUE", "learning-path-dev-ingest"),
    broker_transport_options={
        "region": os.getenv("AWS_REGION", "us-east-1"),
        # Visibility timeout should be >= task max runtime
        "visibility_timeout": int(os.getenv("VISIBILITY_TIMEOUT", "300")),
    },
    task_acks_late=True,
    worker_prefetch_multiplier=1,
)

@app.task
def ping(msg: str = "ok"):
    return {"pong": msg}

if __name__ == "__main__":
    # Local dev: start a worker
    app.worker_main(argv=["worker", "-l", "info"]) 
