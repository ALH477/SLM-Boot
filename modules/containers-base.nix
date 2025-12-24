# modules/containers-base.nix
{ config, pkgs, ... }:

{
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;                    # docker alias → podman
    defaultNetwork.settings.dns_enabled = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" ];
    };
  };

  environment.systemPackages = [ pkgs.podman ];

  # Podman daemon logging to journald (modern/recommended way)
  # This is usually the default anyway, but we make it explicit
  systemd.services.podman = {
    serviceConfig.Environment = "PODMAN_LOG_DRIVER=journald";
  };

  # Load prebuilt Ollama container image (if you have preloaded images)
  systemd.services.load-ollama-image = {
    description = "Load prebuilt Ollama container image";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if ! ${pkgs.podman}/bin/podman image exists ollama/ollama; then
        echo "Ollama image not found – skipping load (add preloaded image if needed)"
        # ${pkgs.podman}/bin/podman load -i ${config._module.args.preloadedOllamaImage}/image.tar || true
      fi
    '';
  };

  # Load prebuilt Open WebUI container image
  systemd.services.load-openwebui-image = {
    description = "Load prebuilt Open WebUI container image";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if ! ${pkgs.podman}/bin/podman image exists ghcr.io/open-webui/open-webui:ollama; then
        echo "Open WebUI image not found – skipping load (add preloaded image if needed)"
        # ${pkgs.podman}/bin/podman load -i ${config._module.args.preloadedOpenWebUIImage}/image.tar || true
      fi
    '';
  };

  # Create isolated network for containers
  systemd.services.create-ollama-network = {
    description = "Create isolated Podman network for Ollama stack";
    wantedBy = [ "multi-user.target" ];
    before = [ "ollama.service" "open-webui.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network exists ollama-net || \
        ${pkgs.podman}/bin/podman network create ollama-net
    '';
  };
}
