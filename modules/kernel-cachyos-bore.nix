# modules/kernel-cachyos-bore.nix
# Copyright (c) 2025 DeMoD LLC
# SPDX-License-Identifier: BSD-3-Clause
#
# NixOS module for CachyOS BORE kernel (high-performance desktop/gaming variant)
# Requires: cachyos-kernel flake input

{ config, lib, pkgs, ... }:

let
  cfg = config.boot.kernel.cachyos-bore;

  # Select BORE variant from cachyos-kernel input
  boreKernelPackages =
    if cfg.lto then
      pkgs.linuxPackages_cachyos-bore-lto
    else
      pkgs.linuxPackages_cachyos-bore;

in {
  options.boot.kernel.cachyos-bore = with lib; {
    enable = mkEnableOption "Use CachyOS BORE kernel with desktop optimizations";

    lto = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Use ThinLTO-optimized BORE kernel variant (recommended for best performance;
        usually cached by community hydra).
      '';
    };

    disableMitigations = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Disable CPU vulnerability mitigations (Spectre/Meltdown/etc.) for extra performance.
        WARNING: Significant security risk – only enable in trusted environments.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Use the CachyOS BORE kernel packages from the flake input
    boot.kernelPackages = boreKernelPackages;

    # Kernel parameters – safe, effective tweaks for desktop/gaming
    boot.kernelParams = [
      "preempt=full"          # full preemption for low latency
      "threadirqs"            # threaded IRQs for better responsiveness
      "psi=1"                 # Pressure Stall Information
      "zswap.enabled=1"
      "zswap.compressor=zstd"
    ] ++ lib.optional cfg.disableMitigations "mitigations=off";

    # Sysctl tuning – common desktop performance improvements
    boot.kernel.sysctl = {
      "vm.swappiness" = 1;                     # prefer RAM over swap
      "vm.vfs_cache_pressure" = 50;            # favor inode/dentry cache
      "vm.watermark_scale_factor" = 200;       # smoother memory pressure handling
    };

    # zRAM for fast compressed swap – great for gaming/low-RAM systems
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 50;                      # adjust to 75–100 on very low RAM
    };

    # Security warning
    warnings = lib.optional cfg.disableMitigations
      "CPU vulnerability mitigations disabled – significant security risk!";
  };
}
