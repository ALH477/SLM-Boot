{
  description = "DSPy local RAG with Ollama + Gradio web UI (FAISS + sentence-transformers) - Production Ready";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        python = pkgs.python312;

        pipPackages = [
          "dspy-ai==2.5.0"
          "faiss-cpu==1.9.0"
          "ujson==5.10.0"
          "sentence-transformers==3.1.1"
          "numpy==1.26.4"
          "gradio==5.9.1"
        ];

      in {
        devShells.default = pkgs.mkShell {
          name = "dspy-rag-gradio-shell";

          packages = [
            python
            pkgs.ollama
            pkgs.uv
            pkgs.htop
            pkgs.curl
            pkgs.jq
          ];

          shellHook = ''
            echo "═══════════════════════════════════════════════════════════════"
            echo "  DSPy RAG + Gradio UI Development Shell (Production Ready)"
            echo "═══════════════════════════════════════════════════════════════"
            echo ""
            echo "→ Python: $(python --version)"
            echo "→ Ollama: $(ollama --version 2>/dev/null || echo 'not found - install with: nix-env -iA nixpkgs.ollama')"
            echo ""

            if [ ! -d ".venv" ]; then
              echo "→ Creating virtual environment..."
              python -m venv .venv --prompt dspy-rag
            fi

            source .venv/bin/activate

            echo "→ Installing / updating dependencies..."
            pip install --upgrade pip setuptools wheel >/dev/null 2>&1
            uv pip install --quiet ${builtins.concatStringsSep " " pipPackages} 2>/dev/null || \
              pip install --quiet ${builtins.concatStringsSep " " pipPackages}

            mkdir -p corpus
            mkdir -p logs

            if [ ! -f ".env" ]; then
              cat > .env << 'ENVEOF'
# SLM-Assist Configuration
export SLM_DATA_DIR="$(pwd)"
export SLM_LOG_DIR="$(pwd)/logs"
export OLLAMA_HOST="http://127.0.0.1:11434"
export OLLAMA_MODEL="qwen3:0.6b"
ENVEOF
              echo "→ Created .env file - customize as needed"
            fi

            [ -f .env ] && source .env

            cat << 'EOF'

═══════════════════════════════════════════════════════════════
Quick Start Guide - Development Mode
═══════════════════════════════════════════════════════════════

1. Start Ollama server (in another terminal):
   $ ollama serve

2. Pull a model (choose one based on your hardware):
   
   Lightweight (< 1GB RAM):
   $ ollama pull qwen3:0.6b
   
   Balanced (2-4GB RAM):
   $ ollama pull llama3.2:3b
   $ ollama pull phi4:3.8b
   
   High quality (8GB+ RAM):
   $ ollama pull llama3.1:8b
   $ ollama pull qwen3:14b

3. Download the corpus:
   $ wget -O corpus/ragqa_arena_tech_corpus.jsonl \
       https://huggingface.co/dspy/cache/resolve/main/ragqa_arena_tech_corpus.jsonl
   
   Or for faster download:
   $ curl -L -o corpus/ragqa_arena_tech_corpus.jsonl \
       https://huggingface.co/dspy/cache/resolve/main/ragqa_arena_tech_corpus.jsonl

4. Configure environment (optional):
   $ nano .env
   $ source .env

5. Run the application:
   $ python rag_app.py

6. Open in browser:
   → http://127.0.0.1:7860

═══════════════════════════════════════════════════════════════
Monitoring & Troubleshooting
═══════════════════════════════════════════════════════════════

Check Ollama status:
  $ curl http://127.0.0.1:11434/api/tags | jq

View logs:
  $ tail -f logs/slm-assist.log

Check system resources:
  $ htop

Test query performance:
  $ time curl -X POST http://127.0.0.1:7860/api/predict \
      -H "Content-Type: application/json" \
      -d '{"data": ["What is Python?"]}'

═══════════════════════════════════════════════════════════════
Production Deployment
═══════════════════════════════════════════════════════════════

For NixOS production deployment:

1. Copy module to your NixOS config:
   $ cp default.nix /etc/nixos/modules/slm-assist.nix

2. Import in configuration.nix:
   imports = [ ./modules/slm-assist.nix ];

3. Configure service:
   services.slm-assist = {
     enable = true;
     ollamaModel = "qwen3:0.6b";
     
     authentication.enable = true;
     authentication.password = "your-secure-password";
     exposeExternally = false;
     
     resourceLimits = {
       maxMemoryMB = 4096;
       cpuQuota = 200;
     };
     
     delayStartSec = 120;
     autoOpenBrowser = true;
   };

4. Pre-bake models into ./models/ directory:
   $ mkdir -p models/blobs models/manifests

5. Rebuild system:
   $ sudo nixos-rebuild switch

6. Monitor:
   $ journalctl -u slm-assist.service -f
   $ systemctl status slm-assist.service

Happy building!
EOF
          '';
        };
      }
    );
}
