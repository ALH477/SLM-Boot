{ config, lib, pkgs, ... }:

let
  cfg = config.services.slm-assist;

  pythonEnv = pkgs.python312.withPackages (ps: with ps; [
    dspy-ai
    faiss-cpu
    ujson
    sentence-transformers
    numpy
    gradio
  ]);

  scriptPath = "${./rag_app.py}";

in {
  options.services.slm-assist = with lib; {
    enable = mkEnableOption "SLM Assist — local DSPy RAG with Ollama + Gradio UI";

    ollamaModel = mkOption {
      type = types.str;
      default = "llama3.1:8b";
      description = "Ollama model tag to pull and use (e.g. llama3.1:8b, phi4:mini, gemma2:9b)";
    };

    gradioPort = mkOption {
      type = types.port;
      default = 7861;
      description = "Port for the Gradio web interface";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/slm-assist";
      description = "Directory where the corpus and FAISS index will live";
    };

    extraOllamaConfig = mkOption {
      type = types.attrs;
      default = { acceleration = true; };
      description = "Extra configuration for services.ollama";
    };

    exposeExternally = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the Gradio port in the firewall";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ollama as a system service
    services.ollama = {
      enable = true;
    } // cfg.extraOllamaConfig;

    # Pre-pull the requested model during activation
    systemd.services."ollama-prepull-${cfg.ollamaModel}" = {
      description = "Pull Ollama model for SLM Assist";
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

    # Gradio RAG application as a systemd service
    systemd.services.slm-assist = {
      description = "SLM Assist — DSPy RAG Gradio Web UI";
      after = [ "network.target" "ollama.service" "ollama-prepull-${cfg.ollamaModel}.service" ];
      wantedBy = [ "multi-user.target" ];
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

    # Ensure data directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root - -"
      "Z ${cfg.dataDir} 0755 root root - -"
    ];

    # Make ollama CLI available system-wide
    environment.systemPackages = [ pkgs.ollama ];

    # Optional: open firewall port
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.exposeExternally [
      cfg.gradioPort
    ];
  };
}
