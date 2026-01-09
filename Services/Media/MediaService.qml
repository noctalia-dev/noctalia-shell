pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.Commons

Singleton {
  id: root

  function formatTime(seconds) {
    if (isNaN(seconds) || seconds < 0)
      return "0:00";
    var h = Math.floor(seconds / 3600);
    var m = Math.floor((seconds % 3600) / 60);
    var s = Math.floor(seconds % 60);
    var pad = function (n) {
      return (n < 10) ? ("0" + n) : n;
    };

    if (h > 0) {
      return h + ":" + pad(m) + ":" + pad(s);
    } else {
      return m + ":" + pad(s);
    }
  }

  property var currentPlayer: null
  property real currentPosition: 0
  property bool isSeeking: false
  property int selectedPlayerIndex: 0
  property bool isPlaying: currentPlayer ? (currentPlayer.playbackState === MprisPlaybackState.Playing || currentPlayer.isPlaying) : false
  property string trackTitle: currentPlayer ? (currentPlayer.trackTitle !== undefined ? currentPlayer.trackTitle.replace(/(\r\n|\n|\r)/g, "") : "") : ""
  property string trackArtist: currentPlayer ? (currentPlayer.trackArtist || "") : ""
  property string trackAlbum: currentPlayer ? (currentPlayer.trackAlbum || "") : ""
  property string trackArtUrl: currentPlayer ? (currentPlayer.trackArtUrl || "") : ""
  property real trackLength: currentPlayer ? ((currentPlayer.length < infiniteTrackLength) ? currentPlayer.length : 0) : 0
  property bool canPlay: currentPlayer ? currentPlayer.canPlay : false
  property bool canPause: currentPlayer ? currentPlayer.canPause : false
  property bool canGoNext: currentPlayer ? currentPlayer.canGoNext : false
  property bool canGoPrevious: currentPlayer ? currentPlayer.canGoPrevious : false
  property bool canSeek: currentPlayer ? currentPlayer.canSeek : false
  property string positionString: formatTime(currentPosition)
  property string lengthString: formatTime(trackLength)
  property real infiniteTrackLength: 922337203685

  Component.onCompleted: {
    updateCurrentPlayer();
  }

  function getAvailablePlayers() {
    if (!Mpris.players || !Mpris.players.values) {
      return [];
    }

    let allPlayers = Mpris.players.values;
    let finalPlayers = [];
    const genericBrowsers = ["firefox", "chromium", "chrome"];
    const blacklist = (Settings.data.audio && Settings.data.audio.mprisBlacklist) ? Settings.data.audio.mprisBlacklist : [];

    // Separate players into specific and generic lists
    let specificPlayers = [];
    let genericPlayers = [];
    for (var i = 0; i < allPlayers.length; i++) {
      const identity = String(allPlayers[i].identity || "").toLowerCase();
      const name = String(allPlayers[i].name || "").toLowerCase();
      const match = blacklist.find(b => {
                                     const s = String(b || "").toLowerCase();
                                     return s && (identity.includes(s) || name.includes(s));
                                   });
      if (match)
        continue;
      if (genericBrowsers.some(b => identity.includes(b))) {
        genericPlayers.push(allPlayers[i]);
      } else {
        specificPlayers.push(allPlayers[i]);
      }
    }

    let matchedGenericIndices = {};

    // For each specific player, try to find and pair it with a generic partner
    for (var i = 0; i < specificPlayers.length; i++) {
      let specificPlayer = specificPlayers[i];
      let title1 = String(specificPlayer.trackTitle || "").trim();
      let wasMatched = false;

      if (title1) {
        for (var j = 0; j < genericPlayers.length; j++) {
          if (matchedGenericIndices[j])
            continue;
          let genericPlayer = genericPlayers[j];
          let title2 = String(genericPlayer.trackTitle || "").trim();

          if (title2 && (title1.includes(title2) || title2.includes(title1))) {
            let dataPlayer = genericPlayer;
            let identityPlayer = specificPlayer;

            let scoreSpecific = (specificPlayer.trackArtUrl ? 1 : 0);
            let scoreGeneric = (genericPlayer.trackArtUrl ? 1 : 0);
            if (scoreSpecific > scoreGeneric) {
              dataPlayer = specificPlayer;
            }

            let virtualPlayer = {
              "identity": identityPlayer.identity,
              "desktopEntry": identityPlayer.desktopEntry,
              "trackTitle": dataPlayer.trackTitle,
              "trackArtist": dataPlayer.trackArtist,
              "trackAlbum": dataPlayer.trackAlbum,
              "trackArtUrl": dataPlayer.trackArtUrl,
              "length": dataPlayer.length || 0,
              "position": dataPlayer.position || 0,
              "playbackState": dataPlayer.playbackState,
              "isPlaying": dataPlayer.isPlaying || false,
              "canPlay": dataPlayer.canPlay || false,
              "canPause": dataPlayer.canPause || false,
              "canGoNext": dataPlayer.canGoNext || false,
              "canGoPrevious": dataPlayer.canGoPrevious || false,
              "canSeek": dataPlayer.canSeek || false,
              "canControl": dataPlayer.canControl || false,
              "_stateSource": dataPlayer,
              "_controlTarget": identityPlayer
            };
            finalPlayers.push(virtualPlayer);
            matchedGenericIndices[j] = true;
            wasMatched = true;
            break;
          }
        }
      }
      if (!wasMatched) {
        finalPlayers.push(specificPlayer);
      }
    }

    // Add any generic players that were not matched
    for (var i = 0; i < genericPlayers.length; i++) {
      if (!matchedGenericIndices[i]) {
        finalPlayers.push(genericPlayers[i]);
      }
    }

    // Filter for controllable players
    let controllablePlayers = [];
    for (var i = 0; i < finalPlayers.length; i++) {
      let player = finalPlayers[i];
      if (player && player.canControl) {
        controllablePlayers.push(player);
      }
    }
    return controllablePlayers;
  }

  function findActivePlayer() {
    let availablePlayers = getAvailablePlayers();
    if (availablePlayers.length === 0) {
      //Logger.i("Media", "No active player found")
      return null;
    }

    // Prioritize the actively playing player ---
    for (var i = 0; i < availablePlayers.length; i++) {
      if (availablePlayers[i] && availablePlayers[i].playbackState === MprisPlaybackState.Playing) {
        Logger.d("Media", "Found actively playing player: " + availablePlayers[i].identity);
        selectedPlayerIndex = i;
        return availablePlayers[i];
      }
    }

    // fallback if nothing is playing)
    const preferred = (Settings.data.audio.preferredPlayer || "");
    if (preferred !== "") {
      for (var i = 0; i < availablePlayers.length; i++) {
        const p = availablePlayers[i];
        const identity = String(p.identity || "").toLowerCase();
        const pref = preferred.toLowerCase();
        if (identity.includes(pref)) {
          selectedPlayerIndex = i;
          return p;
        }
      }
    }

    if (selectedPlayerIndex < availablePlayers.length) {
      return availablePlayers[selectedPlayerIndex];
    } else {
      selectedPlayerIndex = 0;
      return availablePlayers[0];
    }
  }

  property bool autoSwitchingPaused: false

  function switchToPlayer(index) {
    let availablePlayers = getAvailablePlayers();
    if (index >= 0 && index < availablePlayers.length) {
      let newPlayer = availablePlayers[index];
      if (newPlayer !== currentPlayer) {
        currentPlayer = newPlayer;
        selectedPlayerIndex = index;
        currentPosition = currentPlayer ? currentPlayer.position : 0;
        Logger.d("Media", "Manually switched to player " + currentPlayer.identity);
      }
    }
  }

  // Switch to the most recently active player
  function updateCurrentPlayer() {
    let newPlayer = findActivePlayer();
    if (newPlayer !== currentPlayer) {
      currentPlayer = newPlayer;
      currentPosition = currentPlayer ? currentPlayer.position : 0;
      Logger.d("Media", "Switching player");
    }
  }

  function playPause() {
    if (currentPlayer) {
      let stateSource = currentPlayer._stateSource || currentPlayer;
      let controlTarget = currentPlayer._controlTarget || currentPlayer;
      if (stateSource.playbackState === MprisPlaybackState.Playing) {
        controlTarget.pause();
      } else {
        controlTarget.play();
      }
    }
  }

  function play() {
    let target = currentPlayer ? (currentPlayer._controlTarget || currentPlayer) : null;
    if (target && target.canPlay) {
      target.play();
    }
  }

  function stop() {
    let target = currentPlayer ? (currentPlayer._controlTarget || currentPlayer) : null;
    if (target) {
      target.stop();
    }
  }

  function pause() {
    let target = currentPlayer ? (currentPlayer._controlTarget || currentPlayer) : null;
    if (target && target.canPause) {
      target.pause();
    }
  }

  function next() {
    let target = currentPlayer ? (currentPlayer._controlTarget || currentPlayer) : null;
    if (target && target.canGoNext) {
      target.next();
    }
  }

  function previous() {
    let target = currentPlayer ? (currentPlayer._controlTarget || currentPlayer) : null;
    if (target && target.canGoPrevious) {
      target.previous();
    }
  }

  function seek(position) {
    let target = currentPlayer ? (currentPlayer._controlTarget || currentPlayer) : null;
    if (target && target.canSeek) {
      target.position = position;
      currentPosition = position;
    }
  }

  function seekRelative(offset) {
    let target = currentPlayer ? (currentPlayer._controlTarget || currentPlayer) : null;
    if (target && target.canSeek && target.length > 0) {
      let seekPosition = target.position + offset;
      target.position = seekPosition;
      currentPosition = seekPosition;
    }
  }

  // Seek to position based on ratio (0.0 to 1.0)
  function seekByRatio(ratio) {
    let target = currentPlayer ? (currentPlayer._controlTarget || currentPlayer) : null;
    if (target && target.canSeek && target.length > 0) {
      let seekPosition = ratio * target.length;
      target.position = seekPosition;
      currentPosition = seekPosition;
    }
  }

  // Update progress bar every second while playing
  Timer {
    id: positionTimer
    interval: 1000
    running: currentPlayer && !root.isSeeking && currentPlayer.isPlaying && currentPlayer.length > 0 && currentPlayer.playbackState === MprisPlaybackState.Playing
    repeat: true
    onTriggered: {
      if (currentPlayer && !root.isSeeking && currentPlayer.isPlaying && currentPlayer.playbackState === MprisPlaybackState.Playing) {
        currentPosition = currentPlayer.position;
      } else {
        running = false;
      }
    }
  }

  // Avoid overwriting currentPosition while seeking due to backend position changes
  Connections {
    target: currentPlayer
    function onPositionChanged() {
      if (!root.isSeeking && currentPlayer) {
        currentPosition = currentPlayer.position;
      }
    }
    function onPlaybackStateChanged() {
      if (!root.isSeeking && currentPlayer) {
        currentPosition = currentPlayer.position;
      }
    }
  }

  // Reset position when switching to inactive player
  onCurrentPlayerChanged: {
    if (!currentPlayer || !currentPlayer.isPlaying || currentPlayer.playbackState !== MprisPlaybackState.Playing) {
      currentPosition = 0;
    }
  }

  Timer {
    id: playerStateMonitor
    interval: 2000 // Check every 2 seconds
    repeat: true
    running: true
    onTriggered: {
      //Logger.d("MediaService", "playerStateMonitor triggered. autoSwitchingPaused: " + root.autoSwitchingPaused)
      if (autoSwitchingPaused)
      return;
      // Only update if we don't have a playing player or if current player is paused
      if (!currentPlayer || !currentPlayer.isPlaying || currentPlayer.playbackState !== MprisPlaybackState.Playing) {
        updateCurrentPlayer();
      }
    }
  }

  // Update current player when available players change
  Connections {
    target: Mpris.players
    function onValuesChanged() {
      Logger.d("Media", "Players changed");
      updateCurrentPlayer();
    }
  }
}
