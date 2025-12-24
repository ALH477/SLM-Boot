# flake.nix – Offline AI Assistant with CachyOS BORE Kernel
#
# Description:
#   Builds multiple bootable images for an offline AI assistant:
#   - Graphical live USB ISO (with minimal DWM desktop)
#   - Graphical live USB ISO with voice pipeline
#   - Headless kexec bundle
#   - Headless VM disk image (qcow2)
#   - Headless raw disk image
#
# Features:
#   - CachyOS BORE kernel enabled in all profiles for better interactivity
#   - SLM-Assist (local DSPy RAG with Ollama + Gradio) enabled with delayed start
#   - Automatic Floorp browser launch to Gradio UI on graphical profiles
#   - Corpus baked into /var/lib/slm-assist via tmpfiles
#   - Persistence for /var/lib/slm-assist
#
# Copyright © 2025 DeMoD LLC
# BSD 3-Clause License

{
  description = "Offline AI Assistant (Graphical ISO + Headless Kexec/VM Profiles)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, ... }:

    let
      system = "x86_64-linux";

      # Shared modules for all graphical profiles (ISO)
      graphicalModules = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        self.nixosModules.graphical-minimal
        self.nixosModules.preload
        self.nixosModules.containers-base
        self.nixosModules.ollama-service
        self.nixosModules.open-webui-service
        self.nixosModules.auto-launch
        self.nixosModules.hardening
        self.nixosModules.production-extras
        self.nixosModules.rag-dataset-tool
        self.nixosModules.kernel-cachyos-bore
        { boot.kernel.cachyos-bore.enable = true; }
        # SLM-Assist configuration (with browser auto-launch on graphical)
        {
          imports = [ ./slm-assist/default.nix ];
          services.slm-assist = {
            enable = true;
            ollamaModel = "qwen3:0.6b-instruct-q5_K_M";
            gradioPort = 7861;
            dataDir = "/var/lib/slm-assist";
            exposeExternally = false;
            delayStartSec = 45;
            autoOpenBrowser = true;               # Opens Floorp to Gradio after delay
          };
          # Bake the corpus into the image
          systemd.tmpfiles.rules = [
            "d /var/lib/slm-assist 0755 slm-assist slm-assist - -"
            "C /var/lib/slm-assist/ragqa_arena_tech_corpus.jsonl - - - - ${./corpus/ragqa_arena_tech_corpus.jsonl}"
            "Z /var/lib/slm-assist 0755 slm-assist slm-assist - -"
          ];
          environment.persistence."/persist".directories = [ "/var/lib/slm-assist" ];
        }
      ];

      # Shared modules for headless profiles (kexec / VM / raw)
      headlessModules = [
        self.nixosModules.headless-minimal
        self.nixosModules.preload
        self.nixosModules.containers-base
        self.nixosModules.ollama-service
        self.nixosModules.open-webui-service
        self.nixosModules.headless-access
        self.nixosModules.hardening
        self.nixosModules.production-extras
        self.nixosModules.rag-dataset-tool
        self.nixosModules.kernel-cachyos-bore
        { boot.kernel.cachyos-bore.enable = true; }
        # SLM-Assist without browser auto-launch (headless)
        {
          imports = [ ./modules/slm-assist/default.nix ];
          services.slm-assist = {
            enable = true;
            ollamaModel = "qwen3:0.6b-instruct-q5_K_M";
            gradioPort = 7861;
            dataDir = "/var/lib/slm-assist";
            exposeExternally = false;
            delayStartSec = 45;
            autoOpenBrowser = false;              # No browser on headless
          };
          # Bake the corpus into the image (same as graphical)
          systemd.tmpfiles.rules = [
            "d /var/lib/slm-assist 0755 slm-assist slm-assist - -"
            "C /var/lib/slm-assist/ragqa_arena_tech_corpus.jsonl - - - - ${./corpus/ragqa_arena_tech_corpus.jsonl}"
            "Z /var/lib/slm-assist 0755 slm-assist slm-assist - -"
          ];
        #  environment.persistence."/persist".directories = [ "/var/lib/slm-assist" ];
        }
      ];

    in
    {
      # ────────────────────────────────────────────────────────────────
      # Generated images / bootable artifacts
      # ────────────────────────────────────────────────────────────────
      packages.${system} = {
        # Graphical live USB ISO with minimal desktop (DWM)
        graphical-iso = nixos-generators.nixosGenerate {
          inherit system;
          format = "iso";
          modules = graphicalModules;
        };

        # Graphical live USB ISO with voice pipeline enabled
        graphical-voice-iso = nixos-generators.nixosGenerate {
          inherit system;
          format = "iso";
          modules = graphicalModules ++ [ self.nixosModules.voice-pipeline ];
        };

        # Headless kexec bundle (for quick boot from existing OS)
        headless-kexec = nixos-generators.nixosGenerate {
          inherit system;
          format = "kexec";
          modules = headlessModules;
        };

        # Headless VM disk image (qcow2 format)
        headless-vm = nixos-generators.nixosGenerate {
          inherit system;
          format = "qcow2";
          modules = headlessModules;
        };

        # Headless raw disk image
        headless-raw = nixos-generators.nixosGenerate {
          inherit system;
          format = "raw";
          modules = headlessModules;
        };
      };

      # ────────────────────────────────────────────────────────────────
      # Reusable NixOS modules
      # ────────────────────────────────────────────────────────────────
      nixosModules = {
        graphical-minimal     = ./modules/graphical-minimal.nix;
        headless-minimal      = ./modules/headless-minimal.nix;
        preload               = ./modules/preload.nix;
        containers-base       = ./modules/containers-base.nix;
        ollama-service        = ./modules/ollama-service.nix;
        open-webui-service    = ./modules/open-webui-service.nix;
        auto-launch           = ./modules/auto-launch.nix;
        headless-access       = ./modules/headless-access.nix;
        hardening             = ./modules/hardening.nix;
        voice-pipeline        = ./modules/voice-pipeline.nix;
        production-extras     = ./modules/production-extras.nix;
        rag-dataset-tool      = ./modules/rag-dataset-tool.nix;
        kernel-cachyos-bore   = ./modules/kernel-cachyos-bore.nix;
        default               = ./modules/default.nix;
      };
    };
}
