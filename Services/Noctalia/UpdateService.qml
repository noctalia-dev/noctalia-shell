pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI

Singleton {
  id: root

  // Version properties
  readonly property string baseVersion: "3.8.2"
  readonly property bool isDevelopment: true
  readonly property string developmentSuffix: "-git"
  readonly property string currentVersion: `v${!isDevelopment ? baseVersion : baseVersion + developmentSuffix}`

  // URLs
  readonly property string discordUrl: "https://discord.noctalia.dev"
  readonly property string feedbackUrl: Quickshell.env("NOCTALIA_CHANGELOG_FEEDBACK_URL") || ""
  readonly property string upgradeLogBaseUrl: Quickshell.env("NOCTALIA_UPGRADELOG_URL") || "https://noctalia.dev:7777/upgradelog"

  // Changelog properties
  property bool initialized: false
  property bool changelogPending: false
  property string changelogFromVersion: ""
  property string changelogToVersion: ""
  property string previousVersion: ""
  property string changelogCurrentVersion: ""
  property var releaseHighlights: []
  property string lastShownVersion: ""
  property bool popupScheduled: false
  property string fetchError: ""
  property string changelogLastSeenVersion: ""
  property bool changelogStateLoaded: false
  property bool pendingShowRequest: false

  // Fix for FileView race condition
  property bool saveInProgress: false
  property bool pendingSave: false
  property int saveDebounceTimer: 0

  Connections {
    target: PanelService
    function onPopupMenuWindowRegistered(screen) {
      if (popupScheduled) {
        if (!viewChangelogTargetScreen || viewChangelogTargetScreen.name === screen.name) {
          openWhenReady();
        }
      }
    }
  }

  signal popupQueued(string fromVersion, string toVersion)

  function init() {
    if (initialized)
      return;

    initialized = true;
    Logger.i("UpdateService", "Version:", root.currentVersion);

    // Load changelog state from ShellState
    Qt.callLater(() => {
                   if (typeof ShellState !== 'undefined' && ShellState.isLoaded) {
                     loadChangelogState();
                   }
                 });
  }

  Connections {
    target: typeof ShellState !== 'undefined' ? ShellState : null
    function onIsLoadedChanged() {
      if (ShellState.isLoaded) {
        loadChangelogState();
      }
    }
  }

  // Debounce timer to prevent rapid successive saves
  Timer {
    id: saveDebouncer
    interval: 300
    repeat: false
    onTriggered: executeSave()
  }

  function handleChangelogRequest() {
    const fromVersion = changelogFromVersion || "";
    const toVersion = changelogToVersion || "";

    if (Settings.shouldOpenSetupWizard) {
      // If you'll see the setup wizard then you don't need to see the changelog
      markChangelogSeen(toVersion);
      return;
    }

    if (!toVersion)
      return;

    if (popupScheduled && changelogCurrentVersion === toVersion)
      return;

    if (!popupScheduled && lastShownVersion === toVersion)
      return;

    previousVersion = fromVersion;
    changelogCurrentVersion = toVersion;

    // Fetch the upgrade log from the server
    fetchUpgradeLog(fromVersion, toVersion);

    popupScheduled = true;
    root.popupQueued(previousVersion, changelogCurrentVersion);

    clearChangelogRequest();
  }

  function fetchUpgradeLog(fromVersion, toVersion) {
    // Use the last seen version, or default to v3.0.0 if this is a fresh install
    let from = fromVersion || changelogLastSeenVersion || "v3.0.0";
    let to = toVersion;

    // Strip suffix from versions
    from = from.replace(root.developmentSuffix, "");
    to = to.replace(root.developmentSuffix, "");

    // 'from' always need to be before 'to'
    // handle edge case that will show up as we changed -dev to -git
    if (from >= to) {
      from = "v3.0.0";
    }

    Logger.d("UpdateService", "Fetching upgrade log", "from:", from, "to:", to);

    const url = `${upgradeLogBaseUrl}/${from}/${to}`;
    const request = new XMLHttpRequest();
    request.onreadystatechange = function () {
      if (request.readyState === XMLHttpRequest.DONE) {
        Logger.d("UpdateService", "Request completed with status:", request.status);
        Logger.d("UpdateService", "Response text length:", request.responseText ? request.responseText.length : 0);

        if (request.status >= 200 && request.status < 300) {
          const content = request.responseText || "";
          Logger.d("UpdateService", "Successfully fetched upgrade log, parsing...");
          const entries = parseReleaseNotes(content);
          Logger.d("UpdateService", "Parsed entries count:", entries.length);
          releaseHighlights = [
                {
                  "version": toVersion,
                  "date": "",
                  "entries": entries
                }
              ];
          fetchError = "";
          openWhenReady();
        } else {
          Logger.e("UpdateService", "Failed to fetch upgrade log");
          Logger.e("UpdateService", "Status:", request.status);
          Logger.e("UpdateService", "Status text:", request.statusText);
          Logger.e("UpdateService", "Response:", request.responseText);
          fetchError = I18n.tr("changelog.error.fetch-failed");
          releaseHighlights = [];
          openWhenReady();
        }
      }
    };
    request.open("GET", url);
    request.send();
  }

  function normalizeVersion(version) {
    if (!version)
      return "";
    return version.startsWith("v") ? version.substring(1) : version;
  }

  function parseVersionParts(version) {
    const clean = normalizeVersion(version);
    if (!clean)
      return [];
    return clean.split(/[^0-9]+/).filter(part => part.length > 0).map(part => parseInt(part));
  }

  function compareVersions(a, b) {
    if (a === b)
      return 0;
    const partsA = parseVersionParts(a);
    const partsB = parseVersionParts(b);
    const length = Math.max(partsA.length, partsB.length);
    for (var i = 0; i < length; i++) {
      const valA = partsA[i] || 0;
      const valB = partsB[i] || 0;
      if (valA > valB)
        return 1;
      if (valA < valB)
        return -1;
    }
    return 0;
  }

  function parseReleaseNotes(body) {
    if (!body)
      return [];

    const lines = body.split(/\r?\n/);
    var entries = [];

    for (var i = 0; i < lines.length; i++) {
      const line = lines[i];
      entries.push(line);
    }

    // Remove trailing blank lines
    while (entries.length > 0 && entries[entries.length - 1].trim().length === 0) {
      entries.pop();
    }

    return entries;
  }

  function isVersionLine(text) {
    return /^v?\d/i.test(text);
  }

  function cleanEntry(text) {
    if (!text)
      return "";

    var cleaned = text;

    // Strip markdown links [label](url)
    cleaned = cleaned.replace(/\[([^\]]+)\]\(([^)]+)\)/g, "$1").trim();

    // Drop bare URLs or parentheses wrapping URLs
    cleaned = cleaned.replace(/\((https?:\/\/[^)]+)\)/gi, "").trim();

    cleaned = cleaned.replace(/\([0-9a-f]{7,}\)/gi, "").trim();
    cleaned = cleaned.replace(/\s+by\s+[A-Za-z0-9_-]+$/i, "").trim();
    cleaned = cleaned.replace(/\s{2,}/g, " ");

    if (cleaned.toLowerCase().startsWith("merge branch")) {
      const ofIndex = cleaned.indexOf(" of ");
      if (ofIndex > -1) {
        cleaned = cleaned.substring(0, ofIndex).trim();
      }
    }

    return cleaned;
  }

  function isIgnoredEntry(text) {
    const lower = text.toLowerCase();
    if (lower.startsWith("release v"))
      return true;
    if (lower.includes("autoformat") || lower.includes("auto-formatting"))
      return true;
    if (lower.includes("qmlfmt"))
      return true;
    return false;
  }

  function openWhenReady() {
    if (!popupScheduled)
      return;

    if (!Quickshell.screens || Quickshell.screens.length === 0) {
      return;
    }

    const monitors = Settings.data.bar.monitors || [];
    const allowPanelsOnScreenWithoutBar = Settings.data.general.allowPanelsOnScreenWithoutBar;

    function canShowPanelsOnScreen(screen) {
      const name = screen?.name || "";
      return allowPanelsOnScreenWithoutBar || monitors.length === 0 || monitors.includes(name);
    }

    let targetScreen = viewChangelogTargetScreen;

    if (targetScreen) {
      // Explicit screen requested - validate it
      if (!canShowPanelsOnScreen(targetScreen)) {
        Logger.w("UpdateService", "Changelog cannot be shown on screen without bar:", targetScreen.name);
        popupScheduled = false;
        viewChangelogTargetScreen = null;
        return;
      }
    } else {
      // No explicit screen - find one that can show panels
      for (let i = 0; i < Quickshell.screens.length; i++) {
        if (canShowPanelsOnScreen(Quickshell.screens[i])) {
          targetScreen = Quickshell.screens[i];
          break;
        }
      }

      if (!targetScreen) {
        Logger.w("UpdateService", "No screen available to show changelog");
        popupScheduled = false;
        return;
      }
    }

    const panel = PanelService.getPanel("changelogPanel", targetScreen);
    if (!panel) {
      // Panel not found yet. Wait for popupMenuWindowRegistered signal.
      // This avoids the memory leak (#1306).
      Logger.d("UpdateService", "Waiting for changelogPanel on screen:", targetScreen.name);
      return;
    }

    panel.open();
    popupScheduled = false;
    lastShownVersion = changelogCurrentVersion;
    viewChangelogTargetScreen = null;
  }

  function openDiscord() {
    if (!discordUrl)
      return;
    Quickshell.execDetached(["xdg-open", discordUrl]);
  }

  function openFeedbackForm() {
    if (!feedbackUrl)
      return;
    Quickshell.execDetached(["xdg-open", feedbackUrl]);
  }

  function showLatestChangelog() {
    if (!currentVersion)
      return;

    if (!Settings.data.general.showChangelogOnStartup) {
      return;
    }

    if (!changelogStateLoaded) {
      pendingShowRequest = true;
      return;
    }

    const lastSeen = changelogLastSeenVersion || "";
    if (lastSeen === currentVersion)
      return;

    changelogFromVersion = lastSeen;
    changelogToVersion = currentVersion;
    changelogPending = true;
    handleChangelogRequest();
  }

  // View changelog without checking seen state (for manual viewing)
  property var viewChangelogTargetScreen: null

  function viewChangelog(screen) {
    if (!currentVersion)
      return;

    // Calculate one minor version back as starting point
    const parts = parseVersionParts(currentVersion);
    let fromVersion = "v3.0.0";
    if (parts.length >= 2) {
      const major = parts[0];
      const minor = Math.max(0, parts[1] - 1);
      fromVersion = `v${major}.${minor}.0`;
    }

    previousVersion = fromVersion;
    changelogCurrentVersion = currentVersion;
    viewChangelogTargetScreen = screen || null;
    popupScheduled = true;
    fetchUpgradeLog(fromVersion, currentVersion);
  }

  function clearChangelogRequest() {
    changelogPending = false;
    changelogFromVersion = "";
    changelogToVersion = "";
  }

  function markChangelogSeen(version) {
    if (!version)
      return;
    changelogLastSeenVersion = version;
    debouncedSaveChangelogState();
  }

  function loadChangelogState() {
    try {
      const changelog = ShellState.getChangelogState();
      changelogLastSeenVersion = changelog.lastSeenVersion || "";

      // Migration is now handled in Settings.qml
      Logger.d("UpdateService", "Loaded changelog state from ShellState");
    } catch (error) {
      Logger.e("UpdateService", "Failed to load changelog state:", error);
    }
    changelogStateLoaded = true;
    if (pendingShowRequest) {
      pendingShowRequest = false;
      Qt.callLater(root.showLatestChangelog);
    }
  }

  function debouncedSaveChangelogState() {
    // Queue a save and restart the debounce timer
    pendingSave = true;
    saveDebouncer.restart();
  }

  function executeSave() {
    if (!pendingSave)
      return;

    // Prevent concurrent saves
    if (saveInProgress) {
      // Retry after a short delay
      saveDebouncer.start();
      return;
    }

    pendingSave = false;
    saveInProgress = true;

    try {
      ShellState.setChangelogState({
                                     lastSeenVersion: changelogLastSeenVersion || ""
                                   });
      Logger.d("UpdateService", "Saved changelog state to ShellState");
      saveInProgress = false;

      // Check if another save was queued while we were saving
      if (pendingSave) {
        Qt.callLater(executeSave);
      }
    } catch (error) {
      Logger.e("UpdateService", "Failed to save changelog state:", error);
      saveInProgress = false;
    }
  }

  function saveChangelogState() {
    // Immediate save (backward compatibility)
    debouncedSaveChangelogState();
  }
}
