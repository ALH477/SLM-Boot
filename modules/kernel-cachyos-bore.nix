# modules/kernel-cachyos-bore.nix
# Copyright (c) 2025 DeMoD LLC
# SPDX-License-Identifier: BSD-3-Clause
#
# Enhanced NixOS module for the CachyOS BORE kernel (recommended for gaming + creative workloads)
#
# This module hardcodes the high-performance BORE variant with optional ThinLTO and
# desktop-oriented tweaks for maximum responsiveness and throughput.
#
# Requirements:
# - The xddxdd/nix-cachyos-kernel flake must be added as an input and its pinned overlay applied
#   (adds pkgs.cachyosKernels with linuxPackages-cachyos-bore and linuxPackages-cachyos-bore-lto).
# - Binary caches strongly recommended (see below).
#
# Safety notes:
# - "mitigations=off" is optional and disables CPU vulnerability mitigations (Spectre, Meltdown, etc.).
#   Significant performance gain but major security risk – only enable in trusted environments.
# - Removed "nohz_full=all" and "rcu_nocbs=all" from the original – these are dangerous on most systems
#   (can starve housekeeping tasks and break interactivity). Use manual core isolation if needed.
# - Many tweaks are safe and common for desktop/gaming (low swappiness, zram, etc.).

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.boot.kernel.cachyos-bore;
in
{
  options.boot.kernel.cachyos-bore = {
    enable = mkEnableOption "CachyOS BORE kernel with performance enhancements";

    lto = mkOption {
      type = types.bool;
      default = true;
      description = "Use the ThinLTO-optimized BORE build (recommended for maximum performance, usually cached).";
    };

    disableMitigations = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Disable CPU security mitigations for extra performance.
        WARNING: Major security risk (exposes Spectre/Meltdown/etc.). Only for trusted/gaming setups.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Select BORE variant (with optional LTO)
    boot.kernelPackages =
      let
        suffix = if cfg.lto then "-lto" else "";
      in
      pkgs.cachyosKernels."linuxPackages-cachyos-bore${suffix}";

    # Kernel parameters – focused on safe, effective desktop/gaming improvements
    boot.kernelParams = [
      "preempt=full"     # Ensure full preemption (low latency; redundant if built-in but safe)
      "threadirqs"       # Force threaded IRQs for better responsiveness
      "psi=1"            # Enable Pressure Stall Information (useful for monitoring)
      "zswap.enabled=1"  # Force zswap (CachyOS often enables it, but explicit is good)
      "zswap.compressor=zstd"
    ] ++ optional cfg.disableMitigations "mitigations=off";

    # Sysctl tweaks – standard desktop performance optimizations
    boot.kernel.sysctl = {
      "vm.swappiness" = 1;                  # Prefer RAM over swap
      "vm.vfs_cache_pressure" = 50;         # Favor inode/dentry cache over page cache
      "vm.watermark_boost_factor" = 0;      # Disable watermark boosting
      "vm.watermark_scale_factor" = 200;    # Increase watermark scale for smoother memory pressure
    };

    # Compressed in-RAM swap – excellent for gaming (fast) and low-RAM systems
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 50;  # Adjust higher if needed (e.g., 100 on very low RAM)
    };

    warnings = optional cfg.disableMitigations
      "CPU vulnerability mitigations are disabled – this significantly reduces security!";
  };
}
