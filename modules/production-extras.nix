# modules/production-extras.nix
{ pkgs, ... }:

{
  users.users.nixos.hashedInitialPassword = null;  # Force change on first login

  system.activationScripts.persistence-setup.text = ''
    if [ ! -f /home/nixos/.persistence-setup-done ]; then
      echo "=== Persistence Recommendation ==="
      echo "For repeated use, create a persistent partition and install via Calamares."
      echo "Run 'sudo calamares' for the graphical installer."
      touch /home/nixos/.persistence-setup-done
    fi
  '';
}
