# modules/open-webui-service.nix
#
# Production-ready Open WebUI service for Ollama
#
# Features:
#   - Configurable via options
#   - Offline container image pre-loading
#   - Security hardening
#   - Resource limits
#   - Health checks
#   - Integration with SLM-Assist
#
{ config, lib, pkgs, ... }:

let
  cfg = config.services.open-webui;

  # Container image configuration
  imageRepo = "ghcr.io/open-webui/open-webui";
  imageTag = cfg.imageTag;
  imageFull = "${imageRepo}:${imageTag}";

  # Detect which Ollama service to use
  ollamaService = if config.services.slm-assist.enable
    then "slm-assist.service"  # Use SLM-Assist's Ollama
    else "ollama.service";     # Use standalone Ollama

in {
  options.services.open-webui = with lib; {
    enable = mkEnableOption "Enable Open WebUI frontend for Ollama";

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port to expose Open WebUI on localhost";
    };

    imageTag = mkOption {
      type = types.str;
      default = "0.3.32";  # Pin to stable version
      example = "latest";
      description = "Docker image tag for Open WebUI";
    };

    preloadImage = mkOption {
      type = types.bool;
      default = true;
      description = "Pre-load container image during build (offline mode)";
    };

    ollamaUrl = mkOption {
      type = types.str;
      default = "http://ollama:11434";
      description = "URL to Ollama API (within container network)";
    };

    networkName = mkOption {
      type = types.str;
      default = "ollama-net";
      description = "Podman network name for Ollama communication";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/open-webui";
      description = "Directory for Open WebUI data persistence";
    };

    authentication = {
      enableSignup = mkOption {
        type = types.bool;
        default = false;
        description = "Allow new user signups (security: disable for shared systems)";
      };

      defaultUser = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "admin";
        description = "Default admin user to create (null = no default user)";
      };

      defaultPassword = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "changeme";
        description = "Default admin password (null = random, shown in logs)";
      };
    };

    resourceLimits = {
      memoryMax = mkOption {
        type = types.str;
        default = "1G";
        example = "2G";
        description = "Maximum memory for Open WebUI container";
      };

      memoryHigh = mkOption {
        type = types.str;
        default = "800M";
        example = "1.5G";
        description = "Memory high watermark (starts swap)";
      };

      cpuQuota = mkOption {
        type = types.str;
        default = "50%";
        example = "100%";
        description = "CPU quota (100% = 1 core)";
      };
    };

    offlineMode = mkOption {
      type = types.bool;
      default = true;
      description = "Run in offline mode (no external connections)";
    };

    enableImageGeneration = mkOption {
      type = types.bool;
      default = false;
      description = "Enable image generation features";
    };
  };

  config = lib.mkIf cfg.enable {
    # ────────────────────────────────────────────────────────────────
    # Pre-load container image (for offline operation)
    # ────────────────────────────────────────────────────────────────
    systemd.services.load-openwebui-image = lib.mkIf cfg.preloadImage {
      description = "Pre-load Open WebUI container image";
      wantedBy = [ "multi-user.target" ];
      before = [ "open-webui.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        # Check if image already exists
        if ${pkgs.podman}/bin/podman image exists ${imageFull}; then
          echo "Image ${imageFull} already exists"
          exit 0
        fi

        # Try to load from pre-baked archive (if available)
        if [ -f /var/lib/open-webui-images/open-webui-${imageTag}.tar ]; then
          echo "Loading image from archive..."
          ${pkgs.podman}/bin/podman load -i /var/lib/open-webui-images/open-webui-${imageTag}.tar
        else
          echo "WARNING: Pre-baked image not found, attempting pull..."
          echo "This will fail in offline mode!"
          ${pkgs.podman}/bin/podman pull ${imageFull} || {
            echo "ERROR: Failed to pull image and no archive available"
            exit 1
          }
        fi
      '';
    };

    # ────────────────────────────────────────────────────────────────
    # Create Podman network for Ollama communication
    # ────────────────────────────────────────────────────────────────
    systemd.services.create-ollama-network = {
      description = "Create Podman network for Ollama";
      wantedBy = [ "multi-user.target" ];
      before = [ "open-webui.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        # Check if network already exists
        if ${pkgs.podman}/bin/podman network exists ${cfg.networkName}; then
          echo "Network ${cfg.networkName} already exists"
          exit 0
        fi

        # Create network
        echo "Creating network ${cfg.networkName}..."
        ${pkgs.podman}/bin/podman network create ${cfg.networkName}
      '';
    };

    # ────────────────────────────────────────────────────────────────
    # Open WebUI service
    # ────────────────────────────────────────────────────────────────
    systemd.services.open-webui = {
      description = "Open WebUI Frontend for Ollama";
      after = [ 
        "network.target" 
        ollamaService
        "load-openwebui-image.service"
        "create-ollama-network.service"
      ];
      requires = [ 
        ollamaService
        "create-ollama-network.service"
      ] ++ lib.optional cfg.preloadImage "load-openwebui-image.service";
      
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        # Restart policy
        Restart = "always";
        RestartSec = 10;
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;

        # Resource limits
        MemoryMax = cfg.resourceLimits.memoryMax;
        MemoryHigh = cfg.resourceLimits.memoryHigh;
        CPUQuota = cfg.resourceLimits.cpuQuota;

        # Security
        DynamicUser = true;
        StateDirectory = "open-webui";
        
        # Health check
        ExecStartPre = pkgs.writeShellScript "openwebui-health-check" ''
          # Wait for Ollama to be ready
          echo "Waiting for Ollama API..."
          for i in {1..30}; do
            if ${pkgs.curl}/bin/curl -sf http://127.0.0.1:11434 >/dev/null 2>&1; then
              echo "Ollama is ready"
              exit 0
            fi
            sleep 2
          done
          echo "WARNING: Ollama not responding, starting anyway..."
          exit 0  # Don't fail, just warn
        '';
      };

      script = ''
        exec ${pkgs.podman}/bin/podman run \
          --name open-webui \
          --replace=true \
          --sdnotify=conmon \
          --network ${cfg.networkName} \
          -p ${toString cfg.port}:8080 \
          -v ${cfg.dataDir}:/app/backend/data:Z \
          -e OLLAMA_API_BASE_URL=${cfg.ollamaUrl} \
          -e OFFLINE_MODE=${if cfg.offlineMode then "true" else "false"} \
          -e DISABLE_UPDATES=true \
          -e ENABLE_SIGNUP=${if cfg.authentication.enableSignup then "true" else "false"} \
          -e ENABLE_IMAGE_GENERATION=${if cfg.enableImageGeneration then "true" else "false"} \
          ${lib.optionalString (cfg.authentication.defaultUser != null) 
            "-e DEFAULT_USER_EMAIL=${cfg.authentication.defaultUser}@localhost"} \
          ${lib.optionalString (cfg.authentication.defaultPassword != null)
            "-e DEFAULT_USER_PASSWORD=${cfg.authentication.defaultPassword}"} \
          --cap-drop=ALL \
          --security-opt=no-new-privileges \
          --read-only \
          --tmpfs /tmp \
          --tmpfs /app/backend/data/cache \
          ${imageFull}
      '';
    };

    # ────────────────────────────────────────────────────────────────
    # Firewall configuration (localhost only)
    # ────────────────────────────────────────────────────────────────
    networking.firewall.interfaces.lo.allowedTCPPorts = [ cfg.port ];

    # ────────────────────────────────────────────────────────────────
    # Data directory setup
    # ────────────────────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 open-webui open-webui - -"
      "d /var/lib/open-webui-images 0755 root root - -"
    ];

    # ────────────────────────────────────────────────────────────────
    # User and group
    # ────────────────────────────────────────────────────────────────
    users.users.open-webui = {
      isSystemUser = true;
      group = "open-webui";
      home = cfg.dataDir;
    };

    users.groups.open-webui = {};

    # ────────────────────────────────────────────────────────────────
    # Warnings
    # ────────────────────────────────────────────────────────────────
    warnings = lib.flatten [
      (lib.optional
        (cfg.authentication.enableSignup && cfg.authentication.defaultPassword == null)
        "Open WebUI signup enabled without default password - first user will be admin!")
      
      (lib.optional
        (config.services.slm-assist.enable && cfg.enable)
        "Both Open WebUI and SLM-Assist are enabled - they provide different interfaces to Ollama. See /etc/open-webui-info for details.")
      
      (lib.optional
        (!cfg.preloadImage)
        "Open WebUI image pre-loading disabled - container will try to pull from internet at runtime")
      
      (lib.optional
        (cfg.offlineMode && !cfg.preloadImage)
        "Offline mode enabled but image not pre-loaded - service will likely fail to start")
    ];

    # ────────────────────────────────────────────────────────────────
    # Documentation
    # ────────────────────────────────────────────────────────────────
    environment.etc."open-webui-info".text = ''
      Open WebUI Configuration
      ────────────────────────────────────────────────────────
      Status:          ${if cfg.enable then "Enabled" else "Disabled"}
      Port:            ${toString cfg.port} (localhost only)
      URL:             http://127.0.0.1:${toString cfg.port}
      
      Image:           ${imageFull}
      Pre-loaded:      ${if cfg.preloadImage then "Yes" else "No"}
      Network:         ${cfg.networkName}
      Data Directory:  ${cfg.dataDir}
      
      Features:
        Offline Mode:    ${if cfg.offlineMode then "Enabled" else "Disabled"}
        Signup:          ${if cfg.authentication.enableSignup then "Enabled" else "Disabled"}
        Image Gen:       ${if cfg.enableImageGeneration then "Enabled" else "Disabled"}
      
      Resource Limits:
        Memory Max:      ${cfg.resourceLimits.memoryMax}
        Memory High:     ${cfg.resourceLimits.memoryHigh}
        CPU Quota:       ${cfg.resourceLimits.cpuQuota}
      
      Integration:
        Ollama Service:  ${ollamaService}
        Ollama URL:      ${cfg.ollamaUrl}
        SLM-Assist:      ${if config.services.slm-assist.enable then "Also enabled" else "Not enabled"}
      
      ────────────────────────────────────────────────────────
      
      Open WebUI vs SLM-Assist:
        • Open WebUI:    General chat interface for Ollama
                         Good for: Conversations, experimentation
                         
        • SLM-Assist:    RAG-powered Q&A with document search
                         Good for: Knowledge retrieval, research
      
      Both can coexist - use them for different purposes:
        - Open WebUI for general chat: http://127.0.0.1:${toString cfg.port}
        - SLM-Assist for RAG:          http://127.0.0.1:7861
      
      ────────────────────────────────────────────────────────
      
      Commands:
        systemctl status open-webui             # Check status
        journalctl -u open-webui -f             # View logs
        podman ps | grep open-webui             # Check container
        podman logs open-webui                  # Container logs
        
      Troubleshooting:
        1. Check Ollama is running:
           systemctl status ${ollamaService}
           
        2. Check network exists:
           podman network ls | grep ${cfg.networkName}
           
        3. Check image exists:
           podman image ls | grep open-webui
           
        4. Check container:
           podman inspect open-webui
    '';

    # Add helpful shell aliases
    environment.shellAliases = lib.mkIf cfg.enable {
      "webui-status" = "systemctl status open-webui.service";
      "webui-logs" = "journalctl -u open-webui.service -f";
      "webui-restart" = "sudo systemctl restart open-webui.service";
      "webui-open" = "${pkgs.xdg-utils}/bin/xdg-open http://127.0.0.1:${toString cfg.port} 2>/dev/null || echo 'Open: http://127.0.0.1:${toString cfg.port}'";
    };
  };
}
