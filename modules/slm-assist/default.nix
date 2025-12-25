# modules/slm-assist/default.nix
#
# NixOS module for SLM-Assist — production-ready local DSPy RAG system
#
# Features:
#   - Offline-first: Ollama model & corpus baked via tmpfiles
#   - Delayed & polled startup to handle slow hardware (USB 2.0, old CPUs)
#   - Automatic Floorp launch after Ollama readiness check
#   - Hardened systemd services (DynamicUser, Protect*, Private*)
#   - Environment passthrough for model name & paths
#   - Fallback-friendly (oterm works even on slow boots)
#
# Recommended usage:
#   - USB 3.0+ for best experience (1–2 min wait)
#   - USB 2.0 supported but expect 3–8+ min wait — use oterm fallback
#
{ config, lib, pkgs, ... }:

let
  cfg = config.services.slm-assist;

  # ────────────────────────────────────────────────────────────────
  # Custom package: dspy-ai (not yet in nixpkgs as of Dec 2025)
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
      example = "qwen3:4b-instruct-q5_K_M";
      description = "Ollama model tag (used for env var and reference; files must be pre-baked in ./models)";
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

    exposeExternally = mkOption {
      type = types.bool;
      default = false;
      description = "Open Gradio port in firewall (not recommended for offline/air-gapped use)";
    };

    delayStartSec = mkOption {
      type = types.int;
      default = 180;  # 3 minutes — safer for USB 2.0 / older hardware
      example = 300;
      description = ''
        Minimum delay (seconds) before starting Gradio after boot.
        Combined with ExecStartPre polling for robustness.
      '';
    };

    autoOpenBrowser = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Automatically open Floorp to Gradio UI after Ollama readiness check.
        Only effective on graphical profiles.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # ────────────────────────────────────────────────────────────────
    # Ollama system service – strictly offline
    # ────────────────────────────────────────────────────────────────
    services.ollama = lib.mkMerge [
      {
        enable = true;
        loadModels = lib.mkForce [ ];  # no declarative pulling
      }
      cfg.extraOllamaConfig
    ];

    systemd.services."ollama-prepull-${cfg.ollamaModel}".enable = false;

    # ────────────────────────────────────────────────────────────────
    # Gradio RAG application service
    # ────────────────────────────────────────────────────────────────
    systemd.services.slm-assist = {
      description = "SLM Assist — DSPy RAG Gradio Web UI";
      after = [ "network.target" "ollama.service" ];
      wantedBy = lib.mkIf (!delayEnabled) [ "multi-user.target" ];

      # Poll Ollama readiness before starting Python (critical for slow boots)
      serviceConfig.ExecStartPre = ''
        /bin/sh -c 'echo "Waiting for Ollama model load (USB 2.0 may take 5+ min)..."; \
                    for i in $(seq 1 180); do \
                      if curl -fs --connect-timeout 3 http://127.0.0.1:11434 >/dev/null 2>&1; then break; fi; \
                      [ $((i % 20)) -eq 0 ] && echo "Still waiting... ($((i*3))s elapsed)"; \
                      sleep 3; \
                    done; \
                    echo "Ollama ready - starting Gradio"'
      '';

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
        ProtectKernelTunables = true;
        ProtectClock = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };

      environment = {
        OLLAMA_HOST = "http://127.0.0.1:11434";
        PYTHONUNBUFFERED = "1";
        OLLAMA_MODELS = "/var/lib/ollama/models";
        OLLAMA_MODEL = cfg.ollamaModel;  # Passed to Python for auto-detection priority
      };
    };

    # ────────────────────────────────────────────────────────────────
    # Delayed startup timer + activator
    # ────────────────────────────────────────────────────────────────
    systemd.timers.slm-assist-delayed = lib.mkIf delayEnabled {
      description = "Delayed startup timer for SLM Assist Gradio UI";
      wantedBy = [ "timers.target" ];
      timerConfig.OnBootSec = "${toString cfg.delayStartSec}";
    };

    systemd.services.slm-assist-activator = lib.mkIf delayEnabled {
      description = "Delayed activation of SLM Assist Gradio service";
      after = [ "ollama.service" "network.target" ];
      requires = [ "ollama.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.systemd}/bin/systemctl start slm-assist.service";
      };
    };

    # ────────────────────────────────────────────────────────────────
    # Auto-launch Floorp after Ollama readiness (graphical only)
    # ────────────────────────────────────────────────────────────────
    systemd.services.slm-assist-browser-launch = lib.mkIf (delayEnabled && cfg.autoOpenBrowser) {
      description = "Launch Floorp browser to SLM Assist Gradio interface";
      after = [ "slm-assist-activator.service" "graphical.target" ];
      requires = [ "slm-assist.service" ];
      wantedBy = [ "graphical.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "wait-for-ollama-and-launch-floorp" ''
          #!/usr/bin/env sh
          set -e

          echo "Waiting for Ollama to become responsive..."

          for i in $(seq 1 180); do
            if ${pkgs.curl}/bin/curl -fs --connect-timeout 2 http://127.0.0.1:11434 >/dev/null 2>&1; then
              echo "Ollama is ready (took ~$((i*2)) seconds)"
              break
            fi
            [ $((i % 15)) -eq 0 ] && echo "Still waiting... ($((i*2))s elapsed)"
            sleep 2
          done

          sleep 5  # final buffer for model warmup
          echo "Launching Floorp → ${gradioUrl}"
          exec ${pkgs.floorp-bin}/bin/floorp-bin --new-window ${gradioUrl}
        '';
        User = "gdm";  # change to sddm/lightdm user if needed
        Environment = "DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000";
      };
    };

    # ────────────────────────────────────────────────────────────────
    # Data + model directory setup (offline baking)
    # ────────────────────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      # SLM-Assist data + corpus
      "d ${cfg.dataDir} 0755 slm-assist slm-assist - -"
      "C ${cfg.dataDir}/ragqa_arena_tech_corpus.jsonl - - - - ${./corpus/ragqa_arena_tech_corpus.jsonl}"
      "Z ${cfg.dataDir} 0755 slm-assist slm-assist - -"

      # Ollama models directory structure
      "d /var/lib/ollama                0755 ollama ollama - -"
      "d /var/lib/ollama/models         0755 ollama ollama - -"
      "d /var/lib/ollama/models/blobs   0755 ollama ollama - -"
      "d /var/lib/ollama/models/manifests 0755 ollama ollama - -"

      # Bake pre-downloaded model files (recursive copy)
      "C+ /var/lib/ollama/models - - - - ${./models}"

      # Make models readable by everyone after copy (for oterm fallback, debug, etc.)
      "Z /var/lib/ollama/models 0755 ollama ollama - -"
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
