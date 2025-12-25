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

# ────────────────────────────────────────────────
#  Configuration
# ────────────────────────────────────────────────
DATA_DIR = os.getenv("SLM_DATA_DIR", "/var/lib/slm-assist")
CORPUS_PATH = os.path.join(DATA_DIR, "ragqa_arena_tech_corpus.jsonl")
MAX_CHARS       = 6000
EMBEDDER_MODEL  = "all-MiniLM-L6-v2"
RETRIEVER_K     = 5
MAX_TOKENS      = 450
TEMPERATURE     = 0.1
OLLAMA_HOST     = "http://127.0.0.1:11434"

# ────────────────────────────────────────────────
#  Auto-detect Ollama model at startup
# ────────────────────────────────────────────────
def detect_ollama_model(max_retries=20, retry_delay=5):
    """Query Ollama /api/tags and return the first available model name."""
    preferred = os.getenv("OLLAMA_MODEL")  # Nix can override via env

    if preferred:
        print(f"→ Using preferred model from environment: {preferred}")
        return preferred

    print("→ No OLLAMA_MODEL env set → auto-detecting from Ollama...")
    
    for attempt in range(1, max_retries + 1):
        try:
            response = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=10)
            response.raise_for_status()
            data = response.json()
            models = data.get("models", [])
            
            if not models:
                print("→ No models found in Ollama yet.")
            else:
                # Take the first model (usually the only one in baked offline setup)
                first_model = models[0]["name"]
                print(f"→ Auto-detected model: {first_model} (attempt {attempt}/{max_retries})")
                return first_model

        except requests.RequestException as e:
            print(f"→ Ollama not ready yet (attempt {attempt}/{max_retries}): {e}")
        
        if attempt < max_retries:
            time.sleep(retry_delay)
    
    print("Error: Could not detect any Ollama model after retries.")
    print("  → Check: ollama.service status, model baking (/var/lib/ollama/models), tmpfiles.rules")
    sys.exit(1)

# Run detection once at startup
OLLAMA_MODEL = detect_ollama_model()

# ────────────────────────────────────────────────
#  Load corpus & build FAISS index (runs once)
# ────────────────────────────────────────────────
print("Loading corpus & building FAISS index...")
with open(CORPUS_PATH) as f:
    corpus = [ujson.loads(line)['text'][:MAX_CHARS] for line in f]

embedder = SentenceTransformer(EMBEDDER_MODEL)
corpus_emb = embedder.encode(corpus, normalize_embeddings=True, show_progress_bar=True)
dim = corpus_emb.shape[1]
index = faiss.IndexFlatIP(dim)
index.add(corpus_emb.astype('float32'))
print(f"→ Index ready with {len(corpus)} passages")

# ────────────────────────────────────────────────
#  Custom retriever compatible with DSPy
# ────────────────────────────────────────────────
class LocalRetriever(dspy.Retrieve):
    def __init__(self, embedder, index, corpus, k=RETRIEVER_K):
        super().__init__(k=k)
        self.embedder = embedder
        self.index    = index
        self.corpus   = corpus

    def forward(self, query_or_queries, k=None, **kwargs):
        k = k or self.k
        queries = [query_or_queries] if isinstance(query_or_queries, str) else query_or_queries
        all_passages = []

        for q in queries:
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
    request_timeout=600,  # 10 minutes - safe for slow USB 2.0 load
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
#  Gradio Chat Interface
# ────────────────────────────────────────────────
def rag_chat(message, history):
    if not message.strip():
        return "", history

    try:
        result = rag(message)
        answer = result.answer
        sources = "\n\n**Retrieved contexts** (top matches):\n" + \
                  "\n".join(f"- {c[:180]}..." for c in result.context)
        return answer + sources, history + [(message, answer + sources)]
    except Exception as e:
        return f"Error: {str(e)}", history

with gr.Blocks(title="DSPy Local RAG • Ollama + FAISS") as demo:
    gr.Markdown("""
    # Local DSPy RAG Chat
    Ask questions about the tech corpus. Powered by Ollama + sentence-transformers + FAISS.
    """)

    chatbot = gr.Chatbot(height=500)
    msg = gr.Textbox(placeholder="Ask anything...", label="Your question")
    clear = gr.Button("Clear")

    msg.submit(rag_chat, [msg, chatbot], [msg, chatbot])
    clear.click(lambda: ([], []), None, [chatbot, chatbot])

if __name__ == "__main__":
    print(f"\n→ Starting Gradio interface with model: {OLLAMA_MODEL}")
    print("→ Open http://127.0.0.1:7860 in your browser")
    demo.launch(share=False, server_name="127.0.0.1")
