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
    
    # Entry 11: RAM architecture and management
    entries.append({
        "text": """# RAM (Random Access Memory) Architecture - Deep Dive

RAM is the primary volatile memory system in computers, providing fast data access for running programs.

## Physical Architecture

### Memory Hierarchy
1. **CPU Registers**: 1-2 cycles, <1KB total
2. **L1 Cache**: 3-4 cycles, 32-64KB per core
3. **L2 Cache**: 10-20 cycles, 256KB-1MB per core
4. **L3 Cache**: 40-75 cycles, 8-64MB shared
5. **Main Memory (RAM)**: 100-300 cycles, GB-TB scale
6. **Storage (SSD/HDD)**: Millions of cycles, persistent

### DRAM Technology
Modern RAM uses Dynamic RAM (DRAM):
- **Storage Cell**: One transistor + one capacitor per bit
- **Dynamic**: Capacitors leak charge, requiring periodic refresh (every 64ms)
- **Density**: High bit density due to simple cell structure
- **Cost**: Lower cost per bit than SRAM (used in caches)

### DDR (Double Data Rate) Evolution
- **DDR3**: 800-2133 MT/s, 1.5V, legacy systems
- **DDR4**: 1600-3200 MT/s, 1.2V, current mainstream
- **DDR5**: 4800-6400+ MT/s, 1.1V, modern high-end
- **LPDDR**: Low-power variants for mobile devices

## Memory Organization

### Physical Layout
```
Memory Module (DIMM)
├── Rank 0 (set of chips accessed together)
│   ├── Chip 0 (8 bits)
│   ├── Chip 1 (8 bits)
│   └── ... (total 64 bits data + 8 bits ECC)
└── Rank 1 (optional second set)
```

### Channels and Banks
- **Channels**: Independent memory pathways (dual/quad/octa-channel)
- **Banks**: Subdivisions within each memory chip
- **Rows/Columns**: Address structure within banks
- **Pages**: Row buffer holds recently accessed row (2-4KB)

### Addressing Structure
Physical address broken into:
1. **Channel bits**: Which memory channel
2. **DIMM bits**: Which physical module
3. **Rank bits**: Which rank on the module
4. **Bank bits**: Which bank group and bank
5. **Row bits**: Which row to activate
6. **Column bits**: Which columns within the row

## Memory Controller Operations

### Access Patterns
1. **Row Activation (RAS)**: Open a row into row buffer (~15-20ns)
2. **Column Access (CAS)**: Read/write specific columns (~15ns)
3. **Precharge**: Close row, prepare for next access (~15ns)
4. **Refresh**: Periodically recharge all capacitors (64ms cycle)

### Latency Components
Total latency = CAS Latency + RAS to CAS + Row Precharge + Command Rate
Example DDR4-3200 CL16: 16 cycles CL + other timing = ~45ns actual latency

### Bandwidth vs Latency
- **Bandwidth**: How much data per second (GB/s) - helps sequential access
- **Latency**: Time to first byte (ns) - critical for random access
- **Parallelism**: Multiple outstanding requests improve throughput

## Virtual Memory System

### Memory Management Unit (MMU)
The MMU translates virtual addresses to physical addresses:
- **Page Tables**: Multi-level tree structure (4-level on x86-64)
- **Page Size**: Typically 4KB, with 2MB/1GB huge pages available
- **TLB (Translation Lookaside Buffer)**: Caches recent translations

### Virtual Address Space
64-bit systems provide huge virtual address space:
- User space: 0x0000000000000000 - 0x00007FFFFFFFFFFF (128TB)
- Kernel space: 0xFFFF800000000000 - 0xFFFFFFFFFFFFFFFF (128TB)
- Actual usable: Limited by physical RAM + swap

### Page Faults
When accessing non-resident pages:
1. **Minor Fault**: Page not in RAM but allocated (fetch from disk/zero-fill)
2. **Major Fault**: Page must be read from storage (very slow, ~1-10ms)
3. **Segmentation Fault**: Invalid address access (program error)""",
        "source": "ram_architecture_part1",
        "chunk_index": 0,
        "total_chunks": 2
    })
    
    # Entry 12: RAM management in Linux/NixOS
    entries.append({
        "text": """# RAM Management in Linux and NixOS

Linux provides sophisticated memory management optimized for various workloads.

## Page Cache and Buffer Cache

### Page Cache
The kernel caches file contents in RAM:
- **Purpose**: Avoid slow disk I/O by keeping frequently accessed files in memory
- **Automatic**: Kernel uses free RAM for caching, releases under pressure
- **Benefits**: Dramatically speeds up repeated file access
- **Cost**: "Used" memory shown in `free` includes cache (actually available)

### Buffer Cache
Caches block device metadata:
- **Inodes**: File metadata (permissions, timestamps, location)
- **Directory entries**: Cached directory listings
- **Superblocks**: Filesystem metadata
- **Importance**: Critical for filesystem performance

### Memory Pressure
When applications need RAM:
1. Kernel identifies least-recently-used (LRU) pages
2. Clean pages dropped immediately (can reload from disk)
3. Dirty pages written to disk first, then dropped
4. Cache shrinks, application gets memory

## Memory Allocators

### Kernel Allocator (SLUB)
Manages kernel memory:
- **SLUB allocator**: Modern default (replaced SLAB and SLOB)
- **Object caching**: Frequently allocated structures cached
- **Per-CPU caches**: Reduces lock contention
- **Slab pages**: Groups objects by size class

### User Space Allocators
Applications use allocators like glibc malloc:
- **malloc/free**: Standard C allocation functions
- **Memory arenas**: Per-thread allocation regions
- **mmap**: Large allocations mapped directly
- **jemalloc/tcmalloc**: Alternative allocators for performance

## Memory Overcommit

### Overcommit Modes
```bash
/proc/sys/vm/overcommit_memory:
0 = Heuristic (default): Allow reasonable overcommit
1 = Always: Allow all allocations (can lead to OOM)
2 = Never: Strict accounting, no overcommit
```

### Why Overcommit?
- Applications often allocate more than they use
- fork() creates copy-on-write duplicates
- Allows more processes to run with limited RAM
- Risk: Out-of-Memory (OOM) killer may terminate processes

## OOM (Out of Memory) Killer

### When OOM Triggers
1. System exhausts RAM and swap
2. Kernel cannot satisfy allocation request
3. OOM killer selects victim process
4. Process terminated to free memory

### OOM Score
Each process has OOM score (0-1000):
- Based on memory usage, runtime, and importance
- Lower score = less likely to be killed
- Adjustable via `/proc/<pid>/oom_score_adj`
- System processes protected by default

## Memory Limits and Control Groups

### cgroups v2 Memory Controller
```bash
# Set hard limit
echo "4G" > /sys/fs/cgroup/myapp/memory.max

# Set soft limit (pressure point)
echo "3G" > /sys/fs/cgroup/myapp/memory.high

# Monitor usage
cat /sys/fs/cgroup/myapp/memory.current
```

### NixOS Service Limits
```nix
systemd.services.myservice = {
  serviceConfig = {
    MemoryMax = "4G";        # Hard limit
    MemoryHigh = "3.5G";     # Soft limit (throttling)
    MemorySwapMax = "2G";    # Swap limit
  };
};
```

## Swap and Swappiness

### Swap Space
Extends RAM using disk storage:
- **Swap Partition**: Dedicated disk partition
- **Swap File**: Regular file used as swap
- **zram**: Compressed RAM used as swap (fast but uses RAM)

### Swappiness Parameter
```bash
/proc/sys/vm/swappiness (0-200, default 60):
0 = Avoid swap unless necessary
60 = Balanced (default)
100 = Aggressive swapping
200 = Prefer swapping over page cache
```

### SLM-Boot Considerations
For AI workloads:
- **Lower swappiness (10-20)**: Keep model weights in RAM
- **Large swap on SSD**: Graceful degradation if OOM
- **zram**: Fast compressed swap for temporary pressure
- **Monitor pressure**: Watch for thrashing (excessive swapping)

## NUMA (Non-Uniform Memory Access)

### Architecture
Multi-socket systems have local RAM per CPU:
- **Local**: Fast access to CPU's own RAM
- **Remote**: Slower access to other CPU's RAM
- **Latency**: Remote access 1.5-3x slower

### NUMA Policy
```bash
# Bind process to node 0
numactl --cpunodebind=0 --membind=0 ./myapp

# Interleave across all nodes
numactl --interleave=all ./myapp
```

### NixOS NUMA Configuration
Kernel automatically handles NUMA:
- **AutoNUMA**: Migrates pages to local memory
- **Transparent**: Usually no tuning needed
- **Monitoring**: `numastat` shows NUMA statistics""",
        "source": "ram_management_linux",
        "chunk_index": 1,
        "total_chunks": 2
    })
    
    # Entry 13: RAM optimization for AI workloads
    entries.append({
        "text": """# RAM Optimization for AI/LLM Workloads

AI inference and training have unique memory requirements and optimization strategies.

## LLM Memory Requirements

### Model Size Calculations
```
Formula: Parameters × Bytes_per_Parameter × Overhead

Examples (FP16/Q8 quantization):
- 0.6B parameters × 2 bytes = 1.2GB (+ ~20% overhead = 1.5GB)
- 4B parameters × 2 bytes = 8GB (+ ~20% overhead = 10GB)
- 8B parameters × 2 bytes = 16GB (+ ~20% overhead = 20GB)
- 70B parameters × 2 bytes = 140GB (+ ~20% overhead = 170GB)

Quantization reduces size:
- FP32: 4 bytes per parameter (full precision)
- FP16: 2 bytes per parameter (half precision)
- Q8: 1 byte per parameter (8-bit quantization)
- Q4: 0.5 bytes per parameter (4-bit quantization)
```

### Memory Components
1. **Model Weights**: Largest component, size depends on quantization
2. **KV Cache**: Stores attention keys/values for context (grows with context length)
3. **Activations**: Intermediate computations during inference
4. **Gradients**: Only during training (not needed for inference)

### Context Window Impact
KV cache grows with context length:
```
KV Cache Size = Layers × Heads × Head_Dim × Context_Length × 2 × Bytes_per_Element

Example (Llama-style 8B model, 8K context, FP16):
32 layers × 32 heads × 128 head_dim × 8192 ctx × 2 (K+V) × 2 bytes
= ~2GB KV cache for 8K context
= ~8GB KV cache for 32K context
```

## Memory Optimization Techniques

### Quantization
Reduces precision to save memory:
- **Q8_0**: 8-bit integer, good quality, 75% reduction vs FP32
- **Q5_K_M**: 5-bit mixed precision, balanced quality/size
- **Q4_K_M**: 4-bit mixed precision, 87.5% reduction vs FP32
- **Q3**: Aggressive compression, noticeable quality loss
- **GGUF format**: Optimized quantized format (used by Ollama)

### Model Offloading
Split model across devices:
- **GPU Layers**: Most layers on GPU (fast)
- **CPU Layers**: Remaining layers on CPU (slower)
- **Disk Offloading**: Rarely used layers paged from disk (very slow)
- **Ollama**: Automatically manages GPU memory, spills to CPU/disk

### Batching Strategies
- **Static Batching**: Process fixed batch size
- **Dynamic Batching**: Accumulate requests until batch size or timeout
- **Continuous Batching**: Stream tokens while processing next requests
- **Memory Trade-off**: Larger batches = better throughput but more RAM

### KV Cache Management
- **Sliding Window**: Keep only recent tokens (limited context)
- **Token Eviction**: Remove least important tokens (attention-based)
- **Chunked Processing**: Process long documents in segments
- **Recomputation**: Recompute instead of cache (time vs memory trade-off)

## SLM-Boot Memory Configuration

### Systemd Service Limits
```nix
systemd.services.ollama = {
  serviceConfig = {
    MemoryMax = "4G";         # Prevent runaway memory usage
    MemoryHigh = "3.5G";      # Start throttling here
  };
};
```

### Ollama Environment Variables
```bash
OLLAMA_MAX_LOADED_MODELS=1    # Only keep 1 model in RAM
OLLAMA_NUM_PARALLEL=1         # Process 1 request at a time
OLLAMA_MAX_QUEUE=10           # Queue up to 10 requests
```

### Model Selection by RAM
```
Available RAM → Recommended Models:
4GB: qwen3:0.6b (Q5_K_M), phi4:mini
8GB: qwen3:4b (Q5_K_M), llama3.1:3b, mistral:7b (Q4)
16GB: llama3.1:8b (Q5_K_M), mistral:7b (Q8), command-r:7b
32GB+: llama3.1:70b (Q4), mixtral:8x7b, larger models
```

## Monitoring and Troubleshooting

### Memory Pressure Indicators
```bash
# Check overall memory usage
free -h

# Watch for swapping
vmstat 1

# Memory pressure stalls (cgroups v2)
cat /proc/pressure/memory

# Per-process memory
ps aux --sort=-%mem | head

# Ollama-specific
journalctl -u ollama -f
```

### Warning Signs
1. **High Swap Usage**: Model weights swapping out (very slow)
2. **OOM Kills**: Processes terminated unexpectedly
3. **Slow Inference**: Excessive paging, thrashing
4. **Failed Allocations**: Model won't load at all

### Solutions
1. **Use Smaller Model**: Reduce parameter count or quantization
2. **Reduce Context**: Shorter prompts = less KV cache
3. **Add More RAM**: Hardware upgrade if needed
4. **Use zram**: Fast compressed swap as safety net
5. **Enable Offloading**: Let Ollama spill to disk gracefully

## Best Practices for SLM-Boot

### Graphical ISO (Live USB)
- 8GB RAM minimum: Supports qwen3:0.6b + desktop
- 16GB RAM recommended: Better experience, larger models possible
- zram swap: Compressed RAM swap for safety

### Headless Deployment
- 4GB RAM minimum: Headless + qwen3:0.6b
- No desktop overhead: More RAM available for models
- Swap on SSD: Graceful degradation

### Production Considerations
1. Monitor memory pressure continuously
2. Set conservative MemoryMax limits
3. Use appropriate model for available RAM
4. Test under realistic concurrent load
5. Plan for peak usage, not average""",
        "source": "ram_optimization_ai",
        "chunk_index": 2,
        "total_chunks": 2
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
