{
  description = "DSPy local RAG with Ollama + Gradio web UI (FAISS + sentence-transformers)";

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
          "dspy-ai==2.5.0"                # stable recent version – update if you prefer newer
          "faiss-cpu==1.9.0"
          "ujson"
          "sentence-transformers==3.1.1"
          "numpy"
          "gradio==5.9.1"                 # latest stable Gradio in late 2025
        ];

      in {
        devShells.default = pkgs.mkShell {
          name = "dspy-rag-gradio-shell";

          packages = [
            python
            pkgs.ollama
            pkgs.uv                   # fast installer (optional but speeds things up)
          ];

          shellHook = ''
            echo "→ DSPy RAG + Gradio UI dev shell (local Ollama)"
            echo "→ Python: $(python --version)"
            echo "→ Ollama: $(ollama --version 2>/dev/null || echo 'not found')"

            # Create venv if missing
            [ ! -d ".venv" ] && {
              echo "→ Creating virtual environment..."
              python -m venv .venv --prompt dspy-rag
            }

            source .venv/bin/activate

            echo "→ Installing / updating dependencies..."
            pip install --upgrade pip setuptools wheel
            uv pip install --quiet ${builtins.concatStringsSep " " pipPackages} || \
              pip install --quiet ${builtins.concatStringsSep " " pipPackages}

            cat << EOF

            Quick start:

            1. Start Ollama server in another terminal:
               $ ollama serve

            2. Pull model(s) if needed:
               $ ollama pull llama3.1:8b     # or llama3, phi4, gemma2:9b, etc.

            3. Put your corpus here:
               ./data/ragqa_arena_tech_corpus.jsonl
               (download: https://huggingface.co/dspy/cache/resolve/main/ragqa_arena_tech_corpus.jsonl)

            4. Run the Gradio app:
               $ python rag_app.py

            → Open http://127.0.0.1:7860 in your browser

            Happy building!
            EOF
          '';
        };
      }
    );
}
