# modules/graphical-minimal.nix
{ pkgs, ... }:

{
  services.xserver = {
    enable = true;

    displayManager.lightdm = {
      enable = true;
      background = "#111111";
      greeters.slick = {
        enable = true;
        theme.name = "Adwaita-dark";
      };
    };

    displayManager.autoLogin = {
      enable = true;
      user = "nixos";
    };

    windowManager.dwm.enable = true;
    layout = "us";
  };

  environment.systemPackages = with pkgs; [
    curl
    bash
    dwm
    dmenu
    st
    xterm
    feh
    floorp-bin
  ];

  users.users.nixos = {
    isNormalUser = true;
    description = "Live System User";
    extraGroups = [ "wheel" "podman" "networkmanager" ];
    initialPassword = "nixos";
    linger = true;
  };

  networking.hostName = "offline-assistant-minimal";
}
