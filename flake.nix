# flake.nix - Offline AI Assistant with Voice Pipeline
#
# Production-ready configuration with complete integration
#
# Features:
#   - SLM-Assist (RAG with Ollama + Gradio)
#   - Voice pipeline (speech-to-text, text-to-speech)
#   - Open WebUI (chat interface)
#   - oterm (terminal interface)
#   - CachyOS BORE kernel
#   - Security hardening
#   - Offline operation with pre-baked models
#
# Copyright 2025 DeMoD LLC
# BSD 3-Clause License

{
  description = "Offline AI Assistant - Production Ready";

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
      
      # Global configuration
      defaultModel = "qwen3:0.6b";
      
      # Hardware profiles with resource limits
      profiles = {
        low-end = {
          slmAssistMemory = 1536;
          slmAssistCpu = 100;
          openWebuiMemory = "512M";
          openWebuiCpu = "30%";
          delayStart = 240;
        };
        
        mid-range = {
          slmAssistMemory = 2048;
          slmAssistCpu = 150;
          openWebuiMemory = "1G";
          openWebuiCpu = "50%";
          delayStart = 180;
        };
        
        high-end = {
          slmAssistMemory = 4096;
          slmAssistCpu = 200;
          openWebuiMemory = "2G";
          openWebuiCpu = "100%";
          delayStart = 90;
        };
      };
      
      selectedProfile = profiles.mid-range;

      # Common SLM-Assist configuration
      commonSLMConfig = {
        imports = [ ./modules/slm-assist/default.nix ];
        
        services.slm-assist = {
          enable = true;
          ollamaModel = defaultModel;
          gradioPort = 7861;
          dataDir = "/var/lib/slm-assist";
          logDir = "/var/log/slm-assist";
          
          resourceLimits = {
            maxMemoryMB = selectedProfile.slmAssistMemory;
            cpuQuota = selectedProfile.slmAssistCpu;
            maxTasks = 100;
          };
          
          delayStartSec = selectedProfile.delayStart;
          validateModels = true;
          
          authentication = {
            enable = false;  # Enable for shared systems
            username = "admin";
            password = "";  # Set for production
          };
        };
      };

      # Common Open WebUI configuration
      commonOpenWebUIConfig = {
        imports = [ ./modules/open-webui-service.nix ];
        
        services.open-webui = {
          enable = true;
          port = 3000;
          imageTag = "0.3.32";
          
          authentication = {
            enableSignup = false;
            defaultUser = "admin";
            defaultPassword = null;  # Set for production
          };
          
          resourceLimits = {
            memoryMax = selectedProfile.openWebuiMemory;
            memoryHigh = "800M";
            cpuQuota = selectedProfile.openWebuiCpu;
          };
          
          preloadImage = true;
          offlineMode = true;
        };
      };

      # Voice pipeline configuration (wake word mode)
      voiceWakeWordConfig = {
        imports = [ ./modules/voice-pipeline.nix ];
        
        services.voice-pipeline = {
          enable = true;
          mode = "wake-word";
          wakeWord = "hey assistant";
          gradioUrl = "http://127.0.0.1:7861";
          
          # Use base models for compatibility
          whisper.modelPath = "\${pkgs.whisper-cpp}/share/ggml-base.en.bin";
          piper.modelPath = "\${pkgs.piper-tts}/share/piper/en_US-lessac-medium.onnx";
          
          audioLatency = {
            clockRate = 48000;
            quantum = 128;
          };
        };
      };

      # oterm configuration
      otermConfig = {
        imports = [ ./modules/oterm-service.nix ];
        
        services.oterm = {
          enable = true;
          setupUsers = [ "nixos" ];
          defaultModel = defaultModel;
          
          sessions = {
            default = {
              model = defaultModel;
              systemPrompt = ''
                You are a helpful, concise technical assistant answering questions 
                based on the provided tech corpus (software, programming, systems, 
                NixOS, AI tools, etc.). Be accurate, avoid speculation, and reference 
                the corpus when relevant. Keep answers clear and under 300 words 
                unless asked for more detail.
              '';
              parameters = {
                temperature = 0.3;
                maxTokens = 512;
                topP = 0.9;
                topK = 40;
              };
            };
          };
        };
      };

      # Base graphical modules
      graphicalBaseModules = [
        "\${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        
        # Core modules
        self.nixosModules.graphical-minimal
        self.nixosModules.preload
        self.nixosModules.containers-base
        self.nixosModules.hardening
        self.nixosModules.production-extras
        self.nixosModules.kernel-cachyos-bore
        
        # Enable CachyOS kernel
        { boot.kernel.cachyos-bore.enable = true; }
        
        # Disable ZFS for installer
        ({ lib, ... }: {
          boot.supportedFilesystems.zfs = lib.mkForce false;
        })
        
        # SLM-Assist with browser auto-launch
        (commonSLMConfig // {
          services.slm-assist.autoOpenBrowser = true;
        })
        
        # Open WebUI
        commonOpenWebUIConfig
        
        # Helpful login message
        {
          environment.etc."issue".text = ''
            
            ================================================================
                        Offline AI Assistant - Graphical System
            ================================================================
            
            RAG System (Documents):  http://127.0.0.1:7861 (auto-opens)
            Chat Interface:          http://127.0.0.1:3000
            Terminal Chat:           Run 'oterm' command
            
            Voice Control:           Say "Hey assistant" (if enabled)
            
            System Commands:
              ai-status              Check SLM-Assist status
              ai-logs                View SLM-Assist logs
              webui-status           Check Open WebUI status
              voice-status           Check voice pipeline status
              oterm                  Start terminal chat
            
            Documentation:
              cat /etc/hardening-info
              cat /etc/slm-assist-info
              cat /etc/open-webui-info
              cat /etc/voice-pipeline-info
            
            ================================================================
          '';
        }
      ];

      # Base headless modules
      headlessBaseModules = [
        self.nixosModules.headless-minimal
        self.nixosModules.preload
        self.nixosModules.containers-base
        self.nixosModules.hardening
        self.nixosModules.production-extras
        self.nixosModules.kernel-cachyos-bore
        self.nixosModules.headless-access
        
        { boot.kernel.cachyos-bore.enable = true; }
        
        # SLM-Assist without browser
        (commonSLMConfig // {
          services.slm-assist.autoOpenBrowser = false;
        })
        
        # Open WebUI
        commonOpenWebUIConfig
        
        # SSH access info
        {
          environment.etc."motd".text = ''
            Offline AI Assistant - Headless System
            
            Access via SSH, then:
              - RAG:  curl http://127.0.0.1:7861
              - Chat: curl http://127.0.0.1:3000
              - Terminal: oterm
            
            Commands: ai-status, webui-status, oterm
          '';
        }
      ];

    in {
      # ────────────────────────────────────────────────────────────────
      # Generated bootable images
      # ────────────────────────────────────────────────────────────────
      packages.${system} = {
        # Graphical ISO
        graphical-iso = nixos-generators.nixosGenerate {
          inherit system;
          format = "iso";
          modules = graphicalBaseModules;
        };

        # Graphical ISO with voice (wake word mode)
        graphical-voice-iso = nixos-generators.nixosGenerate {
          inherit system;
          format = "iso";
          modules = graphicalBaseModules ++ [ voiceWakeWordConfig ];
        };

        # Graphical ISO with all features (voice + oterm)
        graphical-full-iso = nixos-generators.nixosGenerate {
          inherit system;
          format = "iso";
          modules = graphicalBaseModules ++ [ 
            voiceWakeWordConfig 
            otermConfig
          ];
        };

        # Headless kexec
        headless-kexec = nixos-generators.nixosGenerate {
          inherit system;
          format = "kexec";
          modules = headlessBaseModules ++ [ otermConfig ];
        };

        # Headless VM (qcow2)
        headless-vm = nixos-generators.nixosGenerate {
          inherit system;
          format = "qcow2";
          modules = headlessBaseModules ++ [ otermConfig ];
        };

        # Headless raw image
        headless-raw = nixos-generators.nixosGenerate {
          inherit system;
          format = "raw";
          modules = headlessBaseModules ++ [ otermConfig ];
        };
      };

      # ────────────────────────────────────────────────────────────────
      # NixOS modules
      # ────────────────────────────────────────────────────────────────
      nixosModules = {
        # Core modules
        graphical-minimal     = ./modules/graphical-minimal.nix;
        headless-minimal      = ./modules/headless-minimal.nix;
        preload               = ./modules/preload.nix;
        containers-base       = ./modules/containers-base.nix;
        hardening             = ./modules/hardening.nix;
        production-extras     = ./modules/production-extras.nix;
        headless-access       = ./modules/headless-access.nix;
        kernel-cachyos-bore   = ./modules/kernel-cachyos-bore.nix;
        
        # Service modules
        open-webui-service    = ./modules/open-webui-service.nix;
        voice-pipeline        = ./modules/voice-pipeline.nix;
        oterm-service         = ./modules/oterm-service.nix;
        rag-dataset-tool      = ./modules/rag-dataset-tool.nix;
        
        # Aggregator (optional use)
        default               = ./modules/default.nix;
      };

      # ────────────────────────────────────────────────────────────────
      # Development shells
      # ────────────────────────────────────────────────────────────────
      devShells.${system}.default = nixpkgs.legacyPackages.${system}.mkShell {
        name = "offline-ai-assistant-dev";
        
        packages = with nixpkgs.legacyPackages.${system}; [
          nixos-generators.packages.${system}.nixos-generators
          git
          curl
          jq
          qemu
        ];

        shellHook = ''
          echo "================================================================"
          echo "    Offline AI Assistant - Development Shell"
          echo "================================================================"
          echo ""
          echo "Build commands:"
          echo "  nix build .#graphical-iso          # Basic graphical ISO"
          echo "  nix build .#graphical-voice-iso    # With voice pipeline"
          echo "  nix build .#graphical-full-iso     # All features"
          echo "  nix build .#headless-vm            # Headless QCOW2"
          echo ""
          echo "Test commands:"
          echo "  nix run .#test-graphical           # Test in QEMU"
          echo "  nix flake check                    # Validate config"
          echo ""
          echo "Prerequisites:"
          echo "  [required] modules/slm-assist/corpus/ragqa_arena_tech_corpus.jsonl"
          echo "  [required] modules/slm-assist/models/blobs/*"
          echo "  [required] modules/slm-assist/models/manifests/*"
          echo "  [optional] modules/open-webui-images/open-webui-0.3.32.tar"
          echo ""
          echo "Download corpus:"
          echo "  wget -O modules/slm-assist/corpus/ragqa_arena_tech_corpus.jsonl \\"
          echo "    https://huggingface.co/dspy/cache/resolve/main/ragqa_arena_tech_corpus.jsonl"
          echo ""
          echo "Bake Ollama model:"
          echo "  ollama pull ${defaultModel}"
          echo "  cp -r ~/.ollama/models/* modules/slm-assist/models/"
          echo ""
          echo "================================================================"
        '';
      };

      # ────────────────────────────────────────────────────────────────
      # Test apps
      # ────────────────────────────────────────────────────────────────
      apps.${system} = {
        test-graphical = {
          type = "app";
          program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "test-graphical" ''
            set -e
            ISO="''${1:-result/iso/*.iso}"
            
            echo "Testing graphical ISO: $ISO"
            echo "Browser will auto-open to SLM-Assist"
            echo "Services: http://127.0.0.1:7861 (Gradio), http://127.0.0.1:3000 (WebUI)"
            echo ""
            
            exec ${nixpkgs.legacyPackages.${system}.qemu}/bin/qemu-system-x86_64 \
              -enable-kvm \
              -m 4096 \
              -smp 2 \
              -cdrom "$ISO" \
              -boot d \
              -vga virtio \
              -display gtk,gl=on \
              -audiodev pa,id=snd0 \
              -device intel-hda \
              -device hda-duplex,audiodev=snd0
          '');
        };
      };

      # ────────────────────────────────────────────────────────────────
      # Flake checks
      # ────────────────────────────────────────────────────────────────
      checks.${system} = {
        prerequisites-check = nixpkgs.legacyPackages.${system}.runCommand "check-prerequisites" {} ''
          echo "Checking build prerequisites..."
          
          # Check corpus
          if [ ! -f ${./modules/slm-assist/corpus/ragqa_arena_tech_corpus.jsonl} ]; then
            echo "ERROR: Corpus not found"
            echo "Download: https://huggingface.co/dspy/cache/resolve/main/ragqa_arena_tech_corpus.jsonl"
            exit 1
          fi
          
          # Check models directory
          if [ ! -d ${./modules/slm-assist/models/blobs} ]; then
            echo "ERROR: Models directory not found"
            echo "Run: ollama pull ${defaultModel}"
            echo "Then: cp -r ~/.ollama/models/* modules/slm-assist/models/"
            exit 1
          fi
          
          echo "Prerequisites OK"
          touch $out
        '';
      };
    };
}
