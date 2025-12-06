pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  // Map to track active sound players: resolvedPath -> MediaPlayer instance
  property var activePlayers: ({})

  // Check if QtMultimedia is available
  property bool multimediaAvailable: false

  // Container for dynamically created players
  Item {
    id: playersContainer
  }

  Component.onCompleted: {
    // Test if QtMultimedia is available by trying to create a simple component
    try {
      var testComponent = Qt.createQmlObject(`
        import QtQuick
        import QtMultimedia
        Item {}
      `, root, "MultimediaTest");
      if (testComponent) {
        multimediaAvailable = true;
        testComponent.destroy();
        Logger.i("SoundService", "QtMultimedia found - sound playback enabled");
      }
    } catch (e) {
      multimediaAvailable = false;
      Logger.w("SoundService", "QtMultimedia not available - no audio will be played from noctalia-shell");
    }
  }

  function resolvePath(soundPath) {
    if (!soundPath || soundPath === "") {
      return "";
    }

    let resolvedPath = soundPath;

    // If it's just a filename (no path separators), assume it's in Assets/Sounds/
    if (!soundPath.includes("/") && !soundPath.startsWith("file://")) {
      resolvedPath = Quickshell.shellDir + "/Assets/Sounds/" + soundPath;
    } else if (!soundPath.startsWith("/") && !soundPath.startsWith("file://")) {
      // Relative path - assume it's relative to shellDir
      resolvedPath = Quickshell.shellDir + "/" + soundPath;
    } else if (soundPath.startsWith("file://")) {
      resolvedPath = soundPath.substring(7); // Remove "file://" prefix
    }
    // Absolute paths are used as-is

    return resolvedPath;
  }

  function playSound(soundPath, options) {
    if (!soundPath || soundPath === "") {
      Logger.w("SoundService", "No sound path provided");
      return;
    }

    if (!multimediaAvailable) {
      Logger.d("SoundService", "QtMultimedia not available, cannot play sound:", soundPath);
      return;
    }

    const opts = options || {};
    const volume = opts.volume !== undefined ? opts.volume : 1.0;
    const fallback = opts.fallback !== undefined ? opts.fallback : false;
    const repeat = opts.repeat !== undefined ? opts.repeat : false;

    // Resolve path
    const resolvedPath = resolvePath(soundPath);

    // Stop any existing player for this path if it's looping
    if (repeat && activePlayers[resolvedPath]) {
      stopSound(soundPath);
    }

    // Create MediaPlayer instance dynamically with QtMultimedia import
    const loopsValue = repeat ? "MediaPlayer.Infinite" : "1";
    const escapedPath = resolvedPath.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    const playerQml = `
      import QtQuick
      import QtMultimedia
      import Quickshell
      import qs.Commons
      import qs.Services.System
      MediaPlayer {
        id: mediaPlayer
        property string resolvedPath: "${escapedPath}"
        property bool shouldFallback: ${fallback && !repeat}
        property real soundVolume: ${Math.max(0, Math.min(1, volume))}
        source: "file://${escapedPath}"
        loops: ${loopsValue}
        audioOutput: AudioOutput {
          volume: soundVolume
        }
        onErrorOccurred: {
          Logger.w("SoundService", "Error playing sound:", source, error, errorString);
          if (shouldFallback) {
            const fallbackPath = Quickshell.shellDir + "/Assets/Sounds/notification.mp3";
            if (fallbackPath !== resolvedPath) {
              SoundService.playSound(fallbackPath, {
                volume: soundVolume,
                fallback: false,
                repeat: false
              });
            }
          }
          if (SoundService.activePlayers[resolvedPath]) {
            delete SoundService.activePlayers[resolvedPath];
          }
          destroy();
        }
        onPlaybackStateChanged: function (state) {
          if (state === MediaPlayer.StoppedState && loops === 1) {
            if (SoundService.activePlayers[resolvedPath]) {
              delete SoundService.activePlayers[resolvedPath];
            }
            destroy();
          }
        }
        Component.onCompleted: {
          play();
        }
      }
    `;

    try {
      const player = Qt.createQmlObject(playerQml, playersContainer, "MediaPlayer_" + resolvedPath.replace(/[^a-zA-Z0-9]/g, "_"));

      if (!player) {
        Logger.w("SoundService", "Failed to create MediaPlayer for:", resolvedPath);
        // Try fallback if requested
        if (fallback && !repeat) {
          const defaultSound = Quickshell.shellDir + "/Assets/Sounds/notification.mp3";
          if (defaultSound !== resolvedPath) {
            playSound(defaultSound, {
                        volume: volume,
                        fallback: false,
                        repeat: false
                      });
          }
        }
        return;
      }

      // Store player in activePlayers map
      activePlayers[resolvedPath] = player;

      Logger.d("SoundService", "Playing sound:", resolvedPath, `(volume: ${Math.round(volume * 100)}%)`, repeat ? "(repeat)" : "");
    } catch (e) {
      Logger.w("SoundService", "Failed to create MediaPlayer:", e);
      // Try fallback if requested
      if (fallback && !repeat) {
        const defaultSound = Quickshell.shellDir + "/Assets/Sounds/notification.mp3";
        if (defaultSound !== resolvedPath) {
          playSound(defaultSound, {
                      volume: volume,
                      fallback: false,
                      repeat: false
                    });
        }
      }
    }
  }

  function stopSound(soundPath) {
    if (!multimediaAvailable) {
      // If multimedia isn't available, there are no active players to stop
      return;
    }

    if (soundPath) {
      // Resolve path the same way as playSound
      const resolvedPath = resolvePath(soundPath);

      // Stop and remove the player for this specific sound
      if (activePlayers[resolvedPath]) {
        const player = activePlayers[resolvedPath];
        player.stop();
        delete activePlayers[resolvedPath];
        player.destroy();
        Logger.d("SoundService", "Stopped sound:", resolvedPath);
      }
    } else {
      // Stop all active players (typically used for repeating sounds)
      const paths = Object.keys(activePlayers);
      for (let i = 0; i < paths.length; i++) {
        const path = paths[i];
        const player = activePlayers[path];
        player.stop();
        player.destroy();
      }
      activePlayers = {};
      Logger.d("SoundService", "Stopped all sounds");
    }
  }
}
