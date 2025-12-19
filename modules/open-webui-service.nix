# modules/open-webui-service.nix
{ pkgs, ... }:

{
  systemd.services.open-webui = {
    description = "Open WebUI Frontend";
    after = [ "network.target" "ollama.service" "load-openwebui-image.service" "create-ollama-network.service" ];
    requires = [ "ollama.service" "load-openwebui-image.service" "create-ollama-network.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Restart = "always";
      RestartSec = 10;
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
      MemoryMax = "1G";
      MemoryHigh = "800M";
      CPUQuota = "50%";
    };

    script = ''
      exec ${pkgs.podman}/bin/podman run \
        --name open-webui \
        --replace=true \
        --sdnotify=conmon \
        --network ollama-net \
        -p 3000:8080 \
        -v open-webui-data:/app/backend/data:Z \
        -e OLLAMA_API_BASE_URL=http://ollama:11434 \
        -e OFFLINE_MODE=true \
        -e DISABLE_UPDATES=true \
        -e ENABLE_SIGNUP=true \
        -e ENABLE_IMAGE_GENERATION=false \
        --cap-drop=ALL \
        --security-opt=no-new-privileges \
        --read-only \
        --tmpfs /tmp \
        --tmpfs /app/backend/data/cache \
        ghcr.io/open-webui/open-webui:ollama
    '';
  };
}
