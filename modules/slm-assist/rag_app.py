import dspy
import ujson
import faiss
import numpy as np
from sentence_transformers import SentenceTransformer
import gradio as gr

# ────────────────────────────────────────────────
#  Configuration
# ────────────────────────────────────────────────
DATA_DIR        = "./data"
CORPUS_PATH     = f"{DATA_DIR}/ragqa_arena_tech_corpus.jsonl"
MAX_CHARS       = 6000
EMBEDDER_MODEL  = "all-MiniLM-L6-v2"
OLLAMA_MODEL    = "llama3"              # change to llama3.1, phi4, etc.
RETRIEVER_K     = 5
MAX_TOKENS      = 450
TEMPERATURE     = 0.1

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
    temperature=TEMPERATURE
)

dspy.settings.configure(lm=lm, rm=retriever)

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
    print("\n→ Starting Gradio interface... open http://127.0.0.1:7860")
    demo.launch(share=False, server_name="127.0.0.1")
