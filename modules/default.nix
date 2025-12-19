# modules/default.nix
{ ... }:

{
  imports = [
    ./graphical-minimal.nix
    ./preload.nix
    ./containers-base.nix
    ./ollama-service.nix
    ./open-webui-service.nix
    ./auto-launch.nix
    ./hardening.nix
    ./production-extras.nix
    ./rag-dataset-tool.nix
  ];
}
