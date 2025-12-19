# scripts/rag_dataset_prep.py 
import os
import argparse
import requests
from bs4 import BeautifulSoup
from urllib.parse import urlparse
import pdfplumber
from pathlib import Path
import logging
import nltk
from nltk.tokenize import sent_tokenize

# Ensure NLTK data
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

def process_source(source: str, output_dir: Path, max_tokens: int, overlap: int, session: requests.Session | None) -> int:
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
                    except Exception as e:
                        logging.error(f"Write failed {path}: {e}")

        elif source_path.is_file():
            # Identical logic to directory case for single file
            suffix = source_path.suffix.lower()
            if suffix in ['.html', '.htm']:
                title, content = process_html_file(source_path)
            elif suffix == '.pdf':
                title, content = process_pdf_file(source_path)
            elif suffix == '.md':
                title, content = process_markdown_file(source_path)
            elif suffix == '.txt':
                title, content = process_text_file(source_path)
            else:
                logging.error(f"Unsupported file: {source}")
                return 0

            if content:
                chunks = semantic_chunk_text(content, max_tokens, overlap)
                output_dir.mkdir(parents=True, exist_ok=True)
                for i, chunk in enumerate(chunks):
                    name = f"{source_path.stem}{f'_{i+1}' if len(chunks)>1 else ''}.md"
                    path = output_dir / name
                    path.write_text(chunk, encoding='utf-8')
                    logging.info(f"{source_path} → {path}")
                    count += len(chunks)

        elif source.startswith(('http://', 'https://')):
            if not session:
                logging.error("URL requires internet")
                return 0
            title, content = process_url(source, session)
            if content:
                chunks = semantic_chunk_text(content, max_tokens, overlap)
                output_dir.mkdir(parents=True, exist_ok=True)
                for i, chunk in enumerate(chunks):
                    name = f"{urlparse(source).netloc}_{i+1 if len(chunks)>1 else ''}.md"
                    path = output_dir / name
                    path.write_text(chunk, encoding='utf-8')
                    logging.info(f"{source} → {path}")
                    count += len(chunks)

    except Exception as e:
        logging.error(f"Source processing failed {source}: {e}")

    return count

def main():
    parser = argparse.ArgumentParser(description="Production-Ready RAG Dataset Preparation Tool")
    parser.add_argument("sources", nargs='+', help="Directories, files, or URLs")
    parser.add_argument("output_dir", help="Output directory")
    parser.add_argument("--max-tokens", type=int, default=500, help="Approx tokens per chunk")
    parser.add_argument("--overlap-sentences", type=int, default=2, help="Sentence overlap")

    args = parser.parse_args()

    session = requests.Session() if any(s.startswith('http') for s in args.sources) else None
    total = 0
    Path(args.output_dir).mkdir(parents=True, exist_ok=True)

    for source in args.sources:
        logging.info(f"Processing {source}")
        total += process_source(source, Path(args.output_dir), args.max_tokens, args.overlap_sentences, session)

    logging.info(f"Complete: {total} chunks in {args.output_dir}")

if __name__ == "__main__":
    main()
