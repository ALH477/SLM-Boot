# modules/kernel-cachyos-bore.nix (updated)
{ config, lib, pkgs, ... }:

let
  cfg = config.boot.kernel.cachyos-bore;

  # Try to find a CachyOS BORE kernel package from the input
  boreKernelPackages =
    # Most common names in xddxdd/nix-cachyos-kernel and similar flakes
    pkgs.linuxPackages_cachyos-bore or
    pkgs.linux_cachyos_bore or
    pkgs.linuxPackages_cachyos-bore-thinlto or
    pkgs.linuxPackages_cachyos or
    # Fallback to regular latest kernel if nothing found
    pkgs.linuxPackages_latest;

in {
  options.boot.kernel.cachyos-bore = with lib; {
    enable = mkEnableOption "Use CachyOS BORE kernel with desktop optimizations";
    lto = mkOption {
      type = types.bool;
      default = true;
      description = "Attempt to use ThinLTO variant if available";
    };
    disableMitigations = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Disable CPU vulnerability mitigations for extra performance.
        WARNING: Major security risk – only for trusted environments.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Use the detected kernel packages
    boot.kernelPackages = boreKernelPackages;

    # Kernel parameters
    boot.kernelParams = [
      "preempt=full"
      "threadirqs"
      "psi=1"
      "zswap.enabled=1"
      "zswap.compressor=zstd"
    ] ++ lib.optional cfg.disableMitigations "mitigations=off";

    # Sysctl tuning
    boot.kernel.sysctl = {
      "vm.swappiness" = 1;
      "vm.vfs_cache_pressure" = 50;
      "vm.watermark_scale_factor" = 200;
    };

    # zRAM
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 50;
    };

    warnings = lib.optional cfg.disableMitigations
      "CPU vulnerability mitigations disabled – significant security risk!";
  };
}
