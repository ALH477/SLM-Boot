#!/usr/bin/env python3
"""
Generate a comprehensive JSONL corpus documenting the SLM-Boot flake system.

This script analyzes the flake.nix and related modules to create documentation
entries explaining how the system works, suitable for RAG-based Q&A.
"""

import json
from pathlib import Path
import re

def extract_module_info(module_path: Path) -> dict:
    """Extract key information from a NixOS module file."""
    try:
        content = module_path.read_text(encoding='utf-8')
        
        # Extract comments at the top
        comments = []
        for line in content.split('\n'):
            if line.strip().startswith('#'):
                comments.append(line.strip('#').strip())
            elif line.strip() and not line.strip().startswith('#'):
                break
        
        description = '\n'.join(comments) if comments else f"Module: {module_path.stem}"
        
        # Extract service/option definitions
        services = re.findall(r'services\.(\w+)', content)
        options = re.findall(r'mkOption\s*{', content)
        
        return {
            'path': str(module_path),
            'description': description,
            'services': list(set(services)),
            'has_options': len(options) > 0,
            'content': content
        }
    except Exception as e:
        print(f"Error processing {module_path}: {e}")
        return None

def generate_corpus_entries() -> list[dict]:
    """Generate all corpus entries for the flake documentation."""
    entries = []
    
    # Entry 1: High-level overview
    entries.append({
        "text": """# SLM-Boot: Offline AI Assistant System Overview

SLM-Boot is a NixOS-based bootable system designed for running local AI assistants completely offline. It uses Nix flakes for reproducible builds and supports multiple deployment formats.

## Key Features
- **Multiple deployment formats**: Graphical live USB ISO, headless kexec bundles, VM images (qcow2), and raw disk images
- **CachyOS BORE kernel**: Enhanced for better interactivity and responsiveness with AI workloads
- **SLM-Assist**: Local DSPy RAG system with Ollama backend and Gradio web interface
- **Delayed startup**: Configurable delays ensure services initialize properly before the UI launches
- **Auto-browser launch**: Automatic Floorp browser opening on graphical profiles
- **Corpus integration**: Pre-baked knowledge base for RAG queries

## Architecture
The system consists of:
1. Base NixOS configuration modules (graphical/headless)
2. Container runtime (Podman) for isolated services
3. Ollama LLM server with pre-pulled models
4. SLM-Assist RAG application with DSPy framework
5. Optional OpenWebUI for model interaction
6. Production hardening and optimization modules""",
        "source": "system_overview",
        "chunk_index": 0,
        "total_chunks": 1
    })
    
    # Entry 2: Flake structure
    entries.append({
        "text": """# SLM-Boot Flake Structure

The flake.nix file defines the entire system configuration using Nix flakes.

## Inputs
```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  nixos-generators = {
    url = "github:nix-community/nixos-generators";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

- **nixpkgs**: Uses the unstable channel for latest packages
- **nixos-generators**: Provides utilities for generating various output formats (ISO, kexec, qcow2, raw)

## Module Organization
Modules are organized in the `modules/` directory:
- `graphical-minimal.nix`: Minimal desktop environment (DWM)
- `headless-minimal.nix`: Server configuration without GUI
- `slm-assist/default.nix`: Main SLM-Assist RAG system
- `ollama-service.nix`: Ollama LLM server (legacy, now integrated in slm-assist)
- `open-webui-service.nix`: Web UI for model interaction
- `kernel-cachyos-bore.nix`: BORE kernel configuration
- `hardening.nix`: Security hardening
- `production-extras.nix`: Performance optimizations""",
        "source": "flake_structure",
        "chunk_index": 0,
        "total_chunks": 1
    })
    
    # Entry 3: Build targets
    entries.append({
        "text": """# SLM-Boot Build Targets

The flake provides multiple build targets for different use cases.

## Graphical ISO (Live USB)
```bash
nix build .#packages.x86_64-linux.graphical-iso
```
Creates a bootable ISO with:
- Minimal DWM desktop environment
- Auto-login as 'nixos' user
- Floorp browser auto-launching to Gradio UI
- SLM-Assist with 45-second delayed start
- Pre-baked corpus at /var/lib/slm-assist

## Graphical ISO with Voice Pipeline
```bash
nix build .#packages.x86_64-linux.graphical-voice-iso
```
Adds voice interaction capabilities to the graphical ISO.

## Headless Kexec Bundle
```bash
nix build .#packages.x86_64-linux.headless-kexec
```
For booting into NixOS from an existing Linux system without rebooting.

## Headless VM Image (qcow2)
```bash
nix build .#packages.x86_64-linux.headless-vm
```
QEMU/KVM-compatible disk image for virtual machine deployment.

## Headless Raw Disk Image
```bash
nix build .#packages.x86_64-linux.headless-raw
```
Raw disk image for writing directly to storage devices.""",
        "source": "build_targets",
        "chunk_index": 0,
        "total_chunks": 1
    })
    
    # Entry 4: SLM-Assist configuration
    entries.append({
        "text": """# SLM-Assist Configuration

SLM-Assist is the core RAG (Retrieval-Augmented Generation) system in SLM-Boot.

## Configuration Options
```nix
services.slm-assist = {
  enable = true;                              # Enable the service
  ollamaModel = "qwen3:0.6b-instruct-q5_K_M"; # Model to use
  gradioPort = 7861;                          # Web UI port
  dataDir = "/var/lib/slm-assist";            # Data directory
  exposeExternally = false;                   # Firewall setting
  delayStartSec = 45;                         # Startup delay in seconds
  autoOpenBrowser = true;                     # Auto-launch Floorp (graphical only)
};
```

## How It Works
1. **Ollama Service**: Native NixOS service runs Ollama LLM server on port 11434
2. **Model Pre-pull**: Systemd service pre-downloads the specified model during boot
3. **Delayed Start**: Timer waits 45 seconds for Ollama to initialize
4. **Gradio Launch**: Python application starts serving the RAG interface
5. **Browser Launch**: Floorp opens to http://127.0.0.1:7861 (graphical profiles only)

## Architecture
- **Backend**: Ollama provides LLM inference
- **Framework**: DSPy for RAG pipeline orchestration
- **Embeddings**: sentence-transformers for document encoding
- **Vector Store**: FAISS for similarity search
- **Frontend**: Gradio web interface
- **Corpus**: Pre-baked JSONL file with domain knowledge""",
        "source": "slm_assist_config",
        "chunk_index": 0,
        "total_chunks": 1
    })
    
    # Entry 5: Module system
    entries.append({
        "text": """# SLM-Boot Module System

The system uses composable NixOS modules for flexibility.

## Graphical Profile Modules
```nix
graphicalModules = [
  installation-cd-minimal.nix     # Base ISO configuration
  graphical-minimal               # DWM desktop
  preload                         # Preload common libraries
  containers-base                 # Podman setup
  open-webui-service              # Model interaction UI
  hardening                       # Security hardening
  production-extras               # Performance tuning
  rag-dataset-tool                # Corpus preparation tool
  kernel-cachyos-bore             # BORE kernel
  slm-assist                      # Main RAG system
];
```

## Headless Profile Modules
```nix
headlessModules = [
  headless-minimal                # Server base config
  preload                         # Preload common libraries
  containers-base                 # Podman setup
  open-webui-service              # Model interaction UI
  headless-access                 # SSH and remote access
  hardening                       # Security hardening
  production-extras               # Performance tuning
  rag-dataset-tool                # Corpus preparation tool
  kernel-cachyos-bore             # BORE kernel
  slm-assist                      # Main RAG system (no browser)
];
```

## Key Differences
- **Graphical**: Includes desktop environment, auto-login, browser launch
- **Headless**: SSH access, no GUI, service-only deployment
- **Both**: Share core AI infrastructure (Ollama, SLM-Assist, corpus)""",
        "source": "module_system",
        "chunk_index": 0,
        "total_chunks": 1
    })
    
    # Entry 6: Corpus management
    entries.append({
        "text": """# Corpus Management in SLM-Boot

The corpus is the knowledge base used for RAG queries.

## Corpus Location
- **Source**: `modules/slm-assist/corpus/ragqa_arena_tech_corpus.jsonl`
- **Runtime**: `/var/lib/slm-assist/ragqa_arena_tech_corpus.jsonl`

## Corpus Format (JSONL)
Each line is a JSON object with document chunks:
```json
{"text": "Document content here...", "source": "filename.md", "chunk_index": 0, "total_chunks": 3}
```

## How It's Integrated
The corpus is baked into the image using systemd tmpfiles:
```nix
systemd.tmpfiles.rules = [
  "d /var/lib/slm-assist 0755 slm-assist slm-assist - -"
  "C /var/lib/slm-assist/ragqa_arena_tech_corpus.jsonl - - - - ${./corpus/ragqa_arena_tech_corpus.jsonl}"
  "Z /var/lib/slm-assist 0755 slm-assist slm-assist - -"
];
```

## Creating Your Own Corpus
Use the included `rag_dataset_prep.py` script:
```bash
python3 scripts/rag_dataset_prep.py \
  your_docs/ \
  /tmp/output \
  --corpus-output modules/slm-assist/corpus/ragqa_arena_tech_corpus.jsonl

git add modules/slm-assist/corpus/ragqa_arena_tech_corpus.jsonl
nix build .#packages.x86_64-linux.graphical-iso
```

## Supported Source Formats
- HTML/HTM files
- PDF documents
- Markdown files
- Plain text files
- JSONL files (for corpus-to-corpus conversion)
- Web URLs (requires internet during build)""",
        "source": "corpus_management",
        "chunk_index": 0,
        "total_chunks": 1
    })
    
    # Entry 7: Development workflow
    entries.append({
        "text": """# SLM-Boot Development Workflow

## Quick Start
```bash
# Clone the repository
git clone <repository-url>
cd SLM-Boot

# Prepare your corpus
mkdir -p modules/slm-assist/corpus
python3 scripts/rag_dataset_prep.py docs/ /tmp/output \
  --corpus-output modules/slm-assist/corpus/ragqa_arena_tech_corpus.jsonl

# Stage the corpus (required for Nix flakes)
git add modules/slm-assist/corpus/

# Build the graphical ISO
nix build .#packages.x86_64-linux.graphical-iso

# Result is in ./result/iso/
ls -lh result/iso/*.iso
```

## Testing in a VM
```bash
# Build VM image
nix build .#packages.x86_64-linux.headless-vm

# Run with QEMU
qemu-system-x86_64 -m 4G -smp 2 -enable-kvm \
  -drive file=result/nixos.qcow2,format=qcow2
```

## Writing to USB
```bash
# After building ISO
sudo dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress
sync
```

## Common Issues
1. **Hash mismatch errors**: Run `nix hash to-sri --type sha256 <old-hash>`
2. **Git tree warnings**: Stage files with `git add` (don't need to commit)
3. **Missing corpus**: Ensure corpus file exists and is staged in Git
4. **Service conflicts**: Check for duplicate service definitions across modules""",
        "source": "development_workflow",
        "chunk_index": 0,
        "total_chunks": 1
    })
    
    # Entry 8: Ollama integration
    entries.append({
        "text": """# Ollama Integration in SLM-Boot

Ollama provides local LLM inference for the RAG system.

## Configuration
The native NixOS Ollama service is used:
```nix
services.ollama = {
  enable = true;
  # Optional GPU acceleration:
  # package = pkgs.ollama-cuda;   # NVIDIA
  # package = pkgs.ollama-rocm;   # AMD
};
```

## Model Pre-pulling
A systemd service automatically downloads the model:
```nix
systemd.services."ollama-prepull-${cfg.ollamaModel}" = {
  description = "Pre-pull Ollama model for SLM Assist";
  wantedBy = [ "multi-user.target" ];
  after = [ "ollama.service" ];
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "${pkgs.ollama}/bin/ollama pull qwen3:0.6b-instruct-q5_K_M";
    RemainAfterExit = true;
    User = "ollama";
    Group = "ollama";
  };
};
```

## Supported Models
- **qwen3:0.6b-instruct-q5_K_M**: Default, very fast on CPU
- **qwen3:4b-instruct-q5_K_M**: Better quality, needs more RAM
- **llama3.1:8b**: High quality, requires 8GB+ RAM
- **phi4:mini**: Microsoft's efficient model
- Custom models from Ollama registry

## API Access
- **URL**: http://127.0.0.1:11434
- **Protocol**: OpenAI-compatible REST API
- **Environment**: Set via OLLAMA_HOST in service configs""",
        "source": "ollama_integration",
        "chunk_index": 0,
        "total_chunks": 1
    })
    
    # Entry 9: DSPy RAG pipeline
    entries.append({
        "text": """# DSPy RAG Pipeline in SLM-Assist

DSPy orchestrates the Retrieval-Augmented Generation pipeline.

## Pipeline Architecture
1. **Query Processing**: User question received via Gradio
2. **Embedding Generation**: sentence-transformers encodes the query
3. **Vector Search**: FAISS finds most relevant corpus chunks
4. **Context Assembly**: Top-k documents assembled into context
5. **LLM Generation**: Ollama generates response using context
6. **Response Rendering**: Answer displayed in Gradio UI

## Key Components
```python
# Simplified DSPy pipeline structure
class RAGPipeline(dspy.Module):
    def __init__(self):
        self.retrieve = dspy.Retrieve(k=5)
        self.generate = dspy.ChainOfThought("context, question -> answer")
    
    def forward(self, question):
        context = self.retrieve(question).passages
        return self.generate(context=context, question=question)
```

## Python Dependencies
- **dspy-ai**: Pipeline orchestration framework
- **faiss-cpu**: Fast similarity search (CPU-only version)
- **sentence-transformers**: Text embedding models
- **gradio**: Web interface framework
- **ujson**: Fast JSON parsing
- **numpy**: Numerical operations

## Index Management
FAISS index is built at runtime:
1. Corpus loaded from JSONL file
2. Documents embedded using sentence-transformers
3. FAISS index constructed in memory
4. Queries search index for relevant chunks""",
        "source": "dspy_pipeline",
        "chunk_index": 0,
        "total_chunks": 1
    })
    
    # Entry 10: CachyOS BORE kernel
    entries.append({
        "text": """# CachyOS BORE Kernel in SLM-Boot

The BORE (Burst-Oriented Response Enhancer) kernel improves interactivity.

## Why BORE?
AI workloads create bursty CPU usage patterns. The BORE scheduler:
- Prioritizes interactive tasks during burst periods
- Maintains responsiveness under AI inference loads
- Reduces latency for user input during model generation
- Optimizes for desktop/workstation use cases

## Configuration
```nix
modules/kernel-cachyos-bore.nix:
  boot.kernel.cachyos-bore.enable = true;

flake.nix:
  self.nixosModules.kernel-cachyos-bore
  { boot.kernel.cachyos-bore.enable = true; }
```

## Benefits for AI Workloads
1. **Responsive UI**: Gradio interface stays responsive during inference
2. **Better Multitasking**: Run multiple models or applications smoothly
3. **Reduced Jitter**: More consistent frame times in graphical environments
4. **Optimized Scheduling**: AI tasks get CPU time without starving the UI

## Comparison to Stock Kernel
- **Stock**: CFS (Completely Fair Scheduler) treats all tasks equally
- **BORE**: Detects burst patterns and prioritizes interactive tasks
- **Result**: Better perceived performance for desktop AI usage""",
        "source": "bore_kernel",
        "chunk_index": 0,
        "total_chunks": 1
    })
    
    return entries

def main():
    """Generate the corpus and save to file."""
    output_path = Path("modules/slm-assist/corpus/ragqa_arena_tech_corpus.jsonl")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    print("Generating SLM-Boot documentation corpus...")
    entries = generate_corpus_entries()
    
    with open(output_path, 'w', encoding='utf-8') as f:
        for entry in entries:
            f.write(json.dumps(entry, ensure_ascii=False) + '\n')
    
    print(f"✓ Generated {len(entries)} corpus entries")
    print(f"✓ Saved to: {output_path}")
    print(f"\nNext steps:")
    print(f"  git add {output_path}")
    print(f"  nix build .#packages.x86_64-linux.graphical-iso")

if __name__ == "__main__":
    main()
