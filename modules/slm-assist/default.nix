# modules/slm-assist/default.nix
#
# NixOS module for SLM-Assist:
#   - Local DSPy RAG system using Ollama + Gradio web interface
#   - Delayed startup to give Ollama time to initialize
#   - Optional automatic browser launch (Floorp) to the Gradio UI
#
# Features:
#   - Ollama runs as system service with pre-pull of selected model
#   - Gradio app runs as DynamicUser service
#   - Configurable delay before Gradio starts
#   - Optional Floorp auto-launch on graphical profiles
#   - Corpus baked into dataDir via tmpfiles
#
# Usage in flake.nix:
#   services.slm-assist = {
#     enable = true;
#     delayStartSec = 45;
#     autoOpenBrowser = true;   # only useful on graphical profiles
#     ...
#   };
{ config, lib, pkgs, ... }:

let
  cfg = config.services.slm-assist;

  # Fetch and build dspy-ai from PyPI (not in nixpkgs)
  dspyAi = pkgs.python312Packages.buildPythonPackage rec {
    pname = "dspy-ai";
    version = "2.5.0";  # latest stable as of late 2025 – update if needed
    format = "pyproject";

    src = pkgs.fetchPypi {
      inherit pname version;
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # ← REPLACE with real hash (see below)
    };

    nativeBuildInputs = with pkgs.python312Packages; [
      setuptools
      wheel
    ];

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
      # add more deps from https://pypi.org/project/dspy-ai/#files or setup.py if build fails
    ];

    doCheck = false;  # skip tests for faster build (safe for production image)
  };

  # Python environment with all required packages (including custom dspy-ai)
  pythonEnv = pkgs.python312.withPackages (ps: with ps; [
    dspyAi           # ← our custom package
    faiss-cpu
    ujson
    sentence-transformers
    numpy
    gradio
  ]);

  # Path to the Gradio application script (relative to this module)
  scriptPath = "${./rag_app.py}";

  # Whether delayed start is active
  delayEnabled = cfg.enable && cfg.delayStartSec > 0;

  # URL where Gradio will be listening
  gradioUrl = "http://127.0.0.1:${toString cfg.gradioPort}";

in {
  options.services.slm-assist = with lib; {
    enable = mkEnableOption "Enable SLM Assist — local DSPy RAG with Ollama + Gradio UI";

    ollamaModel = mkOption {
      type = types.str;
      default = "qwen3:0.6b-instruct-q5_K_M";
      example = "qwen3:4b-instruct-q5_K_M";
      description = "Ollama model tag to pull and use";
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
      description = "Delay (in seconds) before starting Gradio UI after boot";
    };

    autoOpenBrowser = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically open Floorp to Gradio after delay (graphical only)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ────────────────────────────────────────────────────────────────
    # Ollama system service (no deprecated acceleration option)
    # ────────────────────────────────────────────────────────────────
    services.ollama = lib.mkMerge [
      {
        enable = true;
        # Optional GPU backend (uncomment one if you have hardware)
        # package = pkgs.ollama-cuda;   # NVIDIA
        # package = pkgs.ollama-rocm;   # AMD
        # package = pkgs.ollama;        # CPU (default)
      }
      cfg.extraOllamaConfig
    ];

    # Pre-pull the selected model
    systemd.services."ollama-prepull-${cfg.ollamaModel}" = {
      description = "Pre-pull Ollama model for SLM Assist";
      wantedBy = [ "multi-user.target" ];
      after = [ "ollama.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.ollama}/bin/ollama pull ${cfg.ollamaModel}";
        RemainAfterExit = true;
        User = "ollama";
        Group = "ollama";
      };
    };

    # ────────────────────────────────────────────────────────────────
    # Gradio RAG application service
    # ────────────────────────────────────────────────────────────────
    systemd.services.slm-assist = {
      description = "SLM Assist — DSPy RAG Gradio Web UI";
      after = [
        "network.target"
        "ollama.service"
        "ollama-prepull-${cfg.ollamaModel}.service"
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
      };
    };

    # ────────────────────────────────────────────────────────────────
    # Delayed startup (timer + activator)
    # ────────────────────────────────────────────────────────────────
    systemd.timers.slm-assist-delayed = lib.mkIf delayEnabled {
      description = "Delayed startup timer for SLM Assist Gradio UI";
      wantedBy = [ "timers.target" ];
      timerConfig.OnBootSec = "${toString cfg.delayStartSec}";
    };

    systemd.services.slm-assist-activator = lib.mkIf delayEnabled {
      description = "Delayed activation of SLM Assist Gradio service";
      after = [
        "ollama.service"
        "ollama-prepull-${cfg.ollamaModel}.service"
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
        ExecStart = "${pkgs.floorp}/bin/floorp --new-window ${gradioUrl}";
        User = "gdm";  # adjust to sddm/lightdm if needed
        Environment = "DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000";
      };
    };

    # ────────────────────────────────────────────────────────────────
    # Data directory setup + corpus baking
    # ────────────────────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 slm-assist slm-assist - -"
      "C ${cfg.dataDir}/ragqa_arena_tech_corpus.jsonl - - - - ${./corpus/ragqa_arena_tech_corpus.jsonl}"
      "Z ${cfg.dataDir} 0755 slm-assist slm-assist - -"
    ];

    # ────────────────────────────────────────────────────────────────
    # System packages & firewall
    # ────────────────────────────────────────────────────────────────
    environment.systemPackages = [ pkgs.ollama pkgs.floorp ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.exposeExternally [
      cfg.gradioPort
    ];
  };
}
