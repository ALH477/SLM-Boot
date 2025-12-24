# scripts/rag_dataset_prep.py
"""
Production-Ready RAG Dataset Preparation Tool

Supports:
- Directories (recursive)
- Single files (.html, .htm, .pdf, .md, .txt, .jsonl)
- URLs (web pages)
- JSONL files (DSPy/RAG style: each line has a "text" field or similar)

Output: 
- Semantic chunks saved as .md files in the output directory structure
- Optional JSONL corpus file for direct use with RAG systems
"""

import os
import argparse
import requests
from bs4 import BeautifulSoup
from urllib.parse import urlparse
import pdfplumber
from pathlib import Path
import logging
import json
import nltk
from nltk.tokenize import sent_tokenize

# Ensure NLTK data is available
try:
    nltk.data.find('tokenizers/punkt')
except LookupError:
    nltk.download('punkt', quiet=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()]
)


def clean_text(text: str) -> str:
    """Remove excessive whitespace and empty lines."""
    if not text:
        return ""
    lines = (line.strip() for line in text.splitlines())
    chunks = (phrase.strip() for line in lines for phrase in line.split("  "))
    return '\n'.join(chunk for chunk in chunks if chunk)


def semantic_chunk_text(text: str, max_tokens: int = 500, overlap_sentences: int = 2) -> list[str]:
    """Sentence-aware semantic chunking with overlap."""
    if not text.strip():
        return []

    sentences = sent_tokenize(text)
    if not sentences:
        return [text]

    chunks = []
    current_chunk = []
    current_tokens = 0

    for sentence in sentences:
        sentence_tokens = len(sentence.split())

        if current_tokens + sentence_tokens > max_tokens and current_chunk:
            chunks.append(" ".join(current_chunk))
            current_chunk = current_chunk[-overlap_sentences:]
            current_tokens = sum(len(s.split()) for s in current_chunk)

        current_chunk.append(sentence)
        current_tokens += sentence_tokens

    if current_chunk:
        chunks.append(" ".join(current_chunk))

    return chunks


def process_html_file(html_path: Path) -> tuple[str | None, str]:
    try:
        with open(html_path, 'r', encoding='utf-8') as f:
            soup = BeautifulSoup(f, 'html.parser')

        title = soup.find('title').get_text(strip=True) if soup.find('title') else html_path.stem

        # Remove unwanted elements
        for selector in ['script', 'style', 'nav', 'header', 'footer', 'aside', '.sidebar', '.toc']:
            for elem in soup.select(selector):
                elem.decompose()

        main = soup.find('main') or soup.find('article') or soup.find('body')
        raw_text = main.get_text(separator='\n', strip=True) if main else soup.get_text(separator='\n', strip=True)

        cleaned = clean_text(raw_text)

        headings = [h.get_text(strip=True) for h in soup.find_all(['h1', 'h2', 'h3', 'h4'])]
        structured = f"# {title}\n\n"
        if headings:
            structured += "## Key Sections\n" + "\n".join(f"- {h}" for h in headings) + "\n\n"
        structured += cleaned

        return title, structured
    except Exception as e:
        logging.error(f"HTML processing error {html_path}: {e}")
        return None, ""


def process_pdf_file(pdf_path: Path) -> tuple[str | None, str]:
    try:
        parts = []
        with pdfplumber.open(pdf_path) as pdf:
            for num, page in enumerate(pdf.pages, 1):
                text = page.extract_text()
                if text:
                    parts.append(f"## Page {num}\n{text}")

        full = "\n\n".join(parts)
        return pdf_path.stem, f"# {pdf_path.stem}\n\n{clean_text(full)}"
    except Exception as e:
        logging.error(f"PDF processing error {pdf_path}: {e}")
        return None, ""


def process_markdown_file(md_path: Path) -> tuple[str | None, str]:
    try:
        with open(md_path, 'r', encoding='utf-8') as f:
            return md_path.stem, clean_text(f.read())
    except Exception as e:
        logging.error(f"Markdown processing error {md_path}: {e}")
        return None, ""


def process_text_file(txt_path: Path) -> tuple[str | None, str]:
    try:
        with open(txt_path, 'r', encoding='utf-8') as f:
            return txt_path.stem, clean_text(f.read())
    except Exception as e:
        logging.error(f"Text processing error {txt_path}: {e}")
        return None, ""


def process_jsonl_file(jsonl_path: Path, text_key: str = "text") -> tuple[str | None, str]:
    """Process a JSONL file where each line contains a document (typically with a 'text' field)."""
    try:
        documents = []
        with open(jsonl_path, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    doc = json.loads(line)
                    text = doc.get(text_key, "").strip()
                    if not text:
                        logging.warning(f"Line {line_num}: No '{text_key}' field or empty")
                        continue

                    # Optional: use title/source if available
                    title = doc.get("title", "") or doc.get("source", "") or jsonl_path.stem
                    entry = f"# {title}\n\n"
                    if "url" in doc or "source" in doc:
                        entry += f"Source: {doc.get('url', doc.get('source', 'unknown'))}\n\n"
                    entry += clean_text(text)
                    documents.append(entry)
                except json.JSONDecodeError:
                    logging.warning(f"Line {line_num}: Invalid JSON - skipped")

        if not documents:
            return None, ""

        full_content = "\n\n---\n\n".join(documents)
        return jsonl_path.stem, full_content
    except Exception as e:
        logging.error(f"JSONL processing error {jsonl_path}: {e}")
        return None, ""


def process_url(url: str, session: requests.Session) -> tuple[str | None, str]:
    try:
        resp = session.get(url, timeout=15)
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, 'html.parser')

        title = soup.find('title').get_text(strip=True) if soup.find('title') else urlparse(url).netloc
        for selector in ['script', 'style', 'nav', 'header', 'footer', 'aside']:
            for elem in soup.select(selector):
                elem.decompose()

        main = soup.find('main') or soup.find('article') or soup.find('body')
        raw = main.get_text(separator='\n', strip=True) if main else soup.get_text(separator='\n', strip=True)

        return title, f"# {title}\n\nURL: {url}\n\n{clean_text(raw)}"
    except Exception as e:
        logging.error(f"URL scrape error {url}: {e}")
        return None, ""


def process_source(source: str, output_dir: Path, max_tokens: int, overlap: int,
                   session: requests.Session | None, jsonl_key: str = "text",
                   corpus_entries: list | None = None) -> int:
    """Process a source and optionally collect corpus entries."""
    source_path = Path(source)
    count = 0

    try:
        if source_path.is_dir():
            for file in source_path.rglob('*'):
                suffix = file.suffix.lower()
                if suffix in ['.html', '.htm']:
                    title, content = process_html_file(file)
                elif suffix == '.pdf':
                    title, content = process_pdf_file(file)
                elif suffix == '.md':
                    title, content = process_markdown_file(file)
                elif suffix == '.txt':
                    title, content = process_text_file(file)
                elif suffix == '.jsonl':
                    title, content = process_jsonl_file(file, text_key=jsonl_key)
                else:
                    continue

                if not content:
                    continue

                chunks = semantic_chunk_text(content, max_tokens, overlap)

                rel = file.relative_to(source_path).parent
                out_sub = output_dir / rel
                out_sub.mkdir(parents=True, exist_ok=True)

                for i, chunk in enumerate(chunks):
                    name = f"{file.stem}{f'_{i+1}' if len(chunks)>1 else ''}.md"
                    path = out_sub / name
                    try:
                        path.write_text(chunk, encoding='utf-8')
                        logging.info(f"{file} → {path.relative_to(output_dir)}")
                        count += 1
                        
                        # Add to corpus if collecting
                        if corpus_entries is not None:
                            corpus_entries.append({
                                "text": chunk,
                                "source": str(file.relative_to(source_path)),
                                "chunk_index": i if len(chunks) > 1 else 0,
                                "total_chunks": len(chunks)
                            })
                    except Exception as e:
                        logging.error(f"Write failed {path}: {e}")

        elif source_path.is_file():
            suffix = source_path.suffix.lower()
            if suffix in ['.html', '.htm']:
                title, content = process_html_file(source_path)
            elif suffix == '.pdf':
                title, content = process_pdf_file(source_path)
            elif suffix == '.md':
                title, content = process_markdown_file(source_path)
            elif suffix == '.txt':
                title, content = process_text_file(source_path)
            elif suffix == '.jsonl':
                title, content = process_jsonl_file(source_path, text_key=jsonl_key)
            else:
                logging.error(f"Unsupported file type: {suffix}")
                return 0

            if content:
                chunks = semantic_chunk_text(content, max_tokens, overlap)
                output_dir.mkdir(parents=True, exist_ok=True)
                for i, chunk in enumerate(chunks):
                    name = f"{source_path.stem}{f'_{i+1}' if len(chunks)>1 else ''}.md"
                    path = output_dir / name
                    path.write_text(chunk, encoding='utf-8')
                    logging.info(f"{source_path} → {path}")
                    count += 1
                    
                    # Add to corpus if collecting
                    if corpus_entries is not None:
                        corpus_entries.append({
                            "text": chunk,
                            "source": source_path.name,
                            "chunk_index": i if len(chunks) > 1 else 0,
                            "total_chunks": len(chunks)
                        })

        elif source.startswith(('http://', 'https://')):
            if not session:
                logging.error("URL processing requires internet access")
                return 0
            title, content = process_url(source, session)
            if content:
                chunks = semantic_chunk_text(content, max_tokens, overlap)
                output_dir.mkdir(parents=True, exist_ok=True)
                for i, chunk in enumerate(chunks):
                    name = f"{urlparse(source).netloc.replace('.', '_')}{f'_{i+1}' if len(chunks)>1 else ''}.md"
                    path = output_dir / name
                    path.write_text(chunk, encoding='utf-8')
                    logging.info(f"{source} → {path}")
                    count += 1
                    
                    # Add to corpus if collecting
                    if corpus_entries is not None:
                        corpus_entries.append({
                            "text": chunk,
                            "source": source,
                            "chunk_index": i if len(chunks) > 1 else 0,
                            "total_chunks": len(chunks)
                        })

    except Exception as e:
        logging.error(f"Source processing failed {source}: {e}")

    return count


def main():
    parser = argparse.ArgumentParser(
        description="Production-Ready RAG Dataset Preparation Tool (supports JSONL corpora like ragqa_arena_tech_corpus.jsonl)"
    )
    parser.add_argument("sources", nargs='+',
                        help="Directories, files (.html,.pdf,.md,.txt,.jsonl), or URLs")
    parser.add_argument("output_dir", help="Output directory for chunked .md files")
    parser.add_argument("--max-tokens", type=int, default=500,
                        help="Approximate maximum tokens per chunk")
    parser.add_argument("--overlap-sentences", type=int, default=2,
                        help="Number of sentences to overlap between chunks")
    parser.add_argument("--jsonl-key", type=str, default="text",
                        help="JSON key to extract text from in .jsonl files (default: 'text')")
    parser.add_argument("--corpus-output", type=str,
                        help="Path to output JSONL corpus file (e.g., corpus.jsonl)")

    args = parser.parse_args()

    session = requests.Session() if any(s.startswith(('http://', 'https://')) for s in args.sources) else None
    total_chunks = 0
    output_path = Path(args.output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    # Collect corpus entries if requested
    corpus_entries = [] if args.corpus_output else None

    for source in args.sources:
        logging.info(f"Processing source: {source}")
        total_chunks += process_source(
            source,
            output_path,
            args.max_tokens,
            args.overlap_sentences,
            session,
            jsonl_key=args.jsonl_key,
            corpus_entries=corpus_entries
        )

    # Write corpus JSONL file if requested
    if args.corpus_output and corpus_entries:
        corpus_path = Path(args.corpus_output)
        corpus_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(corpus_path, 'w', encoding='utf-8') as f:
            for entry in corpus_entries:
                f.write(json.dumps(entry, ensure_ascii=False) + '\n')
        
        logging.info(f"Corpus saved: {corpus_path} ({len(corpus_entries)} entries)")

    logging.info(f"Processing complete: {total_chunks} chunks written to {output_path}")


if __name__ == "__main__":
    main()
