from fastapi import FastAPI

app = FastAPI(title="rag-service")

@app.get("/healthz")
def healthz():
    return {"status": "ok"}

@app.post("/embed")
def embed():
    return {"todo": "implement embeddings"}

@app.post("/search")
def search():
    return {"todo": "implement qdrant search"}

@app.post("/summarize")
def summarize():
    return {"todo": "implement summarization"}
