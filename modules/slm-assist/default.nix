# modules/slm-assist/default.nix
#
# NixOS module for SLM-Assist:
#   - Local DSPy RAG system using Ollama + Gradio web interface
#   - Delayed startup to give Ollama time to initialize
#   - Optional automatic browser launch (Floorp) to the Gradio UI
#   - Corpus baked into dataDir via tmpfiles
#
# Changes for offline model support (Dec 2025):
#   - Model files are expected in ${./models/<model-name>} in the flake repo
#   - Pre-pull service is disabled
#   - Model blobs/manifests are copied into /var/lib/ollama/models at boot
#
{ config, lib, pkgs, ... }:

let
  cfg = config.services.slm-assist;

  # ────────────────────────────────────────────────────────────────
  # Custom package: only dspy-ai is not in nixpkgs
  # ────────────────────────────────────────────────────────────────

  dspyAi = pkgs.python312Packages.buildPythonPackage rec {
    pname = "dspy-ai";
    version = "2.5.0";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/py3/d/dspy_ai/dspy_ai-${version}-py3-none-any.whl";
      hash = "sha256-4Iad3ZiPYdknuoTlLftC49HnZ0B+hMJa5w1UMmGjHAY=";
    };

    propagatedBuildInputs = with pkgs.python312Packages; [
      openai
      requests
      pandas
      regex
      ujson
      datasets
      optuna
      tqdm
      backoff
      joblib
      numpy
      pydantic
    ];

    doCheck = false;
    pythonImportsCheck = [ ];
  };

  pythonEnv = pkgs.python312.withPackages (ps: with ps; [
    dspyAi
    faiss
    sentence-transformers
    ujson
    numpy
    gradio
  ]);

  scriptPath = "${./rag_app.py}";

  delayEnabled = cfg.enable && cfg.delayStartSec > 0;

  gradioUrl = "http://127.0.0.1:${toString cfg.gradioPort}";

in {
  options.services.slm-assist = with lib; {
    enable = mkEnableOption "Enable SLM Assist — local DSPy RAG with Ollama + Gradio UI";

    ollamaModel = mkOption {
      type = types.str;
      default = "qwen3:0.6b";
      example = "qwen3:4b";
      description = "Ollama model tag (used for naming and reference; actual files must be pre-baked)";
    };

    gradioPort = mkOption {
      type = types.port;
      default = 7861;
      description = "TCP port for the Gradio web interface";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/slm-assist";
      description = "Directory for corpus files, FAISS index, and application data";
    };

    extraOllamaConfig = mkOption {
      type = types.attrs;
      default = { };
      description = "Extra configuration attributes passed to services.ollama";
    };

    exposeExternally = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the Gradio port in the firewall";
    };

    delayStartSec = mkOption {
      type = types.int;
      default = 0;
      example = 45;
      description = ''
        Delay (in seconds) before starting the Gradio UI after boot.
        Useful to ensure Ollama is fully initialized and responsive.
      '';
    };

    autoOpenBrowser = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Automatically open Floorp browser to the Gradio interface after the delay timer fires.
        Only effective on graphical profiles.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # ────────────────────────────────────────────────────────────────
    # Ollama system service – no automatic pulling
    # ────────────────────────────────────────────────────────────────
    services.ollama = lib.mkMerge [
      {
        enable = true;
        # Prevent any declarative model loading / pulling
        loadModels = lib.mkForce [ ];
        # Optional: GPU if needed
        # package = pkgs.ollama-cuda;
      }
      cfg.extraOllamaConfig
    ];

    # Explicitly disable the old prepull service
    systemd.services."ollama-prepull-${cfg.ollamaModel}" = {
      enable = false;
    };

    # ────────────────────────────────────────────────────────────────
    # Gradio RAG application service
    # ────────────────────────────────────────────────────────────────
    systemd.services.slm-assist = {
      description = "SLM Assist — DSPy RAG Gradio Web UI";
      after = [
        "network.target"
        "ollama.service"
      ];
      wantedBy = lib.mkIf (!delayEnabled) [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = ''
          ${pythonEnv}/bin/python ${scriptPath} \
            --server-port ${toString cfg.gradioPort} \
            --server-name 127.0.0.1
        '';
        Restart = "always";
        RestartSec = 5;
        DynamicUser = true;
        StateDirectory = "slm-assist";
        WorkingDirectory = cfg.dataDir;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
      environment = {
        OLLAMA_HOST = "http://127.0.0.1:11434";
        PYTHONUNBUFFERED = "1";
        # Belt-and-suspenders: tell Ollama exactly where models live
        OLLAMA_MODELS = "/var/lib/ollama/models";
      };
    };

    # ────────────────────────────────────────────────────────────────
    # Delayed startup (timer + activator)
    # ────────────────────────────────────────────────────────────────
    systemd.timers.slm-assist-delayed = lib.mkIf delayEnabled {
      description = "Delayed startup timer for SLM Assist Gradio UI";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "${toString cfg.delayStartSec}";
      };
    };

    systemd.services.slm-assist-activator = lib.mkIf delayEnabled {
      description = "Delayed activation of SLM Assist Gradio service";
      after = [
        "ollama.service"
        "network.target"
      ];
      requires = [ "ollama.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.systemd}/bin/systemctl start slm-assist.service";
      };
    };

    # ────────────────────────────────────────────────────────────────
    # Auto-launch Floorp to Gradio UI (graphical only)
    # ────────────────────────────────────────────────────────────────
    systemd.services.slm-assist-browser-launch = lib.mkIf (delayEnabled && cfg.autoOpenBrowser) {
      description = "Launch Floorp browser to SLM Assist Gradio interface";
      after = [
        "slm-assist-activator.service"
        "graphical.target"
      ];
      requires = [ "slm-assist.service" ];
      wantedBy = [ "graphical.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.floorp-bin}/bin/floorp-bin --new-window ${gradioUrl}";
        User = "gdm";  # adjust if using sddm, lightdm, etc.
        Environment = "DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000";
      };
    };

    # ────────────────────────────────────────────────────────────────
    # Data + model directory setup
    # ────────────────────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      # SLM-Assist data dir + corpus
      "d ${cfg.dataDir} 0755 slm-assist slm-assist - -"
      "C ${cfg.dataDir}/ragqa_arena_tech_corpus.jsonl - - - - ${./corpus/ragqa_arena_tech_corpus.jsonl}"
      "Z ${cfg.dataDir} 0755 slm-assist slm-assist - -"

      # Ollama models directory + bake pre-downloaded model
      "d /var/lib/ollama                0755 ollama ollama - -"
      "d /var/lib/ollama/models         0755 ollama ollama - -"
      "d /var/lib/ollama/models/blobs   0755 ollama ollama - -"
      "d /var/lib/ollama/models/manifests 0755 ollama ollama - -"

      # Copy your pre-downloaded model folder (adjust folder name if different)
      # Example: ./models/qwen3-0.6b must exist in the flake repo
      "C+ /var/lib/ollama/models - - - - ${./models}"
    ];

    # ────────────────────────────────────────────────────────────────
    # System packages & firewall
    # ────────────────────────────────────────────────────────────────
    environment.systemPackages = [ pkgs.ollama pkgs.floorp-bin ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.exposeExternally [
      cfg.gradioPort
    ];
  };
}
