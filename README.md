# Offline AI Assistant Live USB

**Production-Ready, Modular, Offline-First AI Assistant with Local RAG**

<img width="1920" height="1280" alt="Offline AI Assistant Desktop" src="https://github.com/user-attachments/assets/256ff118-9089-4210-a580-1e738e7be306"/>

> Bootable NixOS-based live USB with fully offline LLM + RAG capabilities  
> Built for privacy, reliability, and ease of deployment

## Overview

This project delivers a **fully offline-capable AI assistant** packaged as bootable media (ISO, VM image, kexec bundle, raw disk).  

It combines:
- **Ollama** – local LLM inference server
- **Open WebUI** – clean, browser-based chat interface
- **SLM-Assist** – custom DSPy-powered RAG pipeline with local embeddings (sentence-transformers + FAISS)
- **Voice pipeline** (optional) – speech-to-text + text-to-speech
- **RAG dataset preparation tool** – semantic chunking from PDF/HTML/MD/TXT/JSONL/URLs
- **Automatic Floorp browser launch** to the RAG interface on graphical boot
- **Hardened NixOS base** with CachyOS BORE kernel for responsiveness

Designed for:
- Offline use (air-gapped environments, secure research, field operations)
- Quick deployment (live USB, VM, kexec rescue)
- Reproducible builds via Nix flakes

## Key Features

- **Fully offline after first model pull** (corpus and models baked in or pre-pulled)
- **Modular NixOS services** (ollama, open-webui, slm-assist, voice pipeline)
- **Semantic RAG dataset preparation** with sentence-aware chunking
- **Automatic browser launch** to Gradio RAG UI after boot delay
- **CachyOS BORE kernel** enabled everywhere for better interactivity under load
- **Security hardening** (auditd, no-new-privileges, firewall, resource limits)
- **Persistence guidance** for repeated live USB usage

## System Requirements

| Component            | Minimum          | Recommended         |
|----------------------|------------------|---------------------|
| Architecture         | x86_64           | x86_64              |
| RAM                  | 8 GB             | 16–32 GB            |
| Storage (USB/VM)     | 16 GB            | 32–128 GB           |
| CPU                  | 4 cores          | 8+ cores            |
| GPU (optional)       | —                | NVIDIA/AMD for faster Ollama |

## Quick Start

### 1. Build the image

```bash
# Update flake lockfile (recommended first time)
nix flake update

# Build the main graphical ISO (with DWM desktop + auto Floorp launch)
nix build .#packages.x86_64-linux.graphical-iso

# Build voice-enabled variant
nix build .#packages.x86_64-linux.graphical-voice-iso

# Build headless VM image (great for testing in QEMU/VirtualBox)
nix build .#packages.x86_64-linux.headless-vm
```

### 2. Write to USB (for live boot)

```bash
# Replace /dev/sdX with your USB device (careful!)
sudo dd if=result of=/dev/sdX bs=4M status=progress oflag=sync
```

### 3. Boot & use

- Boot from USB
- Graphical: Wait ~45–60 seconds → Floorp should auto-open to the RAG chat UI
- Headless: Access Open WebUI at http://localhost:3000 or via SSH/VNC (see `headless-access` module)
- Default user: `nixos` (password forced change on first login)

## RAG Dataset Preparation Tool

The included `rag-dataset-prep.py` script prepares documents for your local RAG system.

```bash
# Prepare from local directory
python scripts/rag_dataset_prep.py /path/to/sources/ /path/to/chunks/

# Process a single JSONL corpus (DSPy style)
python scripts/rag_dataset_prep.py corpus/ragqa_arena_tech_corpus.jsonl chunks/

# From URL (requires internet)
python scripts/rag_dataset_prep.py https://example.com/docs chunks/
```

Supported formats: `.html`, `.pdf`, `.md`, `.txt`, `.jsonl`, URLs

Options:
- `--max-tokens 400` – target chunk size
- `--overlap-sentences 3` – sentence overlap between chunks
- `--jsonl-key content` – extract text from alternative JSON field

## Building Custom Images

### Change the LLM model

```nix
services.slm-assist.ollamaModel = "qwen3:4b-instruct-q5_K_M";  # or "llama3.1:8b", etc.
```

### Disable browser auto-launch (headless use)

```nix
services.slm-assist.autoOpenBrowser = false;
```

### Add your own corpus

Place it in `corpus/my-corpus.jsonl` and reference it in the tmpfiles rule:

```nix
systemd.tmpfiles.rules = [
  "C /var/lib/slm-assist/my-corpus.jsonl - - - - ${./corpus/my-corpus.jsonl}"
];
```

Update `rag_app.py` to load from that path if needed.

## Security Notes

- Firewall blocks all ports except Ollama (11434) and Open WebUI (3000) internally
- Containers run with `--cap-drop=ALL`, `--no-new-privileges`, `--read-only`
- Auditd enabled for security-relevant events
- Avoid setting `exposeExternally = true` unless you really need remote access

## License

```
BSD 3-Clause License
Copyright © 2025 DeMoD LLC

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Contact & Support

DeMoD LLC
