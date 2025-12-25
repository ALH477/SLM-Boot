# modules/graphical-minimal.nix
#
# Production-ready minimal graphical environment for offline AI assistant
#
# Features:
#   - Lightweight DWM window manager
#   - LightDM display manager with auto-login
#   - Audio support for voice pipeline
#   - Essential desktop utilities
#   - Optimized for live USB systems
#   - Integration with SLM-Assist and voice-pipeline
#
{ config, lib, pkgs, ... }:

let
  # Simple DWM status script
  dwmStatus = pkgs.writeShellScriptBin "dwm-status" ''
    #!/usr/bin/env bash
    while true; do
      # Battery status (if available)
      if [ -f /sys/class/power_supply/BAT0/capacity ]; then
        BATTERY="BAT: $(cat /sys/class/power_supply/BAT0/capacity)%"
      else
        BATTERY=""
      fi
      
      # Volume
      VOLUME="VOL: $(${pkgs.pulseaudio}/bin/pactl get-sink-volume @DEFAULT_SINK@ | grep -oP '\d+%' | head -1)"
      
      # Time
      TIME="$(date '+%a %b %d %H:%M')"
      
      # Set status
      ${pkgs.xorg.xsetroot}/bin/xsetroot -name " $BATTERY $VOLUME | $TIME "
      
      sleep 10
    done
  '';

  # Auto-start script for live system
  autoStartScript = pkgs.writeShellScriptBin "graphical-autostart" ''
    #!/usr/bin/env bash
    
    # Set wallpaper (if available)
    if [ -f /etc/wallpaper.png ]; then
      ${pkgs.feh}/bin/feh --bg-scale /etc/wallpaper.png &
    else
      ${pkgs.xorg.xsetroot}/bin/xsetroot -solid '#1a1a1a' &
    fi
    
    # Start DWM status bar
    ${dwmStatus}/bin/dwm-status &
    
    # Start compositor for better visuals
    ${pkgs.picom}/bin/picom -b --config /dev/null \
      --fade-in-step=0.03 \
      --fade-out-step=0.03 \
      --fade-delta=5 &
    
    # Wait a moment for services to settle
    sleep 2
    
    # Note: Browser auto-launch is handled by slm-assist-browser-launch.service
    # No need to manually open Floorp here
  '';

  # Helpful welcome message
  welcomeMessage = pkgs.writeTextFile {
    name = "welcome-desktop";
    text = ''
      ╔══════════════════════════════════════════════════════════╗
      ║                                                          ║
      ║         Offline AI Assistant - Graphical System          ║
      ║                                                          ║
      ╚══════════════════════════════════════════════════════════╝
      
      SLM-Assist RAG System:
        • Browser will auto-open to: http://127.0.0.1:7861
        • Or manually: floorp http://127.0.0.1:7861
      
      Voice Control (if enabled):
        • Say "Hey assistant" to activate
        • Test: voice-test-mic, voice-test-tts
      
      Quick Commands:
        • Super+Enter: Open terminal
        • Super+P: Run program (dmenu)
        • Super+Shift+Q: Quit window
        • Super+Shift+E: Exit DWM
      
      System Status:
        • systemctl status slm-assist
        • systemctl status voice-orchestrator
        • journalctl -f  (view all logs)
      
      File Manager: pcmanfm
      Text Editor: mousepad
      
      ══════════════════════════════════════════════════════════
    '';
  };

in {
  # ────────────────────────────────────────────────────────────────
  # Display Manager & Window Manager
  # ────────────────────────────────────────────────────────────────
  services.xserver = {
    enable = true;
    
    # LightDM configuration
    displayManager.lightdm = {
      enable = true;
      background = "#111111";
      
      greeters.slick = {
        enable = true;
        theme.name = "Adwaita-dark";
        iconTheme.name = "Adwaita";
        cursorTheme.name = "Adwaita";
        
        extraConfig = ''
          [Greeter]
          show-hostname=true
          show-power=true
          show-a11y=true
          show-keyboard=true
          show-clock=true
          clock-format=%a %b %d, %H:%M
        '';
      };
    };
    
    # Auto-login for live system
    displayManager.autoLogin = {
      enable = true;
      user = "nixos";
    };
    
    # Set display manager user for SLM-Assist integration
    displayManager.sessionCommands = ''
      # Run autostart script
      ${autoStartScript}/bin/graphical-autostart &
    '';
    
    # DWM window manager
    windowManager.dwm.enable = true;
    
    # Keyboard layout
    layout = "us";
    xkbOptions = "terminate:ctrl_alt_bksp";  # Ctrl+Alt+Backspace to kill X
    
    # Enable touchpad support
    libinput = {
      enable = true;
      touchpad = {
        tapping = true;
        naturalScrolling = true;
        disableWhileTyping = true;
      };
    };
    
    # Resolution and display settings
    resolutions = [
      { x = 1920; y = 1080; }
      { x = 1366; y = 768; }
      { x = 1280; y = 720; }
    ];
  };

  # Explicitly set display manager for detection by other modules
  services.displayManager = {
    enable = true;
    user = "nixos";  # Used by slm-assist for browser launch
  };

  # ────────────────────────────────────────────────────────────────
  # Default session
  # ────────────────────────────────────────────────────────────────
  services.xserver.displayManager.defaultSession = "none+dwm";

  # ────────────────────────────────────────────────────────────────
  # User configuration
  # ────────────────────────────────────────────────────────────────
  users.users.nixos = {
    isNormalUser = true;
    description = "Live System User";
    
    # Comprehensive group membership for all features
    extraGroups = [
      "wheel"           # sudo access
      "podman"          # container management
      "networkmanager"  # network configuration
      "audio"           # audio device access (voice-pipeline)
      "video"           # video device access
      "pipewire"        # pipewire audio system
      "input"           # input devices
      "render"          # GPU rendering
    ];
    
    # Password handled by production-extras module
    # DO NOT set initialPassword here to avoid conflicts
    
    # Enable lingering for user services
    linger = true;
  };

  # ────────────────────────────────────────────────────────────────
  # System packages
  # ────────────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # Core utilities
    curl
    wget
    git
    bash
    
    # Window Manager & Desktop
    dwm
    dmenu
    st               # Simple terminal (lightweight)
    xterm            # Backup terminal
    picom            # Compositor for transparency/effects
    
    # File Management
    pcmanfm          # Lightweight file manager
    xfce.thunar      # Alternative file manager
    
    # Text Editors
    mousepad         # Simple GUI editor
    nano             # CLI editor
    vim              # Power user CLI editor
    
    # Graphics & Media
    feh              # Image viewer & wallpaper setter
    mpv              # Video player
    
    # Screenshot & Screen Recording
    flameshot        # Screenshot tool
    scrot            # Simple screenshot
    
    # System Monitoring
    htop             # Process viewer
    btop             # Modern system monitor
    
    # Audio
    pavucontrol      # PulseAudio volume control
    helvum           # PipeWire patchbay (for voice-pipeline)
    
    # Browsers
    floorp-bin       # Primary browser (for SLM-Assist)
    firefox          # Backup browser
    
    # PDF & Documents
    evince           # PDF viewer
    libreoffice-fresh # Office suite (optional, can remove for space)
    
    # Archive management
    xarchiver        # GUI archive manager
    unzip
    zip
    p7zip
    
    # Utilities
    xclip            # Clipboard management
    xdotool          # X automation
    dunst            # Notification daemon
    
    # Scripts
    dwmStatus
    autoStartScript
  ];

  # ────────────────────────────────────────────────────────────────
  # XDG Base Directory specification
  # ────────────────────────────────────────────────────────────────
  environment.sessionVariables = {
    XDG_CONFIG_HOME = "$HOME/.config";
    XDG_CACHE_HOME = "$HOME/.cache";
    XDG_DATA_HOME = "$HOME/.local/share";
    XDG_STATE_HOME = "$HOME/.local/state";
  };

  # Create XDG directories
  systemd.tmpfiles.rules = [
    "d /home/nixos/.config 0755 nixos users - -"
    "d /home/nixos/.cache 0755 nixos users - -"
    "d /home/nixos/.local/share 0755 nixos users - -"
    "d /home/nixos/.local/state 0755 nixos users - -"
  ];

  # ────────────────────────────────────────────────────────────────
  # Fonts
  # ────────────────────────────────────────────────────────────────
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-emoji
      liberation_ttf
      dejavu_fonts
      ubuntu_font_family
      fira-code
      fira-code-symbols
      hack-font
    ];
    
    fontconfig = {
      defaultFonts = {
        serif = [ "Liberation Serif" ];
        sansSerif = [ "Ubuntu" ];
        monospace = [ "Fira Code" ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };

  # ────────────────────────────────────────────────────────────────
  # Sound & Audio (for voice-pipeline integration)
  # ────────────────────────────────────────────────────────────────
  # Note: PipeWire is configured by voice-pipeline module
  # This just ensures basic audio support
  sound.enable = true;
  hardware.pulseaudio.enable = lib.mkForce false;  # Use PipeWire instead
  security.rtkit.enable = true;  # For PipeWire realtime priority

  # ────────────────────────────────────────────────────────────────
  # Desktop notifications
  # ────────────────────────────────────────────────────────────────
  services.dbus.enable = true;
  
  # Dunst notification daemon configuration
  systemd.user.services.dunst = {
    description = "Dunst notification daemon";
    after = [ "graphical-session-pre.target" ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    
    serviceConfig = {
      Type = "dbus";
      BusName = "org.freedesktop.Notifications";
      ExecStart = "${pkgs.dunst}/bin/dunst";
      Restart = "on-failure";
    };
  };

  # ────────────────────────────────────────────────────────────────
  # Welcome message
  # ────────────────────────────────────────────────────────────────
  environment.etc."issue".text = welcomeMessage.text;
  
  # Also show in terminal on login
  programs.bash.interactiveShellInit = ''
    # Show welcome message on first login
    if [ -z "$WELCOME_SHOWN" ]; then
      export WELCOME_SHOWN=1
      cat /etc/issue
    fi
  '';

  # ────────────────────────────────────────────────────────────────
  # Shell aliases for convenience
  # ────────────────────────────────────────────────────────────────
  environment.shellAliases = {
    # SLM-Assist
    "ai-status" = "systemctl status slm-assist.service";
    "ai-logs" = "journalctl -u slm-assist.service -f";
    "ai-restart" = "sudo systemctl restart slm-assist.service";
    "ai-open" = "floorp http://127.0.0.1:7861";
    
    # Voice Pipeline
    "voice-status" = "systemctl status voice-orchestrator.service";
    "voice-logs" = "journalctl -u voice-orchestrator.service -f";
    "voice-restart" = "sudo systemctl restart voice-orchestrator.service";
    
    # System
    "ll" = "ls -alh";
    "update-system" = "sudo nixos-rebuild switch";
    "system-logs" = "journalctl -f";
  };

  # ────────────────────────────────────────────────────────────────
  # Networking
  # ────────────────────────────────────────────────────────────────
  networking.hostName = "offline-assistant";  # Removed "-minimal" for cleaner name
  networking.networkmanager.enable = true;

  # ────────────────────────────────────────────────────────────────
  # Hardware support
  # ────────────────────────────────────────────────────────────────
  hardware = {
    # Enable OpenGL for better graphics
    opengl = {
      enable = true;
      driSupport = true;
      driSupport32Bit = false;  # Not needed for 64-bit only system
    };
    
    # Bluetooth support (optional, can disable to save space)
    bluetooth.enable = true;
    bluetooth.powerOnBoot = false;  # Don't auto-enable
  };

  # ────────────────────────────────────────────────────────────────
  # Performance optimizations for live USB
  # ────────────────────────────────────────────────────────────────
  
  # Reduce journald size on live system
  services.journald.extraConfig = ''
    SystemMaxUse=100M
    RuntimeMaxUse=50M
  '';
  
  # Disable unnecessary services for live system
  services.logrotate.enable = false;  # Not needed on live USB
  
  # ────────────────────────────────────────────────────────────────
  # Optional: Custom wallpaper
  # ────────────────────────────────────────────────────────────────
  # Uncomment and add your wallpaper:
  # environment.etc."wallpaper.png".source = ./path/to/wallpaper.png;

  # ────────────────────────────────────────────────────────────────
  # System information
  # ────────────────────────────────────────────────────────────────
  environment.etc."graphical-info".text = ''
    Graphical Environment Configuration
    ────────────────────────────────────────────
    Display Manager:  LightDM (with auto-login)
    Window Manager:   DWM (Dynamic Window Manager)
    User:            nixos
    
    DWM Keybindings:
      Super+Enter          Open terminal
      Super+P              Run program (dmenu)
      Super+Shift+C        Close window
      Super+Shift+Q        Quit DWM
      Super+J/K            Focus next/previous window
      Super+[1-9]          Switch to workspace 1-9
      Super+Shift+[1-9]    Move window to workspace 1-9
    
    Installed Applications:
      Browser:       floorp, firefox
      File Manager:  pcmanfm, thunar
      Text Editor:   mousepad, nano, vim
      PDF Viewer:    evince
      Screenshot:    flameshot, scrot
      Audio Control: pavucontrol, helvum
      System Monitor: htop, btop
    
    Integration:
      SLM-Assist:    Auto-opens in Floorp
      Voice Control: Enabled if voice-pipeline module active
      Audio System:  PipeWire (low latency)
  '';
}
