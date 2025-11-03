import os
import logging
from typing import List, Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from qdrant_client import QdrantClient
from qdrant_client.models import (
    Distance,
    VectorParams,
    Filter,
    FieldCondition,
    Range,
    MatchAny,
)
from sentence_transformers import SentenceTransformer, CrossEncoder


logger = logging.getLogger("rag-service")
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))

QDRANT_URL = os.getenv("QDRANT_URL", "http://localhost:6333")
QDRANT_COLLECTION = os.getenv("QDRANT_COLLECTION", "resources")
ENABLE_RERANK = os.getenv("ENABLE_RERANK", "true").lower() not in ("0", "false", "no")

app = FastAPI(title="rag-service")


class EmbedRequest(BaseModel):
    texts: List[str] = Field(default_factory=list)


class EmbedResponse(BaseModel):
    vectors: List[List[float]]


class SearchFilters(BaseModel):
    level_lte: Optional[int] = None
    license_in: Optional[List[str]] = None
    duration_lte: Optional[int] = None
    media_in: Optional[List[str]] = None


class SearchRequest(BaseModel):
    query: str
    top_k: int = 20
    filters: Optional[SearchFilters] = None


class ResourceCard(BaseModel):
    resource_id: str
    title: Optional[str] = None
    url: Optional[str] = None
    why: Optional[str] = None
    est_minutes: Optional[int] = None
    skills: Optional[List[str]] = None
    score: Optional[float] = None


class SearchResponse(BaseModel):
    hits: List[ResourceCard]


class SummarizeRequest(BaseModel):
    resource_ids: List[str]


class SummarizeResponse(BaseModel):
    summary: str
    citations: List[str]


# Globals initialised on startup
_qdrant: Optional[QdrantClient] = None
_embedder: Optional[SentenceTransformer] = None
_reranker: Optional[CrossEncoder] = None
_embedder_ready = False
_reranker_ready = False


def _ensure_collection():
    assert _qdrant is not None
    try:
        _qdrant.get_collection(QDRANT_COLLECTION)
    except Exception:
        logger.info("Creating Qdrant collection '%s'", QDRANT_COLLECTION)
        _qdrant.create_collection(
            collection_name=QDRANT_COLLECTION,
            vectors_config=VectorParams(size=768, distance=Distance.COSINE),
        )


@app.on_event("startup")
def on_startup():
    global _qdrant, _embedder, _reranker
    _qdrant = QdrantClient(url=QDRANT_URL)
    _ensure_collection()
    # e5-base for embeddings
    _embedder = SentenceTransformer("intfloat/e5-base")
    global _embedder_ready
    _embedder_ready = True
    logger.info("Embedder loaded: intfloat/e5-base")
    # bge reranker for cross-encoder rerank
    if ENABLE_RERANK:
        _reranker = CrossEncoder("BAAI/bge-reranker-base")
        global _reranker_ready
        _reranker_ready = True
        logger.info("Reranker loaded: BAAI/bge-reranker-base")
    else:
        logger.info("Reranker disabled via ENABLE_RERANK=false")
    logger.info("Startup complete: Qdrant at %s, collection '%s'", QDRANT_URL, QDRANT_COLLECTION)


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    return {
        "embedder_ready": _embedder_ready,
        "reranker_ready": _reranker_ready,
        "reranker_enabled": ENABLE_RERANK,
    }


@app.post("/embed", response_model=EmbedResponse)
def embed(req: EmbedRequest):
    if _embedder is None:
        raise HTTPException(status_code=503, detail="Embedder not initialized")
    # e5 recommends prefixing with "query: " or "passage: "; we expose generic embedding
    texts = [t if t.startswith("query:") or t.startswith("passage:") else f"passage: {t}" for t in req.texts]
    vectors = _embedder.encode(texts, normalize_embeddings=True).tolist()
    return EmbedResponse(vectors=vectors)


def _to_filter(sf: Optional[SearchFilters]) -> Optional[Filter]:
    if not sf:
        return None
    must = []
    if sf.level_lte is not None:
        must.append(FieldCondition(key="level", range=Range(lte=sf.level_lte)))
    if sf.license_in:
        must.append(FieldCondition(key="license", match=MatchAny(any=sf.license_in)))
    if sf.duration_lte is not None:
        must.append(FieldCondition(key="duration_min", range=Range(lte=sf.duration_lte)))
    if sf.media_in:
        must.append(FieldCondition(key="media_type", match=MatchAny(any=sf.media_in)))
    return Filter(must=must) if must else None


@app.post("/search", response_model=SearchResponse)
def search(req: SearchRequest):
    if _embedder is None or _qdrant is None or _reranker is None:
        raise HTTPException(status_code=503, detail="Service not initialized")

    query_text = req.query if req.query.startswith("query:") else f"query: {req.query}"
    qvec = _embedder.encode([query_text], normalize_embeddings=True)[0]

    qfilter = _to_filter(req.filters)
    try:
        raw_hits = _qdrant.search(
            collection_name=QDRANT_COLLECTION,
            query_vector=qvec,
            query_filter=qfilter,
            limit=max(1, req.top_k),
            with_payload=True,
            with_vectors=False,
        )
    except Exception as e:
        logger.exception("Qdrant search failed")
        raise HTTPException(status_code=500, detail=f"Qdrant search error: {e}")

    # Prepare texts for reranking
    pairs = []
    for h in raw_hits:
        payload = h.payload or {}
        title = str(payload.get("title", ""))
        url = str(payload.get("url", ""))
        context = title + " " + url
        pairs.append((req.query, context))

    rerank_scores: List[float] = []
    if ENABLE_RERANK and _reranker is not None and pairs:
        rerank_scores = _reranker.predict(pairs).tolist()

    # Attach rerank scores and sort
    enriched = []
    for i, h in enumerate(raw_hits):
        payload = h.payload or {}
        skills = payload.get("skills") or []
        why = None
        if skills:
            why = "Matched skills: " + ", ".join(skills[:5])
        enriched.append(
            ResourceCard(
                resource_id=str(payload.get("resource_id") or payload.get("id") or h.id),
                title=payload.get("title"),
                url=payload.get("url"),
                why=why,
                est_minutes=payload.get("duration_min"),
                skills=skills,
                score=float(rerank_scores[i]) if i < len(rerank_scores) else float(h.score or 0.0),
            )
        )
    enriched.sort(key=lambda x: x.score or 0.0, reverse=True)
    top = enriched[:5]
    return SearchResponse(hits=top)


@app.post("/summarize", response_model=SummarizeResponse)
def summarize(req: SummarizeRequest):
    # Stub: implement grounded summarization later
    return SummarizeResponse(summary="TODO", citations=[])
