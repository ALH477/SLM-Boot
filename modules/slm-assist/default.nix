# modules/slm-assist/default.nix
#
# Production-ready NixOS module for SLM-Assist
#
{ config, lib, pkgs, ... }:

let
  cfg = config.services.slm-assist;

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

  graphicalUser = if config.services.displayManager.enable
    then config.services.displayManager.user or "nobody"
    else "nobody";

  authScript = pkgs.writeShellScript "gradio-with-auth" ''
    #!/usr/bin/env bash
    export GRADIO_USERNAME="${cfg.authentication.username}"
    export GRADIO_PASSWORD="${cfg.authentication.password}"
    exec ${pythonEnv}/bin/python ${scriptPath} --auth
  '';

  validateModelsScript = pkgs.writeShellScript "validate-ollama-models" ''
    #!/usr/bin/env bash
    set -e

    MODEL_DIR="/var/lib/ollama/models"
    echo "Validating Ollama model installation..."

    if [ ! -d "$MODEL_DIR" ]; then
      echo "ERROR: Model directory $MODEL_DIR does not exist"
      exit 1
    fi

    MANIFEST_COUNT=$(find "$MODEL_DIR/manifests" -type f 2>/dev/null | wc -l)
    if [ "$MANIFEST_COUNT" -eq 0 ]; then
      echo "ERROR: No model manifests found in $MODEL_DIR/manifests"
      echo "Expected model: ${cfg.ollamaModel}"
      exit 1
    fi

    BLOB_COUNT=$(find "$MODEL_DIR/blobs" -type f 2>/dev/null | wc -l)
    if [ "$BLOB_COUNT" -eq 0 ]; then
      echo "ERROR: No model blobs found in $MODEL_DIR/blobs"
      exit 1
    fi

    echo "✓ Found $MANIFEST_COUNT manifest(s) and $BLOB_COUNT blob(s)"
    echo "✓ Model validation passed"
  '';

in {
  options.services.slm-assist = with lib; {
    enable = mkEnableOption "Enable SLM Assist — local DSPy RAG with Ollama + Gradio UI";

    ollamaModel = mkOption {
      type = types.str;
      default = "qwen3:0.6b";
      example = "qwen3:4b";
      description = "Ollama model tag (actual files must be pre-baked in ./models)";
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

    logDir = mkOption {
      type = types.path;
      default = "/var/log/slm-assist";
      description = "Directory for application logs";
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
      default = 120;
      example = 180;
      description = ''
        Minimum delay (in seconds) before starting the Gradio UI after boot.
        Combined with ExecStartPre polling for better reliability.
      '';
    };

    autoOpenBrowser = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Automatically open Floorp browser to the Gradio interface.
        Only effective on graphical profiles.
      '';
    };

    authentication = {
      enable = mkEnableOption "Enable basic authentication for Gradio interface";
      
      username = mkOption {
        type = types.str;
        default = "admin";
        description = "Username for Gradio authentication";
      };

      password = mkOption {
        type = types.str;
        default = "";
        description = "Password for Gradio authentication (leave empty to disable)";
      };
    };

    resourceLimits = {
      maxMemoryMB = mkOption {
        type = types.nullOr types.int;
        default = 4096;
        example = 8192;
        description = "Maximum memory usage in MB (null for unlimited)";
      };

      cpuQuota = mkOption {
        type = types.nullOr types.int;
        default = 200;
        example = 400;
        description = "CPU quota percentage (100 = 1 core, null for unlimited)";
      };

      maxTasks = mkOption {
        type = types.int;
        default = 100;
        description = "Maximum number of tasks/threads";
      };
    };

    validateModels = mkOption {
      type = types.bool;
      default = true;
      description = "Validate model files exist before starting service";
    };
  };

  config = lib.mkIf cfg.enable {
    services.ollama = lib.mkMerge [
      {
        enable = true;
        loadModels = lib.mkForce [ ];
      }
      cfg.extraOllamaConfig
    ];

    systemd.services."ollama-prepull-${cfg.ollamaModel}".enable = false;

    users.users.slm-assist = {
      isSystemUser = true;
      group = "slm-assist";
      home = cfg.dataDir;
      createHome = false;
    };

    users.groups.slm-assist = {};

    systemd.services.slm-assist = {
      description = "SLM Assist — DSPy RAG Gradio Web UI";
      after = [
        "network.target"
        "ollama.service"
        "systemd-tmpfiles-setup.service"
      ];
      wantedBy = lib.mkIf (!delayEnabled) [ "multi-user.target" ];

      serviceConfig.ExecStartPre = [
        (lib.mkIf cfg.validateModels validateModelsScript)
        (pkgs.writeShellScript "wait-for-ollama" ''
          #!/usr/bin/env bash
          set -e

          echo "Waiting for Ollama to become responsive..."
          
          for i in $(seq 1 60); do
            if ${pkgs.curl}/bin/curl -fs --connect-timeout 2 http://127.0.0.1:11434 >/dev/null 2>&1; then
              echo "Ollama is ready (took ~$((i*3)) seconds)"
              exit 0
            fi
            [ $((i % 10)) -eq 0 ] && echo "Still waiting for Ollama... ($((i*3))s elapsed)"
            sleep 3
          done

          echo "ERROR: Ollama failed to start within 180 seconds"
          exit 1
        '')
      ];

      serviceConfig = {
        ExecStart = if cfg.authentication.enable && cfg.authentication.password != ""
          then authScript
          else "${pythonEnv}/bin/python ${scriptPath}";
        
        Restart = "always";
        RestartSec = 5;
        
        User = "slm-assist";
        Group = "slm-assist";
        
        WorkingDirectory = cfg.dataDir;
        
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadOnlyPaths = [ "/var/lib/ollama" ];
        
        MemoryMax = lib.mkIf (cfg.resourceLimits.maxMemoryMB != null)
          "${toString cfg.resourceLimits.maxMemoryMB}M";
        CPUQuota = lib.mkIf (cfg.resourceLimits.cpuQuota != null)
          "${toString cfg.resourceLimits.cpuQuota}%";
        TasksMax = toString cfg.resourceLimits.maxTasks;
        
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "slm-assist";
      };

      environment = {
        OLLAMA_HOST = "http://127.0.0.1:11434";
        PYTHONUNBUFFERED = "1";
        OLLAMA_MODELS = "/var/lib/ollama/models";
        OLLAMA_MODEL = cfg.ollamaModel;
        SLM_DATA_DIR = cfg.dataDir;
        SLM_LOG_DIR = cfg.logDir;
      };
    };

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
        "systemd-tmpfiles-setup.service"
      ];
      requires = [ "ollama.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.systemd}/bin/systemctl start slm-assist.service";
      };
    };

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
        
        ExecStart = pkgs.writeShellScript "wait-and-launch-browser" ''
          #!/usr/bin/env bash
          set -e

          echo "Waiting for Ollama to become responsive..."
          for i in $(seq 1 180); do
            if ${pkgs.curl}/bin/curl -fs --connect-timeout 2 http://127.0.0.1:11434 >/dev/null 2>&1; then
              echo "Ollama is ready (took ~$((i*2)) seconds)"
              break
            fi
            [ $((i % 15)) -eq 0 ] && echo "Still waiting for Ollama... ($((i*2))s elapsed)"
            sleep 2
          done

          echo "Waiting for Gradio interface to become responsive..."
          for i in $(seq 1 60); do
            if ${pkgs.curl}/bin/curl -fs --connect-timeout 2 ${gradioUrl} >/dev/null 2>&1; then
              echo "Gradio is ready (took ~$((i*2)) seconds)"
              break
            fi
            [ $((i % 10)) -eq 0 ] && echo "Still waiting for Gradio... ($((i*2))s elapsed)"
            sleep 2
          done

          sleep 2
          echo "Launching Floorp → ${gradioUrl}"
          exec ${pkgs.floorp-bin}/bin/floorp-bin --new-window ${gradioUrl}
        '';
        
        User = graphicalUser;
        Environment = [
          "DISPLAY=:0"
          "WAYLAND_DISPLAY=wayland-0"
          "XDG_RUNTIME_DIR=/run/user/1000"
        ];
      };
    };

    warnings = lib.flatten [
      (lib.optional 
        (cfg.autoOpenBrowser && graphicalUser == "nobody")
        "slm-assist.autoOpenBrowser is enabled but no display manager user detected")
      
      (lib.optional
        (cfg.authentication.enable && cfg.authentication.password == "")
        "slm-assist.authentication is enabled but no password is set - authentication will be disabled")
      
      (lib.optional
        (cfg.exposeExternally && !cfg.authentication.enable)
        "slm-assist.exposeExternally is enabled without authentication - this is a security risk")
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 slm-assist slm-assist - -"
      "C ${cfg.dataDir}/ragqa_arena_tech_corpus.jsonl - - - - ${./corpus/ragqa_arena_tech_corpus.jsonl}"
      "Z ${cfg.dataDir} 0755 slm-assist slm-assist - -"

      "d ${cfg.logDir} 0755 slm-assist slm-assist - -"

      "d /var/lib/ollama                0755 ollama ollama - -"
      "d /var/lib/ollama/models         0755 ollama ollama - -"
      "d /var/lib/ollama/models/blobs   0755 ollama ollama - -"
      "d /var/lib/ollama/models/manifests 0755 ollama ollama - -"

      "C+ /var/lib/ollama/models - - - - ${./models}"
      "Z+ /var/lib/ollama/models 0755 ollama ollama - -"
    ];

    services.logrotate.settings.slm-assist = {
      files = "${cfg.logDir}/*.log";
      frequency = "daily";
      rotate = 7;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "0644 slm-assist slm-assist";
    };

    environment.systemPackages = [ 
      pkgs.ollama 
      pkgs.floorp-bin
      pkgs.htop
      pkgs.iotop
    ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.exposeExternally [
      cfg.gradioPort
    ];
  };
}
