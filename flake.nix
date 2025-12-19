# flake.nix – Complete Production-Ready Modular Template
{
  description = "Production-Ready Offline AI Assistant Live USB";

  # Copyright © 2025 DeMoD LLC
  #
  # BSD 3-Clause License (full text in modules)

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

      commonModules = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        self.nixosModules.graphical-minimal
        self.nixosModules.preload
        self.nixosModules.containers-base
        self.nixosModules.ollama-service
        self.nixosModules.open-webui-service
        self.nixosModules.auto-launch
        self.nixosModules.hardening
        self.nixosModules.production-extras
        self.nixosModules.rag-dataset-tool  # New: polished dataset parser
      ];
    in
    {
      packages.${system} = {
        default-iso = nixos-generators.nixosGenerate {
          inherit system;
          format = "iso";
          modules = commonModules;
        };

        voice-iso = nixos-generators.nixosGenerate {
          inherit system;
          format = "iso";
          modules = commonModules ++ [ self.nixosModules.voice-pipeline ];
        };
      };

      nixosModules = {
        graphical-minimal = ./modules/graphical-minimal.nix;
        preload = ./modules/preload.nix;
        containers-base = ./modules/containers-base.nix;
        ollama-service = ./modules/ollama-service.nix;
        open-webui-service = ./modules/open-webui-service.nix;
        auto-launch = ./modules/auto-launch.nix;
        hardening = ./modules/hardening.nix;
        voice-pipeline = ./modules/voice-pipeline.nix;
        production-extras = ./modules/production-extras.nix;
        rag-dataset-tool = ./modules/rag-dataset-tool.nix;

        default = ./modules/default.nix;
      };
    };
}
