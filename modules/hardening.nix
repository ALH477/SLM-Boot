# modules/hardening.nix
{ ... }:

{
  documentation.nixos.enable = true;

  security.auditd.enable = true;
  security.audit.enable = true;

  networking = {
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ ];
      interfaces.lo.allowedTCPPorts = [ 3000 11434 ];
    };
  };

  boot.kernel.sysctl."vm.swappiness" = 10;
}
