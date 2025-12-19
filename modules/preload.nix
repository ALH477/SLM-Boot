# modules/preload.nix
{ pkgs, config, ... }:

let
  preloadedOllamaModels = pkgs.stdenv.mkDerivation {
    name = "ollama-preloaded-models";
    src = ../ollama-preloaded-models;
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out
      cp -r $src/* $out/
    '';
  };

  preloadedOpenWebUIImage = pkgs.stdenv.mkDerivation {
    name = "open-webui-image";
    src = ../open-webui-ollama.tar;
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out
      cp $src $out/image.tar
    '';
  };

  preloadedOllamaImage = pkgs.stdenv.mkDerivation {
    name = "ollama-image";
    src = ../ollama-cpu.tar;
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out
      cp $src $out/image.tar
    '';
  };
in
{
  system.activationScripts.preload-ollama-models.text = ''
    OLLAMA_DIR="/var/lib/ollama/.ollama"
    mkdir -p "$OLLAMA_DIR"
    if [ -z "$(ls -A "$OLLAMA_DIR")" ]; then
      echo "Pre-loading Ollama models..."
      cp -r ${preloadedOllamaModels}/* "$OLLAMA_DIR"/
      chown -R nixos:users "$OLLAMA_DIR"
      chmod -R 750 "$OLLAMA_DIR"
    fi
  '';

  _module.args = {
    inherit preloadedOllamaModels preloadedOpenWebUIImage preloadedOllamaImage;
  };
}
