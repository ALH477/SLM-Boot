# Offline AI Assistant Live USB

**Production-Ready, Fully Offline Local AI Assistant with RAG**

<img width="1920" height="1280" alt="Offline AI Assistant Desktop" src="https://github.com/user-attachments/assets/256ff118-9089-4210-a580-1e738e7be306"/>

> Bootable NixOS live USB / VM image with local LLM, semantic RAG, and optional voice pipeline  
> 100% offline after model baking – perfect for air-gapped, secure, or field use

## Overview

This Nix flake produces **reproducible bootable images** of a privacy-focused, offline-first AI assistant:

- **Ollama** — local LLM inference
- **Open WebUI** — modern browser-based chat frontend
- **SLM-Assist** — custom DSPy + Gradio RAG pipeline (sentence-transformers + FAISS)
- **Optional voice pipeline** — STT → LLM → TTS
- **RAG dataset preparation tool** — chunk & embed documents offline
- **Automatic Floorp launch** to RAG interface on graphical boots
- **CachyOS BORE kernel** — optimized for low-latency interactivity
- **Hardened configuration** — security-focused defaults

Built entirely with Nix flakes for reproducibility and easy customization.

## Key Features

- Fully offline operation (models & corpus baked into the image)
- Multiple output formats: graphical ISO, voice ISO, headless kexec, qcow2 VM, raw disk
- Delayed Gradio startup (~45s) to ensure Ollama is ready
- Semantic chunking for RAG corpora (PDF, MD, HTML, TXT, JSONL, URLs)
- Automatic browser opening to http://127.0.0.1:7861 on graphical profiles
- No internet required after build (models copied via systemd tmpfiles)
- Persistence-ready layout (optional /persist bind-mount for live USB reuse)

## System Requirements

| Component          | Minimum          | Recommended              |
|--------------------|------------------|--------------------------|
| Architecture       | x86_64           | x86_64                   |
| RAM                | 8 GB             | 16–32 GB                 |
| Storage (USB/VM)   | 16 GB            | 64–128 GB+ (for models)  |
| CPU                | 4 cores          | 8+ cores (AVX2+)         |
| GPU (optional)     | —                | NVIDIA/AMD for faster inference |

## Quick Start

### 1. Prepare the model (offline baking – do this once on a machine with internet)

```bash
# Create models folder at flake root
mkdir -p models

# Temporarily override Ollama storage location
export OLLAMA_MODELS="$PWD/models"

# Pull desired model(s) – small/quantized recommended
ollama pull qwen3:0.6b
# or better: ollama pull qwen3:0.6b-instruct-q5_K_M   (~400–600 MB)
# or: ollama pull phi3:mini
# or: ollama pull llama3.1:8b-instruct-q5_K_M

# Verify
ls -la models/blobs models/manifests
ollama list   # should show the pulled model
```

**Important:** Do **not** commit large blob files directly unless using git-lfs.

### 2. Build the image

```bash
# Update flake inputs (recommended first time)
nix flake update

# Build graphical ISO (DWM desktop + auto Floorp to RAG UI)
nix build .#graphical-iso
# or use path: prefix if models/ is untracked:
# nix build path:.#graphical-iso

# Voice-enabled variant
nix build .#graphical-voice-iso

# Headless VM image (test in QEMU)
nix build .#headless-vm
```

### 3. Write to USB or run in VM

```bash
# Write to USB (WARNING: double-check device!)
sudo dd if=result of=/dev/sdX bs=4M status=progress oflag=sync conv=fsync

# Quick QEMU test (headless-vm)
qemu-system-x86_64 -m 8G -drive file=result,format=qcow2 -cpu host -smp 8
```

### 4. Boot & Use

- **Graphical**: Boot → wait ~45–90 seconds → Floorp auto-opens to Gradio RAG UI (http://127.0.0.1:7861)
- **Headless**: Access Open WebUI at http://localhost:3000 (default port)
- Default credentials: user `nixos`, password change required on first login
- Check Ollama: `ollama list` (should show baked-in model without pulling)

## Adding / Changing Models

1. Pull new model(s) into `./models/` as shown above
2. The `modules/slm-assist/default.nix` automatically copies `./models/{blobs,manifests}` → `/var/lib/ollama/models` at boot
3. Update config if you want to reference a different tag (mostly cosmetic):

   ```nix
   services.slm-assist.ollamaModel = "qwen3:0.6b-instruct-q5_K_M";
   ```

4. Rebuild → the model is now baked in (no pull on boot)

## Customizing the Corpus

Place your JSONL corpus in `./corpus/`:

```bash
# Example: copy existing DSPy-format corpus
mkdir -p corpus
curl -L https://huggingface.co/dspy/cache/resolve/main/ragqa_arena_tech_corpus.jsonl \
  -o corpus/ragqa_arena_tech_corpus.jsonl
```

It's automatically copied to `/var/lib/slm-assist/` via tmpfiles.

For your own documents → use the preparation tool:

```bash
python scripts/rag_dataset_prep.py /path/to/docs/ corpus/my-corpus.jsonl \
  --max-tokens 400 --overlap-sentences 3
```

Then add to tmpfiles if needed (already handled for default corpus).

## Security & Hardening

- Minimal attack surface (no unnecessary services/ports open)
- `ProtectSystem=strict`, `NoNewPrivileges=true`, `DynamicUser` where possible
- Auditd enabled for security-relevant events
- Firewall: only internal ports (11434 Ollama, 7861 Gradio, 3000 WebUI)
- **Never** set `services.slm-assist.exposeExternally = true` on untrusted networks

## License

BSD 3-Clause License  
Copyright © 2025 DeMoD LLC

See [LICENSE](./LICENSE) for full text.

## Troubleshooting

- **Model not found after boot**  
  Check: `journalctl -u ollama` and `ls -la /var/lib/ollama/models/blobs`  
  Ensure `./models` was git-added or built with `path:.`

- **Build fails with "Path ... does not exist in Git repository"**  
  Use: `nix build path:.#graphical-iso`

- **Slow boot / Ollama not ready**  
  Increase `services.slm-assist.delayStartSec = 90;`

## Contact

DeMoD LLC  
Issues / PRs welcome on GitHub
