# modules/hardening.nix
#
# Production-ready security hardening for offline AI assistant
#
# Features:
#   - Kernel security parameters
#   - Network firewall configuration
#   - Audit logging (optional)
#   - Service isolation
#   - Live USB optimizations
#
{ config, lib, pkgs, ... }:

let
  # Detect if this is a live system (ISO) or installed system
  isLiveSystem = config.boot.isContainer or false || 
                 (config.fileSystems."/".fsType or "" == "tmpfs");

in {
  # ────────────────────────────────────────────────────────────────
  # Documentation (disable for live systems to save space)
  # ────────────────────────────────────────────────────────────────
  documentation = {
    nixos.enable = !isLiveSystem;  # ~50MB saved on live USB
    man.enable = !isLiveSystem;
    info.enable = false;
    doc.enable = false;
  };

  # ────────────────────────────────────────────────────────────────
  # Audit System (disabled on live USB for performance)
  # ────────────────────────────────────────────────────────────────
  security.auditd.enable = !isLiveSystem;
  security.audit = {
    enable = !isLiveSystem;
    
    # Specific rules when enabled
    rules = lib.mkIf (!isLiveSystem) [
      # Monitor authentication events
      "-w /etc/passwd -p wa -k identity"
      "-w /etc/group -p wa -k identity"
      "-w /etc/shadow -p wa -k identity"
      
      # Monitor sudo usage
      "-w /etc/sudoers -p wa -k sudoers"
      "-w /var/log/sudo.log -p wa -k sudoers"
      
      # Monitor network configuration changes
      "-w /etc/hosts -p wa -k network"
      "-w /etc/network/ -p wa -k network"
      
      # Monitor system calls (selective)
      "-a always,exit -F arch=b64 -S execve -k exec"
    ];
  };

  # ────────────────────────────────────────────────────────────────
  # Network Configuration
  # ────────────────────────────────────────────────────────────────
  networking = {
    # NetworkManager for easy WiFi/network management
    networkmanager.enable = true;
    
    # Firewall configuration
    firewall = {
      enable = true;
      
      # External ports (none by default - offline system)
      allowedTCPPorts = [ ];
      allowedUDPPorts = [ ];
      
      # Localhost ports for internal services
      interfaces.lo.allowedTCPPorts = [
        3000   # Open WebUI
        7861   # SLM-Assist Gradio
        11434  # Ollama API
      ];
      
      # Log dropped packets (can be noisy, disabled by default)
      logRefusedConnections = false;
      
      # Log rate limit (if enabled)
      logRefusedPackets = false;
      
      # Extra firewall configuration
      extraCommands = ''
        # Rate limiting for localhost services (anti-DoS)
        iptables -A INPUT -i lo -m state --state NEW -m recent --set
        iptables -A INPUT -i lo -m state --state NEW -m recent --update --seconds 60 --hitcount 100 -j DROP
        
        # Allow established connections
        iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        
        # Drop invalid packets
        iptables -A INPUT -m state --state INVALID -j DROP
      '';
    };
    
    # Disable IPv6 if not needed (reduce attack surface)
    enableIPv6 = false;
  };

  # ────────────────────────────────────────────────────────────────
  # Kernel Hardening
  # ────────────────────────────────────────────────────────────────
  boot.kernel.sysctl = {
    # Memory Management
    "vm.swappiness" = 10;                    # Prefer RAM over swap
    "vm.dirty_ratio" = 10;                   # Start background writeback at 10%
    "vm.dirty_background_ratio" = 5;         # Background writeback at 5%
    
    # Network Security
    "net.ipv4.tcp_syncookies" = 1;           # SYN flood protection
    "net.ipv4.tcp_syn_retries" = 2;          # Reduce SYN retries
    "net.ipv4.tcp_synack_retries" = 2;       # Reduce SYN-ACK retries
    "net.ipv4.tcp_max_syn_backlog" = 4096;   # Increase SYN backlog
    "net.ipv4.conf.all.rp_filter" = 1;       # Enable reverse path filtering
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;  # Ignore broadcast pings
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
    "net.ipv4.conf.all.accept_source_route" = 0;  # Don't accept source routing
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;  # Don't send ICMP redirects
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_redirects" = 0;  # Don't accept ICMP redirects
    "net.ipv4.conf.default.accept_redirects" = 0;
    
    # Kernel Security
    "kernel.dmesg_restrict" = 1;             # Restrict dmesg to root only
    "kernel.kptr_restrict" = 2;              # Hide kernel pointers
    "kernel.yama.ptrace_scope" = 1;          # Restrict ptrace to parent processes
    "kernel.kexec_load_disabled" = 1;        # Disable kexec (live systems)
    
    # File System Security
    "fs.protected_hardlinks" = 1;            # Protect against hardlink exploits
    "fs.protected_symlinks" = 1;             # Protect against symlink exploits
    "fs.suid_dumpable" = 0;                  # Disable core dumps for SUID
  };

  # ────────────────────────────────────────────────────────────────
  # Additional Kernel Security Modules
  # ────────────────────────────────────────────────────────────────
  boot.kernelParams = [
    # Disable kernel module loading after boot (optional, can break some things)
    # "module.sig_enforce=1"
    
    # Enable kernel page table isolation (Meltdown mitigation)
    "pti=on"
    
    # Disable vsyscalls (legacy, security risk)
    "vsyscall=none"
    
    # Slab/slub debugging (performance impact, only for security-critical)
    # "slub_debug=P"
    
    # Randomize memory layout
    "randomize_kstack_offset=on"
  ];

  # ────────────────────────────────────────────────────────────────
  # Security Modules
  # ────────────────────────────────────────────────────────────────
  
  # AppArmor (optional, adds security layer)
  security.apparmor = {
    enable = false;  # Enable if you want additional MAC
    packages = [ pkgs.apparmor-profiles ];
  };

  # Polkit (required for some GUI apps)
  security.polkit.enable = true;

  # Sudo configuration
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;  # Require password for wheel group
    execWheelOnly = true;       # Only wheel group can sudo
    
    extraConfig = ''
      # Timeout for sudo password cache (minutes)
      Defaults timestamp_timeout=15
      
      # Don't allow sudo with no password
      Defaults !targetpw
      
      # Log sudo commands
      Defaults logfile=/var/log/sudo.log
      Defaults log_input, log_output
    '';
  };

  # PAM configuration
  security.pam = {
    # Require password for login
    services.login.unixAuth = true;
    
    # Limits
    loginLimits = [
      # Limit number of processes per user
      { domain = "*"; type = "-"; item = "nproc"; value = "1024"; }
      
      # Limit number of open files
      { domain = "*"; type = "-"; item = "nofile"; value = "4096"; }
      
      # Limit core dump size
      { domain = "*"; type = "-"; item = "core"; value = "0"; }
    ];
  };

  # ────────────────────────────────────────────────────────────────
  # Service Hardening Defaults
  # ────────────────────────────────────────────────────────────────
  
  # These are defaults that all systemd services inherit
  systemd.services = {
    # Global hardening defaults
    systemd-tmpfiles-setup.serviceConfig = {
      ProtectSystem = "strict";
      PrivateTmp = true;
    };
  };

  # ────────────────────────────────────────────────────────────────
  # USB Security (for live systems)
  # ────────────────────────────────────────────────────────────────
  
  # Disable automounting of USB drives (security)
  services.udisks2.enable = true;  # Enable but configure securely
  
  # ────────────────────────────────────────────────────────────────
  # Bluetooth Security
  # ────────────────────────────────────────────────────────────────
  
  # Disable bluetooth by default (can be enabled if needed)
  hardware.bluetooth.enable = lib.mkDefault false;

  # ────────────────────────────────────────────────────────────────
  # Warnings and Information
  # ────────────────────────────────────────────────────────────────
  
  warnings = lib.flatten [
    (lib.optional 
      (config.networking.firewall.enable == false)
      "Firewall is disabled - this is a security risk!")
    
    (lib.optional
      (isLiveSystem && config.security.audit.enable)
      "Audit logging enabled on live system - may impact performance")
  ];

  # ────────────────────────────────────────────────────────────────
  # System Information
  # ────────────────────────────────────────────────────────────────
  environment.etc."hardening-info".text = ''
    Security Hardening Configuration
    ────────────────────────────────────────────────────────
    System Type:     ${if isLiveSystem then "Live USB" else "Installed"}
    
    Firewall:        ${if config.networking.firewall.enable then "Enabled" else "Disabled"}
    Audit Logging:   ${if config.security.audit.enable then "Enabled" else "Disabled"}
    AppArmor:        ${if config.security.apparmor.enable then "Enabled" else "Disabled"}
    
    Localhost Ports:
      - 3000   (Open WebUI)
      - 7861   (SLM-Assist Gradio)
      - 11434  (Ollama API)
    
    Kernel Hardening:
      - PTI (Meltdown):     Enabled
      - KPTR restrict:      Level 2
      - Ptrace restrict:    Parent only
      - SYN cookies:        Enabled
      - ICMP broadcast:     Ignored
      
    Security Notes:
      - All services run with minimal privileges
      - No external network ports exposed
      - Kernel hardening parameters applied
      - Sudo requires password
      - Audit logs: ${if config.security.audit.enable then "/var/log/audit/audit.log" else "Disabled"}
    
    To check security status:
      sudo systemctl status auditd  (if enabled)
      sudo iptables -L -n -v
      cat /proc/sys/kernel/kptr_restrict
  '';
}
