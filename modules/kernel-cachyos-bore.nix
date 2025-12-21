# modules/kernel-cachyos-bore.nix – Enhanced for Maximum Performance
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.boot.kernel.cachyos-bore;
in
{
  options.boot.kernel.cachyos-bore = {
    enable = mkEnableOption "CachyOS LTS kernel with BORE scheduler for maximum interactivity and inference throughput";
  };

  config = mkIf cfg.enable {
    boot.kernelPackages = pkgs.linuxPackages_cachyos-bore;

    boot.kernelParams = [
      "preempt=full"
      "threadirqs"
      "rcu_nocbs=all"
      "nohz_full=all"
      "psi=1"
      "zswap.enabled=1"
      "zswap.compressor=zstd"
      "mitigations=off"  # Max perf (disable in secure envs)
    ];

    boot.kernel.sysctl = {
      "vm.swappiness" = 1;
      "vm.vfs_cache_pressure" = 50;
      "vm.watermark_boost_factor" = 0;
      "vm.watermark_scale_factor" = 200;
    };

    # Zram for compressed RAM swap (great on low-memory USB/VM)
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 50;
    };
  };
}
