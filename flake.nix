# flake.nix – Oriented Towards Kexec Bundle and VM Disk Image Outputs
{
  description = "Offline AI Assistant (Graphical ISO + Headless Kexec/VM Profiles)";

  # Copyright © 2025 DeMoD LLC
  # BSD 3-Clause License

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/24.11";  # Pinned for reproducibility
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, ... }:
    let
      system = "x86_64-linux";

      # Shared graphical modules (for ISO)
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
      ];

      # Shared headless modules (for both kexec and VM)
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
      ];
    in
    {
      packages.${system} = {
        # Graphical live USB ISO (minimal DWM)
        graphical-iso = nixos-generators.nixosGenerate {
          inherit system;
          format = "iso";
          modules = graphicalModules;
        };

        # Graphical with voice pipeline
        graphical-voice-iso = nixos-generators.nixosGenerate {
          inherit system;
          format = "iso";
          modules = graphicalModules ++ [ self.nixosModules.voice-pipeline ];
        };

        # Headless kexec bundle (quick overlay boot on existing Linux)
        headless-kexec = nixos-generators.nixosGenerate {
          inherit system;
          format = "kexec";
          modules = headlessModules;
        };

        # Headless VM disk image (qcow2 for QEMU/KVM/Proxmox/libvirt)
        headless-vm = nixos-generators.nixosGenerate {
          inherit system;
          format = "qcow2";
          modules = headlessModules;
        };

        # Optional: Raw disk image for other hypervisors
        headless-raw = nixos-generators.nixosGenerate {
          inherit system;
          format = "raw";
          modules = headlessModules;
        };
      };

      nixosModules = {
        graphical-minimal = ./modules/graphical-minimal.nix;
        headless-minimal = ./modules/headless-minimal.nix;
        preload = ./modules/preload.nix;
        containers-base = ./modules/containers-base.nix;
        ollama-service = ./modules/ollama-service.nix;
        open-webui-service = ./modules/open-webui-service.nix;
        auto-launch = ./modules/auto-launch.nix;
        headless-access = ./modules/headless-access.nix;
        hardening = ./modules/hardening.nix;
        voice-pipeline = ./modules/voice-pipeline.nix;
        production-extras = ./modules/production-extras.nix;
        rag-dataset-tool = ./modules/rag-dataset-tool.nix;

        default = ./modules/default.nix;
      };
    };
}
