# modules/preload.nix
{ config, pkgs, ... }:

{
  # Preload services removed – not needed for basic offline setup
  # (Ollama runs natively, Open WebUI can be Nix-packaged later if needed)

  environment.systemPackages = [ pkgs.podman ];  # keep Podman if you plan containers later
}
