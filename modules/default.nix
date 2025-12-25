# modules/default.nix
#
# Default module aggregator for offline AI assistant
#
# This module provides sensible defaults for different deployment profiles:
#   - Graphical (desktop with DWM)
#   - Headless (server/CLI only)
#   - Common (shared between both)
#
# Usage:
#   For graphical: Import this file (includes graphical-minimal.nix)
#   For headless:  Import individual modules or create custom default
#
{ config, lib, pkgs, ... }:

let
  cfg = config.services.offline-assistant;

in {
  options.services.offline-assistant = with lib; {
    profile = mkOption {
      type = types.enum [ "graphical" "headless" "minimal" ];
      default = "graphical";
      description = ''
        Deployment profile for the offline AI assistant:
        - graphical: Full desktop environment with DWM
        - headless: CLI only, no GUI
        - minimal: Only core modules, you configure the rest
      '';
    };

    enableVoicePipeline = mkOption {
      type = types.bool;
      default = false;
      description = "Enable voice interaction pipeline (requires graphical or audio setup)";
    };

    enableSLMAssist = mkOption {
      type = types.bool;
      default = true;
      description = "Enable SLM-Assist RAG system with Ollama + Gradio";
    };

    enableOpenWebUI = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Open WebUI for Ollama";
    };

    enableHardening = mkOption {
      type = types.bool;
      default = true;
      description = "Enable security hardening";
    };
  };

  config = {
    # ────────────────────────────────────────────────────────────────
    # Core modules (always imported)
    # ────────────────────────────────────────────────────────────────
    imports = [
      # Base system configuration
      ./preload.nix
      ./containers-base.nix
      ./production-extras.nix
      
      # Optional kernel (if you want CachyOS BORE)
      # ./kernel-cachyos-bore.nix
      
      # Tools
      ./rag-dataset-tool.nix
      
      # Hardening (conditional)
      (lib.mkIf cfg.enableHardening ./hardening.nix)
      
      # ────────────────────────────────────────────────────────────
      # Profile-specific imports
      # ────────────────────────────────────────────────────────────
      
      # Graphical profile
      (lib.mkIf (cfg.profile == "graphical") ./graphical-minimal.nix)
      
      # Headless profile
      (lib.mkIf (cfg.profile == "headless") ./headless-minimal.nix)
      
      # ────────────────────────────────────────────────────────────
      # Service modules (conditional)
      # ────────────────────────────────────────────────────────────
      
      # SLM-Assist (production RAG system)
      # Note: Don't import here - import from flake to avoid path issues
      # (lib.mkIf cfg.enableSLMAssist ./slm-assist/default.nix)
      
      # Open WebUI (conditional)
      (lib.mkIf cfg.enableOpenWebUI ./open-webui-service.nix)
      
      # Voice Pipeline (conditional)
      # Note: Don't import here - import from flake
      # (lib.mkIf cfg.enableVoicePipeline ./voice-pipeline.nix)
      
      # ────────────────────────────────────────────────────────────
      # Deprecated modules (DO NOT USE)
      # ────────────────────────────────────────────────────────────
      # ./ollama-service.nix  # ← DEPRECATED: Use slm-assist module instead
    ];

    # ────────────────────────────────────────────────────────────────
    # Warnings
    # ────────────────────────────────────────────────────────────────
    warnings = lib.flatten [
      (lib.optional
        (cfg.enableVoicePipeline && cfg.profile == "headless")
        "Voice pipeline enabled on headless profile - you'll need to configure audio manually")
      
      (lib.optional
        (cfg.enableVoicePipeline && !cfg.enableSLMAssist)
        "Voice pipeline requires SLM-Assist to be enabled")
    ];

    # ────────────────────────────────────────────────────────────────
    # Profile information
    # ────────────────────────────────────────────────────────────────
    environment.etc."profile-info".text = ''
      Offline AI Assistant Profile Configuration
      ────────────────────────────────────────────────────────
      Profile:          ${cfg.profile}
      
      Enabled Services:
        SLM-Assist:     ${if cfg.enableSLMAssist then "✓" else "✗"}
        Open WebUI:     ${if cfg.enableOpenWebUI then "✓" else "✗"}
        Voice Pipeline: ${if cfg.enableVoicePipeline then "✓" else "✗"}
        Hardening:      ${if cfg.enableHardening then "✓" else "✗"}
      
      Included Modules:
        - preload.nix           (system preloading)
        - containers-base.nix   (Podman container support)
        - production-extras.nix (security & extras)
        - rag-dataset-tool.nix  (RAG utilities)
        ${if cfg.enableHardening then "- hardening.nix        (security hardening)" else ""}
        ${if cfg.profile == "graphical" then "- graphical-minimal.nix (DWM desktop)" else ""}
        ${if cfg.profile == "headless" then "- headless-minimal.nix  (CLI only)" else ""}
      
      Important:
        - SLM-Assist and voice-pipeline are imported from flake.nix
        - Don't use deprecated ollama-service.nix module
        - Configure services via flake.nix or custom imports
    '';
  };
}
