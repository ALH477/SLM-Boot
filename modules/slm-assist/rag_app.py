import dspy
import ujson
import faiss
import numpy as np
from sentence_transformers import SentenceTransformer
import gradio as gr
import os
import requests
import sys
import time
import logging
from pathlib import Path
from datetime import datetime
import threading
import hashlib

# ────────────────────────────────────────────────
#  Logging Setup
# ────────────────────────────────────────────────
LOG_DIR = os.getenv("SLM_LOG_DIR", "/var/log/slm-assist")
Path(LOG_DIR).mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.join(LOG_DIR, 'slm-assist.log')),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# ────────────────────────────────────────────────
#  Configuration
# ────────────────────────────────────────────────
DATA_DIR = os.getenv("SLM_DATA_DIR", "/var/lib/slm-assist")
CORPUS_PATH = os.path.join(DATA_DIR, "ragqa_arena_tech_corpus.jsonl")
INDEX_PATH = os.path.join(DATA_DIR, "faiss.index")
CORPUS_HASH_PATH = os.path.join(DATA_DIR, ".corpus_hash")

MAX_CHARS       = 6000
EMBEDDER_MODEL  = "all-MiniLM-L6-v2"
RETRIEVER_K     = 5
MAX_TOKENS      = 450
TEMPERATURE     = 0.1
OLLAMA_HOST     = "http://127.0.0.1:11434"

# Input validation limits
MAX_QUERY_LENGTH = 2000
MIN_QUERY_LENGTH = 1

# ────────────────────────────────────────────────
#  Metrics tracking
# ────────────────────────────────────────────────
class MetricsCollector:
    def __init__(self):
        self.query_count = 0
        self.error_count = 0
        self.total_latency = 0.0
        self.lock = threading.Lock()
    
    def record_query(self, latency_seconds, success=True):
        with self.lock:
            self.query_count += 1
            self.total_latency += latency_seconds
            if not success:
                self.error_count += 1
    
    def get_stats(self):
        with self.lock:
            avg_latency = self.total_latency / self.query_count if self.query_count > 0 else 0
            return {
                "total_queries": self.query_count,
                "errors": self.error_count,
                "avg_latency_sec": round(avg_latency, 2),
                "success_rate": round((self.query_count - self.error_count) / self.query_count * 100, 2) if self.query_count > 0 else 100
            }

metrics = MetricsCollector()

# ────────────────────────────────────────────────
#  Auto-detect Ollama model at startup
# ────────────────────────────────────────────────
def detect_ollama_model(max_retries=20, retry_delay=5):
    """Query Ollama /api/tags and return the first available model name."""
    preferred = os.getenv("OLLAMA_MODEL")

    if preferred:
        logger.info(f"Using preferred model from environment: {preferred}")
        return preferred

    logger.info("No OLLAMA_MODEL env set → auto-detecting from Ollama...")
    
    for attempt in range(1, max_retries + 1):
        try:
            response = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=10)
            response.raise_for_status()
            
            try:
                data = response.json()
            except ValueError as e:
                logger.warning(f"Invalid JSON from Ollama (attempt {attempt}/{max_retries}): {e}")
                continue
            
            models = data.get("models", [])
            
            if not models:
                logger.info(f"No models found in Ollama yet (attempt {attempt}/{max_retries})")
            else:
                try:
                    first_model = models[0]["name"]
                    logger.info(f"Auto-detected model: {first_model} (attempt {attempt}/{max_retries})")
                    return first_model
                except (KeyError, IndexError, TypeError) as e:
                    logger.warning(f"Malformed model data: {e} (attempt {attempt}/{max_retries})")
                    continue

        except requests.RequestException as e:
            logger.warning(f"Ollama not ready yet (attempt {attempt}/{max_retries}): {e}")
        
        if attempt < max_retries:
            time.sleep(retry_delay)
    
    logger.error("Could not detect any Ollama model after all retries")
    logger.error("Troubleshooting:")
    logger.error("  1. Check: systemctl status ollama.service")
    logger.error("  2. Verify: ls -la /var/lib/ollama/models/manifests/")
    logger.error("  3. Check: tmpfiles.d rules executed correctly")
    logger.error("  4. Try: curl http://127.0.0.1:11434/api/tags")
    sys.exit(1)

OLLAMA_MODEL = detect_ollama_model()

# ────────────────────────────────────────────────
#  Index persistence utilities
# ────────────────────────────────────────────────
def compute_corpus_hash(corpus_path):
    """Compute SHA256 hash of corpus file to detect changes."""
    sha256_hash = hashlib.sha256()
    with open(corpus_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def should_rebuild_index():
    """Check if we need to rebuild the index."""
    if not os.path.exists(INDEX_PATH):
        logger.info("No existing index found - will build new index")
        return True
    
    if not os.path.exists(CORPUS_HASH_PATH):
        logger.info("No corpus hash found - will rebuild index")
        return True
    
    current_hash = compute_corpus_hash(CORPUS_PATH)
    with open(CORPUS_HASH_PATH, 'r') as f:
        saved_hash = f.read().strip()
    
    if current_hash != saved_hash:
        logger.info("Corpus has changed - will rebuild index")
        return True
    
    logger.info("Using cached index (corpus unchanged)")
    return False

# ────────────────────────────────────────────────
#  Load corpus & build/load FAISS index
# ────────────────────────────────────────────────
logger.info(f"Loading corpus from: {CORPUS_PATH}")

if not os.path.exists(CORPUS_PATH):
    logger.error(f"Corpus file not found at {CORPUS_PATH}")
    logger.error("Expected path (from tmpfiles):", CORPUS_PATH)
    logger.error("Check: systemctl status systemd-tmpfiles-setup.service")
    sys.exit(1)

try:
    with open(CORPUS_PATH) as f:
        corpus = [ujson.loads(line)['text'][:MAX_CHARS] for line in f]
    logger.info(f"Loaded {len(corpus)} passages from corpus")
except Exception as e:
    logger.error(f"Failed to load corpus: {e}", exc_info=True)
    sys.exit(1)

logger.info("Initializing embedder...")
embedder = SentenceTransformer(EMBEDDER_MODEL)

# Load or build index
if should_rebuild_index():
    logger.info("Building FAISS index (this may take a while)...")
    corpus_emb = embedder.encode(corpus, normalize_embeddings=True, show_progress_bar=True)
    dim = corpus_emb.shape[1]
    index = faiss.IndexFlatIP(dim)
    index.add(corpus_emb.astype('float32'))
    
    # Save index and hash
    faiss.write_index(index, INDEX_PATH)
    logger.info(f"Saved index to {INDEX_PATH}")
    
    current_hash = compute_corpus_hash(CORPUS_PATH)
    with open(CORPUS_HASH_PATH, 'w') as f:
        f.write(current_hash)
    logger.info("Saved corpus hash")
else:
    logger.info("Loading cached FAISS index...")
    index = faiss.read_index(INDEX_PATH)
    dim = index.d

logger.info(f"Index ready with {len(corpus)} passages, dimension={dim}")

# ────────────────────────────────────────────────
#  Thread-safe retriever
# ────────────────────────────────────────────────
class LocalRetriever(dspy.Retrieve):
    def __init__(self, embedder, index, corpus, k=RETRIEVER_K):
        super().__init__(k=k)
        self.embedder = embedder
        self.index    = index
        self.corpus   = corpus
        self.lock     = threading.Lock()

    def forward(self, query_or_queries, k=None, **kwargs):
        k = k or self.k
        queries = [query_or_queries] if isinstance(query_or_queries, str) else query_or_queries
        all_passages = []

        for q in queries:
            with self.lock:
                q_emb = self.embedder.encode(q, normalize_embeddings=True).astype('float32')
                D, I = self.index.search(q_emb.reshape(1, -1), k)
            
            passages = [self.corpus[i] for i in I[0] if i != -1]
            all_passages.append(passages)

        if len(all_passages) == 1:
            return dspy.Prediction(passages=all_passages[0])
        return [dspy.Prediction(passages=p) for p in all_passages]

retriever = LocalRetriever(embedder, index, corpus, k=RETRIEVER_K)

# ────────────────────────────────────────────────
#  DSPy setup
# ────────────────────────────────────────────────
lm = dspy.OllamaLocal(
    model=OLLAMA_MODEL,
    model_type='text',
    max_tokens=MAX_TOKENS,
    temperature=TEMPERATURE,
    request_timeout=600,
)

dspy.settings.configure(lm=lm, rm=retriever)

# ────────────────────────────────────────────────
#  RAG Module
# ────────────────────────────────────────────────
class RAG(dspy.Module):
    def __init__(self, num_passages=RETRIEVER_K):
        super().__init__()
        self.retrieve = dspy.Retrieve(k=num_passages)
        self.generate = dspy.ChainOfThought("context, question -> answer")

    def forward(self, question):
        context = self.retrieve(question).passages
        pred = self.generate(context=context, question=question)
        return dspy.Prediction(context=context, answer=pred.answer)

rag = RAG()

# ────────────────────────────────────────────────
#  Input validation and formatting
# ────────────────────────────────────────────────
def validate_input(message):
    """Validate user input with helpful error messages."""
    if not message or not message.strip():
        return False, "Please enter a question."
    
    if len(message) < MIN_QUERY_LENGTH:
        return False, "Query too short. Please provide more detail."
    
    if len(message) > MAX_QUERY_LENGTH:
        return False, f"Query too long (max {MAX_QUERY_LENGTH} characters). Please shorten your question."
    
    return True, None

def smart_truncate(text, max_len=180):
    """Truncate text without cutting mid-word."""
    if len(text) <= max_len:
        return text
    
    truncated = text[:max_len]
    last_space = truncated.rfind(' ')
    
    if last_space > max_len * 0.8:
        return truncated[:last_space] + '...'
    return truncated + '...'

# ────────────────────────────────────────────────
#  Gradio Chat Interface
# ────────────────────────────────────────────────
def rag_chat(message, history):
    """
    Process user query with RAG system.
    Note: This implementation is stateless - each query is independent.
    """
    start_time = time.time()
    
    # Input validation
    valid, error_msg = validate_input(message)
    if not valid:
        return error_msg, history
    
    try:
        logger.info(f"Processing query (length={len(message)})")
        result = rag(message)
        answer = result.answer
        
        # Smart truncation of context
        sources = "\n\n**Retrieved contexts** (top matches):\n" + \
                  "\n".join(f"- {smart_truncate(c, 180)}" for c in result.context)
        
        full_response = answer + sources
        
        # Record metrics
        latency = time.time() - start_time
        metrics.record_query(latency, success=True)
        logger.info(f"Query processed successfully in {latency:.2f}s")
        
        return full_response, history + [(message, full_response)]
        
    except Exception as e:
        latency = time.time() - start_time
        metrics.record_query(latency, success=False)
        
        logger.error(f"Error processing query: {e}", exc_info=True)
        
        user_message = "I encountered an error processing your question. Please try:\n"
        user_message += "• Rephrasing your question\n"
        user_message += "• Making your question more specific\n"
        user_message += "• Checking if the service is running properly"
        
        return user_message, history

def get_stats():
    """Return current system statistics."""
    stats = metrics.get_stats()
    return f"""
    **System Statistics:**
    - Total Queries: {stats['total_queries']}
    - Errors: {stats['errors']}
    - Success Rate: {stats['success_rate']}%
    - Avg Latency: {stats['avg_latency_sec']}s
    - Model: {OLLAMA_MODEL}
    - Corpus Size: {len(corpus)} passages
    """

# ────────────────────────────────────────────────
#  Gradio Interface
# ────────────────────────────────────────────────
with gr.Blocks(title="DSPy Local RAG • Ollama + FAISS") as demo:
    gr.Markdown("""
    # Local DSPy RAG Chat
    Ask questions about the tech corpus. Powered by Ollama + sentence-transformers + FAISS.
    
    **Note**: Each query is independent (no conversation memory).
    """)

    with gr.Row():
        with gr.Column(scale=3):
            chatbot = gr.Chatbot(height=500, label="Chat")
            msg = gr.Textbox(
                placeholder=f"Ask anything (max {MAX_QUERY_LENGTH} chars)...",
                label="Your question",
                max_lines=3
            )
            with gr.Row():
                submit = gr.Button("Send", variant="primary")
                clear = gr.Button("Clear")
        
        with gr.Column(scale=1):
            stats_display = gr.Markdown(get_stats())
            refresh_stats = gr.Button("Refresh Stats")

    msg.submit(rag_chat, [msg, chatbot], [msg, chatbot])
    submit.click(rag_chat, [msg, chatbot], [msg, chatbot])
    clear.click(lambda: ([], []), None, [chatbot, chatbot])
    refresh_stats.click(lambda: get_stats(), None, stats_display)

if __name__ == "__main__":
    logger.info(f"Starting Gradio interface with model: {OLLAMA_MODEL}")
    logger.info(f"Listening on http://127.0.0.1:7860")
    logger.info(f"Logs: {LOG_DIR}/slm-assist.log")
    
    try:
        demo.launch(
            share=False,
            server_name="127.0.0.1",
            server_port=7860,
            show_error=True
        )
    except OSError as e:
        if "address already in use" in str(e).lower():
            logger.error(f"Port 7860 is already in use. Is another instance running?")
            logger.error("Try: lsof -i :7860  or  systemctl status slm-assist")
        else:
            logger.error(f"Failed to start server: {e}")
        sys.exit(1)
