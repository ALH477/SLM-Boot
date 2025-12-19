# modules/voice-pipeline.nix
{ pkgs, ... }:

{
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = false;
    pulse.enable = true;
    jack.enable = true;

    extraConfig.pipewire = {
      "92-low-latency" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.quantum" = 128;
          "default.clock.min-quantum" = 64;
          "default.clock.max-quantum" = 256;
        };
      };
    };
  };

  security.rtkit.enable = true;

  environment.systemPackages = with pkgs; [
    piper-tts
    whisper-cpp
    helvum
    pavucontrol
  ];
}
