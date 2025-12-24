# modules/production-extras.nix
# Extra configuration for production/live images
{ pkgs, config, lib, ... }:

{
  # Default user: nixos – force password change on first login
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "video" "audio" ];
    initialPassword = null;  # No initial password → forces change at login
    # Alternative: initialHashedPassword = null;  # if you prefer hashed form
  };

  # Persistence setup message (shows on first boot)
  system.activationScripts.persistence-setup = {
    text = ''
      if [ ! -f /home/nixos/.persistence-setup-done ]; then
        echo "=== Persistence Recommendation ==="
        echo "For repeated use of this live USB, create a persistent partition."
        echo "Boot into the system and run 'sudo calamares' for the graphical installer."
        echo "Alternatively, mount a persistent volume at /persist manually."
        touch /home/nixos/.persistence-setup-done
      fi
    '';
    # Run after user creation
    deps = [ "users" ];
  };

  # Optional: add other production extras (e.g. timezone, locale, etc.)
  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "UTC";  # or your preferred zone
}
