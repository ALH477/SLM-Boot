# modules/ollama-service.nix
{ pkgs, ... }:

{
  systemd.services.ollama = {
    description = "Ollama LLM Server";
    after = [ "network.target" "load-ollama-image.service" "create-ollama-network.service" ];
    requires = [ "load-ollama-image.service" "create-ollama-network.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      TimeoutStartSec = 300;
      Restart = "always";
      RestartSec = 10;
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
      MemoryMax = "4G";
      MemoryHigh = "3.5G";
      CPUQuota = "200%";
    };

    script = ''
      exec ${pkgs.podman}/bin/podman run \
        --name ollama \
        --replace=true \
        --sdnotify=conmon \
        --network ollama-net \
        -p 127.0.0.1:11434:11434 \
        -v /var/lib/ollama/.ollama:/root/.ollama:Z \
        --cap-drop=ALL \
        --security-opt=no-new-privileges \
        --read-only \
        --tmpfs /tmp \
        ollama/ollama
    '';
  };
}
