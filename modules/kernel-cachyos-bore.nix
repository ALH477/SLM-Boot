# modules/kernel-cachyos-bore.nix
# Copyright (c) 2025 DeMoD LLC
# SPDX-License-Identifier: BSD-3-Clause
#
# NixOS module for CachyOS BORE kernel (high-performance desktop/gaming variant)
#
# This module enables the CachyOS BORE kernel if available via custom inputs.
# Falls back to linuxPackages_latest if the CachyOS variant is not found.
# Overrides vm.swappiness with mkForce to resolve conflicts with hardening.nix.

{ config, lib, pkgs, ... }:

let
  cfg = config.boot.kernel.cachyos-bore;

  # Select BORE kernel packages if available, otherwise fallback to latest kernel
  boreKernelPackages = pkgs.linuxPackages_cachyos-bore or
                       pkgs.linux_cachyos_bore or
                       pkgs.linuxPackages_latest;
in {
  options.boot.kernel.cachyos-bore = with lib; {
    enable = mkEnableOption "Use CachyOS BORE kernel with desktop optimizations";

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
    # Use the selected kernel packages
    boot.kernelPackages = boreKernelPackages;

    # Kernel parameters – safe, effective tweaks for desktop/gaming
    boot.kernelParams = [
      "preempt=full"          # full preemption for low latency
      "threadirqs"            # threaded IRQs for better responsiveness
      "psi=1"                 # Pressure Stall Information
      "zswap.enabled=1"
      "zswap.compressor=zstd"
    ] ++ lib.optional cfg.disableMitigations "mitigations=off";

    # Sysctl tuning – BORE-specific desktop performance improvements
    # Use mkForce to override any conflicting value from hardening.nix
    boot.kernel.sysctl = {
      "vm.swappiness" = lib.mkForce 1;                # prefer RAM over swap
      "vm.vfs_cache_pressure" = 50;                   # favor inode/dentry cache
      "vm.watermark_scale_factor" = 200;              # smoother memory pressure
    };

    # Compressed in-RAM swap – excellent for gaming/low-RAM systems
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 50;                             # adjust to 75–100 on low RAM
    };

    # Security warning for mitigations=off
    warnings = lib.optional cfg.disableMitigations
      "CPU vulnerability mitigations disabled – significant security risk!";
  };
}
