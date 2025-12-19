# modules/containers-base.nix
{ pkgs, config, ... }:

{
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" ];
    };
    extraConfig.log_driver = "journald";
  };

  environment.systemPackages = [ pkgs.podman ];

  systemd.services.load-ollama-image = {
    description = "Load Ollama Image";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      if ! ${pkgs.podman}/bin/podman image exists ollama/ollama; then
        ${pkgs.podman}/bin/podman load -i ${config._module.args.preloadedOllamaImage}/image.tar
      fi
    '';
  };

  systemd.services.load-openwebui-image = {
    description = "Load Open WebUI Image";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      if ! ${pkgs.podman}/bin/podman image exists ghcr.io/open-webui/open-webui:ollama; then
        ${pkgs.podman}/bin/podman load -i ${config._module.args.preloadedOpenWebUIImage}/image.tar
      fi
    '';
  };

  systemd.services.create-ollama-network = {
    description = "Create Isolated Network";
    wantedBy = [ "multi-user.target" ];
    before = [ "ollama.service" "open-webui.service" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      if ! ${pkgs.podman}/bin/podman network exists ollama-net; then
        ${pkgs.podman}/bin/podman network create ollama-net
      fi
    '';
  };
}
