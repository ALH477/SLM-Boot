# Offline AI Assistant Live USB

**Production-Ready, Modular, Offline AI Assistant with RAG Dataset Integration**

<img width="1920" height="1280" alt="image" src="https://github.com/user-attachments/assets/256ff118-9089-4210-a580-1e738e7be306"

---

## Overview

This project provides a **fully offline AI assistant live USB**, built on **NixOS** and packaged with **modular services**, including:

- **Ollama LLM server** (offline language model container)
- **Open WebUI frontend** (browser-based GUI)
- **Voice pipeline** (PipeWire + ALSA + TTS/ASR)
- **RAG dataset preparation tool** (`rag-dataset-prep`)
- Security-focused setup with hardened defaults and systemd resource limits
- Automatic browser launch on system startup

This setup is **production-ready**, reproducible, and designed for offline-first operation.

---

## Features

- **Minimal graphical environment**: DWM + LightDM + Firefox
- **Podman container management**: isolated networks, auto-load images
- **Persistent storage guidance**: recommended for repeated live USB use
- **Automatic dataset tooling**: supports HTML, PDF, Markdown, text, and URL scraping
- **Sentence-aware semantic chunking** for RAG datasets
- **Security hardening**: firewall, auditd, memory/CPU limits

---

## Architecture

```mermaid
flowchart TD
    A[Live USB Boot] --> B[Systemd Activation Scripts]
    B --> C[Preload Ollama & WebUI Images]
    B --> D[Set up Firewall & Hardening]
    B --> E[Auto-launch Firefox]

    C --> F[Podman Network: ollama-net]
    F --> G[Ollama LLM Container]
    F --> H[Open WebUI Container]

    G -->|API| H
    E -->|Browser GUI| H

    subgraph RAG Tool
        I[rag-dataset-prep.py] --> J[Process PDFs, HTML, Markdown, Text, URLs]
        J --> K[Chunked Dataset Output]
    end

    A --> RAG Tool
````

---

## Installation

### ISO Generation

```bash
nix flake update
nix build .#packages.x86_64-linux.default-iso
# For voice-enabled variant
nix build .#packages.x86_64-linux.voice-iso
```

* Burn the resulting ISO to a USB drive.
* Boot and login with the default user `nixos` (password is forced to change at first login).
* Persistence recommended via a separate partition and installer (`calamares`).

---

### RAG Dataset Tool Usage

```bash
# Prepare a dataset from local files
rag-dataset-prep.py /path/to/source /path/to/output

# Include URLs if internet is available
rag-dataset-prep.py https://example.com /path/to/output
```

**Options:**

* `--max-tokens`: Approximate tokens per chunk (default 500)
* `--overlap-sentences`: Sentence overlap between chunks (default 2)

---

## System Requirements

* x86_64 CPU
* ≥4 GB RAM recommended
* Live USB with ≥8 GB storage
* Offline-first environment (internet optional for URLs)

---

## Security & Hardening

* `auditd` enabled for auditing
* Podman containers run with:

  * `--cap-drop=ALL`
  * `no-new-privileges`
  * `--read-only` filesystem
* Firewall restricted to only necessary ports:

  * 11434 → Ollama API
  * 3000 → Open WebUI

---

## License

```
BSD 3-Clause License

Copyright © 2025 DeMoD LLC

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

---

## Contact

DeMoD LLC – [support@demod.com](mailto:support@demod.com)

