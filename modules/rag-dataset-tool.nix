# modules/rag-dataset-tool.nix
{ pkgs, ... }:

let
  ragScript = pkgs.writeScript "rag_dataset_prep.py" (builtins.readFile ../scripts/rag_dataset_prep.py);

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    beautifulsoup4
    pdfplumber
    requests
    nltk
  ]);
in
{
  environment.systemPackages = [
    (pkgs.runCommand "rag-dataset-prep" {
      buildInputs = [ pythonEnv ];
    } ''
      mkdir -p $out/bin
      ln -s ${ragScript} $out/bin/rag-dataset-prep
      chmod +x $out/bin/rag-dataset-prep
    '')
  ];

  system.activationScripts.nltk-data.text = ''
    if ! python -c "import nltk; nltk.data.find('tokenizers/punkt')" 2>/dev/null; then
      echo "Downloading NLTK punkt data..."
      su - nixos -c "python - <<'EOF'
import nltk
nltk.download('punkt', quiet=True)
EOF"
    fi
  '';
}
