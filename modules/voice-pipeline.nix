# modules/voice-pipeline.nix
#
# Production-ready voice pipeline for SLM-Assist integration
# 
# Features:
#   - Speech-to-text using whisper.cpp
#   - Text-to-speech using piper-tts
#   - Integration with SLM-Assist Gradio API
#   - Wake word detection (optional)
#   - Configurable voice models
#   - Audio routing and latency optimization
#   - Systemd services for voice interaction loop
#
{ config, lib, pkgs, ... }:

let
  cfg = config.services.voice-pipeline;

  # Voice interaction orchestrator script
  voiceOrchestrator = pkgs.writeShellScriptBin "voice-orchestrator" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Configuration from environment
    WHISPER_MODEL="''${WHISPER_MODEL:-${cfg.whisper.modelPath}}"
    PIPER_MODEL="''${PIPER_MODEL:-${cfg.piper.modelPath}}"
    GRADIO_URL="''${GRADIO_URL:-${cfg.gradioUrl}}"
    WAKE_WORD="''${WAKE_WORD:-${cfg.wakeWord}}"
    LOG_FILE="''${LOG_FILE:-/var/log/voice-pipeline/orchestrator.log}"

    log() {
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
    }

    # Audio capture and transcription
    capture_and_transcribe() {
      local temp_audio="/tmp/voice-input-$$.wav"
      
      log "Listening for speech..."
      
      # Record audio (5 seconds max, stop on silence)
      ${pkgs.sox}/bin/rec -c 1 -r 16000 "$temp_audio" \
        silence 1 0.1 3% 1 2.0 3% \
        trim 0 5 \
        2>/dev/null || {
          log "ERROR: Failed to record audio"
          return 1
        }
      
      # Transcribe with whisper
      log "Transcribing..."
      local transcription
      transcription=$(${pkgs.whisper-cpp}/bin/whisper-cpp \
        -m "$WHISPER_MODEL" \
        -f "$temp_audio" \
        --no-timestamps \
        --language en \
        2>/dev/null | grep -v '^\[' | sed 's/^[[:space:]]*//')
      
      rm -f "$temp_audio"
      
      if [ -z "$transcription" ]; then
        log "No speech detected"
        return 1
      fi
      
      log "Transcribed: $transcription"
      echo "$transcription"
    }

    # Query SLM-Assist via Gradio API
    query_gradio() {
      local question="$1"
      
      log "Querying SLM-Assist: $question"
      
      local response
      response=$(${pkgs.curl}/bin/curl -s -X POST "$GRADIO_URL/api/predict" \
        -H "Content-Type: application/json" \
        -d "{\"data\": [\"$question\"]}" \
        2>/dev/null) || {
          log "ERROR: Failed to query Gradio"
          return 1
        }
      
      # Extract answer from JSON response
      local answer
      answer=$(echo "$response" | ${pkgs.jq}/bin/jq -r '.data[0]' 2>/dev/null | \
        sed 's/\*\*Retrieved contexts\*\*.*//' | \
        sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
      
      if [ -z "$answer" ]; then
        log "ERROR: Empty response from Gradio"
        return 1
      fi
      
      log "Answer received (${#answer} chars)"
      echo "$answer"
    }

    # Speak answer using piper-tts
    speak() {
      local text="$1"
      
      log "Speaking response..."
      
      echo "$text" | ${pkgs.piper-tts}/bin/piper \
        --model "$PIPER_MODEL" \
        --output-raw | \
        ${pkgs.sox}/bin/play -t raw -r 22050 -e signed -b 16 -c 1 - \
        2>/dev/null || {
          log "ERROR: Failed to speak"
          return 1
        }
      
      log "Speech completed"
    }

    # Wake word detection (simple keyword matching)
    detect_wake_word() {
      local text="$1"
      echo "$text" | grep -qi "$WAKE_WORD"
    }

    # Main interaction loop
    main_loop() {
      log "Voice orchestrator started"
      log "Wake word: $WAKE_WORD"
      log "Gradio URL: $GRADIO_URL"
      
      while true; do
        # Capture audio and transcribe
        local transcription
        transcription=$(capture_and_transcribe) || {
          sleep 1
          continue
        }
        
        # Check for wake word
        if detect_wake_word "$transcription"; then
          log "Wake word detected!"
          
          # Confirmation beep
          ${pkgs.sox}/bin/play -n synth 0.1 sine 800 2>/dev/null &
          
          # Listen for actual question
          sleep 0.5
          local question
          question=$(capture_and_transcribe) || continue
          
          # Query AI
          local answer
          answer=$(query_gradio "$question") || {
            speak "Sorry, I encountered an error processing your request."
            continue
          }
          
          # Speak answer
          speak "$answer"
          
        fi
        
        sleep 0.5
      done
    }

    # Handle signals
    trap 'log "Shutting down..."; exit 0' SIGTERM SIGINT

    # Start
    main_loop
  '';

  # Simple continuous listening script (no wake word)
  continuousListener = pkgs.writeShellScriptBin "voice-continuous" ''
    #!/usr/bin/env bash
    set -euo pipefail

    WHISPER_MODEL="''${WHISPER_MODEL:-${cfg.whisper.modelPath}}"
    PIPER_MODEL="''${PIPER_MODEL:-${cfg.piper.modelPath}}"
    GRADIO_URL="''${GRADIO_URL:-${cfg.gradioUrl}}"

    log() {
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
    }

    while true; do
      # Record until silence
      temp_audio="/tmp/voice-continuous-$$.wav"
      ${pkgs.sox}/bin/rec -c 1 -r 16000 "$temp_audio" \
        silence 1 0.1 3% 1 2.0 3% \
        2>/dev/null || continue
      
      # Transcribe
      text=$(${pkgs.whisper-cpp}/bin/whisper-cpp \
        -m "$WHISPER_MODEL" -f "$temp_audio" \
        --no-timestamps --language en 2>/dev/null | \
        grep -v '^\[' | sed 's/^[[:space:]]*//')
      
      rm -f "$temp_audio"
      
      [ -z "$text" ] && continue
      
      log "You: $text"
      
      # Query Gradio
      response=$(${pkgs.curl}/bin/curl -s -X POST "$GRADIO_URL/api/predict" \
        -H "Content-Type: application/json" \
        -d "{\"data\": [\"$text\"]}")
      
      answer=$(echo "$response" | ${pkgs.jq}/bin/jq -r '.data[0]' | \
        sed 's/\*\*Retrieved contexts\*\*.*//')
      
      log "AI: $answer"
      
      # Speak
      echo "$answer" | ${pkgs.piper-tts}/bin/piper \
        --model "$PIPER_MODEL" --output-raw | \
        ${pkgs.sox}/bin/play -t raw -r 22050 -e signed -b 16 -c 1 - \
        2>/dev/null
      
      sleep 1
    done
  '';

in {
  options.services.voice-pipeline = with lib; {
    enable = mkEnableOption "Enable voice pipeline for SLM-Assist";

    mode = mkOption {
      type = types.enum [ "wake-word" "continuous" "push-to-talk" ];
      default = "wake-word";
      description = ''
        Voice interaction mode:
        - wake-word: Listen for wake word, then process command
        - continuous: Always listening, no wake word needed
        - push-to-talk: Manual activation (future implementation)
      '';
    };

    wakeWord = mkOption {
      type = types.str;
      default = "hey assistant";
      example = "computer";
      description = "Wake word to activate voice assistant";
    };

    gradioUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:7861";
      description = "URL of SLM-Assist Gradio interface";
    };

    whisper = {
      modelPath = mkOption {
        type = types.path;
        default = "${pkgs.whisper-cpp}/share/ggml-base.en.bin";
        description = "Path to whisper.cpp model file";
      };

      language = mkOption {
        type = types.str;
        default = "en";
        description = "Language for speech recognition";
      };
    };

    piper = {
      modelPath = mkOption {
        type = types.path;
        default = "${pkgs.piper-tts}/share/piper/en_US-lessac-medium.onnx";
        description = "Path to piper TTS model file";
      };

      voice = mkOption {
        type = types.str;
        default = "en_US-lessac-medium";
        description = "Piper voice model name";
      };
    };

    audioLatency = {
      clockRate = mkOption {
        type = types.int;
        default = 48000;
        description = "PipeWire clock rate (sample rate)";
      };

      quantum = mkOption {
        type = types.int;
        default = 128;
        description = "Default buffer size (lower = less latency)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # ────────────────────────────────────────────────────────────────
    # Audio system setup
    # ────────────────────────────────────────────────────────────────
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = false;
      pulse.enable = true;
      jack.enable = true;

      extraConfig.pipewire = {
        "92-low-latency" = {
          "context.properties" = {
            "default.clock.rate" = cfg.audioLatency.clockRate;
            "default.clock.quantum" = cfg.audioLatency.quantum;
            "default.clock.min-quantum" = cfg.audioLatency.quantum / 2;
            "default.clock.max-quantum" = cfg.audioLatency.quantum * 2;
          };
        };
      };
    };

    security.rtkit.enable = true;

    # ────────────────────────────────────────────────────────────────
    # System packages
    # ────────────────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      piper-tts
      whisper-cpp
      sox
      helvum
      pavucontrol
      voiceOrchestrator
      continuousListener
      
      # Utility scripts
      (writeShellScriptBin "voice-test-mic" ''
        echo "Recording 5 seconds... speak now!"
        ${sox}/bin/rec -c 1 -r 16000 /tmp/test.wav trim 0 5
        echo "Playing back..."
        ${sox}/bin/play /tmp/test.wav
        rm /tmp/test.wav
      '')
      
      (writeShellScriptBin "voice-test-tts" ''
        echo "Testing text-to-speech..."
        echo "Hello! This is a test of the voice pipeline." | \
          ${piper-tts}/bin/piper \
            --model ${cfg.piper.modelPath} \
            --output-raw | \
          ${sox}/bin/play -t raw -r 22050 -e signed -b 16 -c 1 -
      '')
      
      (writeShellScriptBin "voice-test-stt" ''
        echo "Recording 5 seconds for speech-to-text test..."
        ${sox}/bin/rec -c 1 -r 16000 /tmp/test-stt.wav trim 0 5
        echo "Transcribing..."
        ${whisper-cpp}/bin/whisper-cpp \
          -m ${cfg.whisper.modelPath} \
          -f /tmp/test-stt.wav \
          --language en
        rm /tmp/test-stt.wav
      '')
    ];

    # ────────────────────────────────────────────────────────────────
    # Voice orchestrator service
    # ────────────────────────────────────────────────────────────────
    systemd.services.voice-orchestrator = lib.mkIf (cfg.mode == "wake-word") {
      description = "Voice Pipeline Orchestrator (Wake Word Mode)";
      after = [ 
        "pipewire.service" 
        "slm-assist.service"
        "sound.target"
      ];
      wants = [ "slm-assist.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${voiceOrchestrator}/bin/voice-orchestrator";
        Restart = "always";
        RestartSec = 5;
        
        # Run as regular user for audio access
        User = "voice-pipeline";
        Group = "audio";
        SupplementaryGroups = [ "audio" "pipewire" ];
        
        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "voice-orchestrator";
      };

      environment = {
        WHISPER_MODEL = cfg.whisper.modelPath;
        PIPER_MODEL = cfg.piper.modelPath;
        GRADIO_URL = cfg.gradioUrl;
        WAKE_WORD = cfg.wakeWord;
        PULSE_SERVER = "unix:/run/user/1000/pulse/native";
      };
    };

    # ────────────────────────────────────────────────────────────────
    # Continuous listening service
    # ────────────────────────────────────────────────────────────────
    systemd.services.voice-continuous = lib.mkIf (cfg.mode == "continuous") {
      description = "Voice Pipeline Continuous Listening";
      after = [ 
        "pipewire.service" 
        "slm-assist.service"
        "sound.target"
      ];
      wants = [ "slm-assist.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${continuousListener}/bin/voice-continuous";
        Restart = "always";
        RestartSec = 5;
        
        User = "voice-pipeline";
        Group = "audio";
        SupplementaryGroups = [ "audio" "pipewire" ];
        
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "voice-continuous";
      };

      environment = {
        WHISPER_MODEL = cfg.whisper.modelPath;
        PIPER_MODEL = cfg.piper.modelPath;
        GRADIO_URL = cfg.gradioUrl;
        PULSE_SERVER = "unix:/run/user/1000/pulse/native";
      };
    };

    # ────────────────────────────────────────────────────────────────
    # User and permissions
    # ────────────────────────────────────────────────────────────────
    users.users.voice-pipeline = {
      isSystemUser = true;
      group = "voice-pipeline";
      extraGroups = [ "audio" "pipewire" ];
    };

    users.groups.voice-pipeline = {};

    # ────────────────────────────────────────────────────────────────
    # Log directory
    # ────────────────────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d /var/log/voice-pipeline 0755 voice-pipeline voice-pipeline - -"
    ];

    # Log rotation
    services.logrotate.settings.voice-pipeline = {
      files = "/var/log/voice-pipeline/*.log";
      frequency = "daily";
      rotate = 7;
      compress = true;
      missingok = true;
      notifempty = true;
    };

    # ────────────────────────────────────────────────────────────────
    # Helpful warnings and documentation
    # ────────────────────────────────────────────────────────────────
    warnings = lib.flatten [
      (lib.optional
        (!config.services.slm-assist.enable)
        "voice-pipeline requires services.slm-assist.enable = true")
      
      (lib.optional
        (cfg.mode == "continuous")
        "Continuous mode: Always listening. High CPU/battery usage. Consider wake-word mode.")
    ];

    # ────────────────────────────────────────────────────────────────
    # System information
    # ────────────────────────────────────────────────────────────────
    environment.etc."voice-pipeline-info".text = ''
      Voice Pipeline Configuration
      ────────────────────────────────────────────
      Mode:        ${cfg.mode}
      Wake Word:   ${cfg.wakeWord}
      Gradio URL:  ${cfg.gradioUrl}
      
      Whisper Model: ${cfg.whisper.modelPath}
      Piper Model:   ${cfg.piper.modelPath}
      
      Test Commands:
        voice-test-mic      # Test microphone
        voice-test-tts      # Test text-to-speech
        voice-test-stt      # Test speech-to-text
      
      Service Control:
        systemctl status voice-orchestrator
        journalctl -u voice-orchestrator -f
      
      Manual Control:
        voice-orchestrator    # Wake word mode
        voice-continuous      # Continuous listening
    '';
  };
}
