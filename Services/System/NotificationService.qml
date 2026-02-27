pragma Singleton

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import "../../Helpers/sha256.js" as Checksum
import qs.Commons
import qs.Services.Compositor
import qs.Services.Media
import qs.Services.Power
import qs.Services.UI

Singleton {
  id: root

  // Configuration
  property int maxVisible: 5
  property int maxHistory: 100
  property string historyFile: Quickshell.env("NOCTALIA_NOTIF_HISTORY_FILE") || (Settings.cacheDir + "notifications.json")

  // State
  property real lastSeenTs: 0
  // Volatile property that doesn't persist to settings (similar to noctaliaPerformanceMode)
  property bool doNotDisturb: false

  // Models
  property ListModel activeList: ListModel {}
  property ListModel historyList: ListModel {}

  // Internal state
  property var activeNotifications: ({}) // Maps internal ID to {notification, watcher, metadata}
  property var quickshellIdToInternalId: ({})

  // Rate limiting for notification sounds (minimum 100ms between sounds)
  property var lastSoundTime: 0
  readonly property int minSoundInterval: 100

  // Notification server
  property var notificationServerLoader: null

  Component {
    id: notificationServerComponent
    NotificationServer {
      keepOnReload: false
      imageSupported: true
      actionsSupported: true
      onNotification: notification => handleNotification(notification)
    }
  }

  Component {
    id: notificationWatcherComponent
    Connections {
      property var targetNotification
      property var targetDataId
      target: targetNotification

      function onSummaryChanged() {
        updateNotificationFromObject(targetDataId);
      }
      function onBodyChanged() {
        updateNotificationFromObject(targetDataId);
      }
      function onAppNameChanged() {
        updateNotificationFromObject(targetDataId);
      }
      function onUrgencyChanged() {
        updateNotificationFromObject(targetDataId);
      }
      function onAppIconChanged() {
        updateNotificationFromObject(targetDataId);
      }
      function onImageChanged() {
        updateNotificationFromObject(targetDataId);
      }
      function onActionsChanged() {
        updateNotificationFromObject(targetDataId);
      }
    }
  }

  function updateNotificationServer() {
    if (notificationServerLoader) {
      notificationServerLoader.destroy();
      notificationServerLoader = null;
    }

    if (Settings.isLoaded && Settings.data.notifications.enabled !== false) {
      notificationServerLoader = notificationServerComponent.createObject(root);
    }
  }

  Component.onCompleted: {
    if (Settings.isLoaded) {
      updateNotificationServer();
    }

    // Load state from ShellState
    Qt.callLater(() => {
                   if (typeof ShellState !== 'undefined' && ShellState.isLoaded) {
                     loadState();
                   }
                 });
  }

  Connections {
    target: typeof ShellState !== 'undefined' ? ShellState : null
    function onIsLoadedChanged() {
      if (ShellState.isLoaded) {
        loadState();
      }
    }
  }

  Connections {
    target: Settings
    function onSettingsLoaded() {
      updateNotificationServer();
    }
    function onSettingsSaved() {
      updateNotificationServer();
    }
  }

  // Helper function to generate content-based ID for deduplication
  function getContentId(summary, body, appName) {
    return Checksum.sha256(JSON.stringify({
                                            "summary": summary || "",
                                            "body": body || "",
                                            "app": appName || ""
                                          }));
  }

  // Main handler
  function handleNotification(notification) {
    const quickshellId = notification.id;
    const data = createData(notification);

    // Check if we should save to history based on urgency
    const saveToHistorySettings = Settings.data.notifications?.saveToHistory;
    if (saveToHistorySettings && !notification.transient) {
      let shouldSave = true;
      switch (data.urgency) {
      case 0: // low
        shouldSave = saveToHistorySettings.low !== false;
        break;
      case 1: // normal
        shouldSave = saveToHistorySettings.normal !== false;
        break;
      case 2: // critical
        shouldSave = saveToHistorySettings.critical !== false;
        break;
      }
      if (shouldSave) {
        addToHistory(data);
      }
    } else if (!notification.transient) {
      // Default behavior: save all if settings not configured
      addToHistory(data);
    }

    if (root.doNotDisturb || PowerProfileService.noctaliaPerformanceMode)
      return;

    // Check if this is a replacement notification
    const existingInternalId = quickshellIdToInternalId[quickshellId];
    if (existingInternalId && activeNotifications[existingInternalId]) {
      updateExistingNotification(existingInternalId, notification, data);
      return;
    }

    // Check for duplicate content
    const duplicateId = findDuplicateNotification(data);
    if (duplicateId) {
      removeNotification(duplicateId);
    }

    // Add new notification
    addNewNotification(quickshellId, notification, data);
    playNotificationSound(data.urgency, notification.appName);
  }

  function playNotificationSound(urgency, appName) {
    if (!SoundService.multimediaAvailable) {
      return;
    }
    if (!Settings.data.notifications?.sounds?.enabled) {
      return;
    }
    if (AudioService.muted) {
      return;
    }
    if (appName) {
      const excludedApps = Settings.data.notifications.sounds.excludedApps || "";
      if (excludedApps.trim() !== "") {
        const excludedList = excludedApps.toLowerCase().split(',').map(app => app.trim());
        const normalizedName = appName.toLowerCase();

        if (excludedList.includes(normalizedName)) {
          Logger.i("NotificationService", `Skipping sound for excluded app: ${appName}`);
          return;
        }
      }
    }

    // Get the sound file for this urgency level
    const soundFile = getNotificationSoundFile(urgency);
    if (!soundFile || soundFile.trim() === "") {
      // No sound file configured for this urgency level
      Logger.i("NotificationService", `No sound file configured for urgency ${urgency}`);
      return;
    }

    // Rate limiting - prevent sound spam
    const now = Date.now();
    if (now - lastSoundTime < minSoundInterval) {
      return;
    }
    lastSoundTime = now;

    // Play sound using existing SoundService
    const volume = Settings.data.notifications?.sounds?.volume ?? 0.5;
    SoundService.playSound(soundFile, {
                             volume: volume,
                             fallback: false,
                             repeat: false
                           });
  }

  // Get the appropriate sound file path for a given urgency level
  function getNotificationSoundFile(urgency) {
    const settings = Settings.data.notifications?.sounds;
    if (!settings) {
      return "";
    }

    // Default sound file path
    const defaultSoundFile = Quickshell.shellDir + "/Assets/Sounds/notification-generic.wav";

    // If separate sounds is disabled, always use normal sound for all urgencies
    if (!settings.separateSounds) {
      const soundFile = settings.normalSoundFile;
      if (soundFile && soundFile.trim() !== "") {
        return soundFile;
      }
      // Return default if no sound file configured
      return defaultSoundFile;
    }

    // Map urgency levels to sound file keys (when separate sounds is enabled)
    let soundKey;
    switch (urgency) {
    case 0:
      soundKey = "lowSoundFile";
      break;
    case 1:
      soundKey = "normalSoundFile";
      break;
    case 2:
      soundKey = "criticalSoundFile";
      break;
    default:
      // Default to normal urgency for invalid values
      soundKey = "normalSoundFile";
      break;
    }

    const soundFile = settings[soundKey];
    if (soundFile && soundFile.trim() !== "") {
      return soundFile;
    }

    // Return default sound file if none configured for this urgency level
    return defaultSoundFile;
  }

  function updateExistingNotification(internalId, notification, data) {
    const index = findNotificationIndex(internalId);
    if (index < 0)
      return;
    const existing = activeList.get(index);
    const oldTimestamp = existing.timestamp;
    const oldProgress = existing.progress;

    // Update properties (keeping original timestamp and progress)
    activeList.setProperty(index, "summary", data.summary);
    activeList.setProperty(index, "summaryMarkdown", data.summaryMarkdown);
    activeList.setProperty(index, "body", data.body);
    activeList.setProperty(index, "bodyMarkdown", data.bodyMarkdown);
    activeList.setProperty(index, "appName", data.appName);
    activeList.setProperty(index, "urgency", data.urgency);
    activeList.setProperty(index, "expireTimeout", data.expireTimeout);
    activeList.setProperty(index, "originalImage", data.originalImage);
    activeList.setProperty(index, "cachedImage", data.cachedImage);
    activeList.setProperty(index, "actionsJson", data.actionsJson);
    activeList.setProperty(index, "timestamp", oldTimestamp);
    activeList.setProperty(index, "progress", oldProgress);

    // Update stored notification object
    const notifData = activeNotifications[internalId];
    notifData.notification = notification;

    // Deep copy actions to preserve them even if QML object clears list
    var safeActions = [];
    if (notification.actions) {
      for (var i = 0; i < notification.actions.length; i++) {
        safeActions.push({
                           "identifier": notification.actions[i].identifier,
                           "actionObject": notification.actions[i]
                         });
      }
    }
    notifData.cachedActions = safeActions;
    notifData.metadata.originalId = data.originalId;

    notification.tracked = true;

    function onClosed() {
      userDismissNotification(internalId);
    }
    notification.closed.connect(onClosed);
    notifData.onClosed = onClosed;

    // Update metadata
    notifData.metadata.urgency = data.urgency;
    notifData.metadata.duration = calculateDuration(data);
  }

  function addNewNotification(quickshellId, notification, data) {
    // Map IDs
    quickshellIdToInternalId[quickshellId] = data.id;

    // Create watcher
    const watcher = notificationWatcherComponent.createObject(root, {
                                                                "targetNotification": notification,
                                                                "targetDataId": data.id
                                                              });

    // Deep copy actions
    var safeActions = [];
    if (notification.actions) {
      for (var i = 0; i < notification.actions.length; i++) {
        safeActions.push({
                           "identifier": notification.actions[i].identifier,
                           "actionObject": notification.actions[i]
                         });
      }
    }

    // Store notification data
    activeNotifications[data.id] = {
      "notification": notification,
      "watcher": watcher,
      "cachedActions": safeActions // Cache actions
                       ,
      "metadata": {
        "originalId": data.originalId // Store original ID
                      ,
        "timestamp": data.timestamp.getTime(),
        "duration": calculateDuration(data),
        "urgency": data.urgency,
        "paused": false,
        "pauseTime": 0
      }
    };

    notification.tracked = true;

    function onClosed() {
      userDismissNotification(data.id);
    }
    notification.closed.connect(onClosed);
    activeNotifications[data.id].onClosed = onClosed;

    // Add to list
    activeList.insert(0, data);

    // Remove overflow
    while (activeList.count > maxVisible) {
      const last = activeList.get(activeList.count - 1);
      // Overflow only removes from ACTIVE view, but keeps it for history
      activeNotifications[last.id]?.notification?.dismiss(); // Visually dismiss
      activeList.remove(activeList.count - 1);
      // DO NOT call cleanupNotification here, we want to keep it for history actions
    }
  }

  function findDuplicateNotification(data) {
    const contentId = getContentId(data.summary, data.body, data.appName);

    for (var i = 0; i < activeList.count; i++) {
      const existing = activeList.get(i);
      const existingContentId = getContentId(existing.summary, existing.body, existing.appName);
      if (existingContentId === contentId) {
        return existing.id;
      }
    }
    return null;
  }

  function calculateDuration(data) {
    const durations = [Settings.data.notifications?.lowUrgencyDuration * 1000 || 3000, Settings.data.notifications?.normalUrgencyDuration * 1000 || 8000, Settings.data.notifications?.criticalUrgencyDuration * 1000 || 15000];

    if (Settings.data.notifications?.respectExpireTimeout) {
      if (data.expireTimeout === 0)
        return -1; // Never expire
      if (data.expireTimeout > 0)
        return data.expireTimeout;
    }

    return durations[data.urgency];
  }

  function createData(n) {
    const time = new Date();
    const id = Checksum.sha256(JSON.stringify({
                                                "summary": n.summary,
                                                "body": n.body,
                                                "app": n.appName,
                                                "time": time.getTime()
                                              }));

    const image = n.image || getIcon(n.appIcon);
    const imageId = generateImageId(n, image);
    queueImage(image, n.appName || "", n.summary || "", id);

    return {
      "id": id,
      "summary": processNotificationText(n.summary || ""),
      "summaryMarkdown": processNotificationMarkdown(n.summary || ""),
      "body": processNotificationText(n.body || ""),
      "bodyMarkdown": processNotificationMarkdown(n.body || ""),
      "appName": getAppName(n.appName || n.desktopEntry || ""),
      "urgency": n.urgency < 0 || n.urgency > 2 ? 1 : n.urgency,
      "expireTimeout": n.expireTimeout,
      "timestamp": time,
      "progress": 1.0,
      "originalImage": image,
      "cachedImage": image  // Start with original, update when cached
                     ,
      "originalId": n.originalId || n.id || 0 // Ensure originalId is passed through
                    ,
      "actionsJson": JSON.stringify((n.actions || []).map(a => ({
                                                                  "text": (a.text || "").trim() || "Action",
                                                                  "identifier": a.identifier || ""
                                                                })))
    };
  }

  function findNotificationIndex(internalId) {
    for (var i = 0; i < activeList.count; i++) {
      if (activeList.get(i).id === internalId) {
        return i;
      }
    }
    return -1;
  }

  function updateNotificationFromObject(internalId) {
    const notifData = activeNotifications[internalId];
    if (!notifData)
      return;
    const index = findNotificationIndex(internalId);
    if (index < 0)
      return;
    const data = createData(notifData.notification);
    const existing = activeList.get(index);

    // Update properties (keeping timestamp and progress)
    activeList.setProperty(index, "summary", data.summary);
    activeList.setProperty(index, "summaryMarkdown", data.summaryMarkdown);
    activeList.setProperty(index, "body", data.body);
    activeList.setProperty(index, "bodyMarkdown", data.bodyMarkdown);
    activeList.setProperty(index, "appName", data.appName);
    activeList.setProperty(index, "urgency", data.urgency);
    activeList.setProperty(index, "expireTimeout", data.expireTimeout);
    activeList.setProperty(index, "originalImage", data.originalImage);
    activeList.setProperty(index, "cachedImage", data.cachedImage);
    activeList.setProperty(index, "actionsJson", data.actionsJson);

    // Update metadata
    notifData.metadata.urgency = data.urgency;
    notifData.metadata.duration = calculateDuration(data);
  }

  function removeNotification(id) {
    const index = findNotificationIndex(id);
    if (index >= 0) {
      activeList.remove(index);
    }
    cleanupNotification(id);
  }

  function cleanupNotification(id) {
    const notifData = activeNotifications[id];
    if (notifData) {
      notifData.watcher?.destroy();
      delete activeNotifications[id];
    }

    // Clean up quickshell ID mapping
    for (const qsId in quickshellIdToInternalId) {
      if (quickshellIdToInternalId[qsId] === id) {
        delete quickshellIdToInternalId[qsId];
        break;
      }
    }
  }

  // Progress updates
  Timer {
    interval: 50
    repeat: true
    running: activeList.count > 0
    onTriggered: updateAllProgress()
  }

  function updateAllProgress() {
    const now = Date.now();
    const toRemove = [];

    for (var i = 0; i < activeList.count; i++) {
      const notif = activeList.get(i);
      const notifData = activeNotifications[notif.id];
      if (!notifData)
        continue;
      const meta = notifData.metadata;
      if (meta.duration === -1 || meta.paused)
        continue;
      const elapsed = now - meta.timestamp;
      const progress = Math.max(1.0 - (elapsed / meta.duration), 0.0);

      if (progress <= 0) {
        toRemove.push(notif.id);
      } else if (Math.abs(notif.progress - progress) > 0.005) {
        activeList.setProperty(i, "progress", progress);
      }
    }

    if (toRemove.length > 0) {
      animateAndRemove(toRemove[0]);
    }
  }

  // Image handling
  function queueImage(path, appName, summary, notificationId) {
    if (!path || !notificationId)
      return;

    // Cache image:// URIs and temporary file paths (e.g. /tmp/ from Chromium)
    const filePath = path.startsWith("file://") ? path.substring(7) : path;
    const isImageUri = path.startsWith("image://");
    const isTempFile = (path.startsWith("/") || path.startsWith("file://")) && filePath.startsWith("/tmp/");

    if (!isImageUri && !isTempFile)
      return;

    ImageCacheService.getNotificationIcon(path, appName, summary, function (cachedPath, success) {
      if (success && cachedPath) {
        updateImagePath(notificationId, "file://" + cachedPath);
      }
    });
  }

  function updateImagePath(notificationId, path) {
    updateModel(activeList, notificationId, "cachedImage", path);
    updateModel(historyList, notificationId, "cachedImage", path);
    saveHistory();
  }

  function updateModel(model, notificationId, prop, value) {
    for (var i = 0; i < model.count; i++) {
      if (model.get(i).id === notificationId) {
        model.setProperty(i, prop, value);
        break;
      }
    }
  }

  // History management
  function addToHistory(data) {
    historyList.insert(0, data);

    while (historyList.count > maxHistory) {
      const old = historyList.get(historyList.count - 1);
      // Only delete cached images that are in our cache directory
      const cachedPath = old.cachedImage ? old.cachedImage.replace(/^file:\/\//, "") : "";
      if (cachedPath && cachedPath.startsWith(ImageCacheService.notificationsDir)) {
        Quickshell.execDetached(["rm", "-f", cachedPath]);
      }
      historyList.remove(historyList.count - 1);
    }
    saveHistory();
  }

  // Persistence - History
  FileView {
    id: historyFileView
    path: historyFile
    printErrors: false
    onLoaded: loadHistory()
    onLoadFailed: error => {
      if (error === 2)
      writeAdapter();
    }

    JsonAdapter {
      id: adapter
      property var notifications: []
    }
  }

  Timer {
    id: saveTimer
    interval: 200
    onTriggered: performSaveHistory()
  }

  function saveHistory() {
    saveTimer.restart();
  }

  function performSaveHistory() {
    try {
      const items = [];
      for (var i = 0; i < historyList.count; i++) {
        const n = historyList.get(i);
        const copy = Object.assign({}, n);
        copy.timestamp = n.timestamp.getTime();
        items.push(copy);
      }
      adapter.notifications = items;
      historyFileView.writeAdapter();
    } catch (e) {
      Logger.e("Notifications", "Save history failed:", e);
    }
  }

  function loadHistory() {
    try {
      historyList.clear();
      for (const item of adapter.notifications || []) {
        const time = new Date(item.timestamp);

        // Use the cached image if it exists and starts with file://, otherwise use originalImage
        let cachedImage = item.cachedImage || "";
        if (!cachedImage || (!cachedImage.startsWith("file://") && !cachedImage.startsWith("/"))) {
          cachedImage = item.originalImage || "";
        }

        historyList.append({
                             "id": item.id || "",
                             "summary": item.summary || "",
                             "summaryMarkdown": processNotificationMarkdown(item.summary || ""),
                             "body": item.body || "",
                             "bodyMarkdown": processNotificationMarkdown(item.body || ""),
                             "appName": item.appName || "",
                             "urgency": item.urgency < 0 || item.urgency > 2 ? 1 : item.urgency,
                             "timestamp": time,
                             "originalImage": item.originalImage || "",
                             "cachedImage": cachedImage,
                             "actionsJson": item.actionsJson || "[]",
                             "originalId": item.originalId || 0
                           });
      }
    } catch (e) {
      Logger.e("Notifications", "Load failed:", e);
    }
  }

  function loadState() {
    try {
      const notifState = ShellState.getNotificationsState();
      root.lastSeenTs = notifState.lastSeenTs || 0;

      // Migration is now handled in Settings.qml
      Logger.d("Notifications", "Loaded state from ShellState");
    } catch (e) {
      Logger.e("Notifications", "Load state failed:", e);
    }
  }

  function saveState() {
    try {
      ShellState.setNotificationsState({
                                         lastSeenTs: root.lastSeenTs
                                       });
      Logger.d("Notifications", "Saved state to ShellState");
    } catch (e) {
      Logger.e("Notifications", "Save state failed:", e);
    }
  }

  function updateLastSeenTs() {
    root.lastSeenTs = Time.timestamp * 1000;
    saveState();
  }

  // Utility functions
  function getAppName(name) {
    if (!name || name.trim() === "")
      return "Unknown";
    name = name.trim();

    if (name.includes(".") && (name.startsWith("com.") || name.startsWith("org.") || name.startsWith("io.") || name.startsWith("net."))) {
      const parts = name.split(".");
      let appPart = parts[parts.length - 1];

      if (!appPart || appPart === "app" || appPart === "desktop") {
        appPart = parts[parts.length - 2] || parts[0];
      }

      if (appPart)
        name = appPart;
    }

    if (name.includes(".")) {
      const parts = name.split(".");
      let displayName = parts[parts.length - 1];

      if (!displayName || /^\d+$/.test(displayName)) {
        displayName = parts[parts.length - 2] || parts[0];
      }

      if (displayName) {
        displayName = displayName.charAt(0).toUpperCase() + displayName.slice(1);
        displayName = displayName.replace(/([a-z])([A-Z])/g, '$1 $2');
        displayName = displayName.replace(/app$/i, '').trim();
        displayName = displayName.replace(/desktop$/i, '').trim();
        displayName = displayName.replace(/flatpak$/i, '').trim();

        if (!displayName) {
          displayName = parts[parts.length - 1].charAt(0).toUpperCase() + parts[parts.length - 1].slice(1);
        }
      }

      return displayName || name;
    }

    let displayName = name.charAt(0).toUpperCase() + name.slice(1);
    displayName = displayName.replace(/([a-z])([A-Z])/g, '$1 $2');
    displayName = displayName.replace(/app$/i, '').trim();
    displayName = displayName.replace(/desktop$/i, '').trim();

    return displayName || name;
  }

  function getIcon(icon) {
    if (!icon)
      return "";
    if (icon.startsWith("/") || icon.startsWith("file://"))
      return icon;
    return ThemeIcons.iconFromName(icon);
  }

  function escapeHtml(text) {
    if (!text)
      return "";
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function sanitizeMarkdownUrl(url) {
    if (!url)
      return "";
    const trimmed = url.trim();
    if (trimmed === "")
      return "";
    const lower = trimmed.toLowerCase();
    if (lower.startsWith("http://") || lower.startsWith("https://") || lower.startsWith("mailto:")) {
      return encodeURI(trimmed);
    }
    return "";
  }

  function sanitizeMarkdown(text) {
    if (!text)
      return "";

    let input = String(text);

    // Strip images entirely
    input = input.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, function (match, alt) {
      return alt ? alt : "";
    });

    // Extract links into placeholders
    const links = [];
    input = input.replace(/\[([^\]]+)\]\(([^)]+)\)/g, function (match, label, urlAndTitle) {
      const urlPart = (urlAndTitle || "").trim().split(/\s+/)[0] || "";
      const safeUrl = sanitizeMarkdownUrl(urlPart);
      const safeLabel = escapeHtml(label);
      if (!safeUrl)
        return safeLabel;
      const token = "__MDLINK_" + links.length + "__";
      links.push({
                   "label": safeLabel,
                   "url": safeUrl
                 });
      return token;
    });

    // Escape any remaining HTML
    input = escapeHtml(input);

    // Restore sanitized links
    for (let i = 0; i < links.length; i++) {
      const token = "__MDLINK_" + i + "__";
      const link = links[i];
      input = input.split(token).join("[" + link.label + "](" + link.url + ")");
    }

    return input;
  }

  function processNotificationText(text) {
    if (!text)
      return "";

    // Split by tags to process segments separately
    const parts = text.split(/(<[^>]+>)/);
    let result = "";
    const allowedTags = ["b", "i", "u", "a", "br"];

    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      if (part.startsWith("<") && part.endsWith(">")) {
        const content = part.substring(1, part.length - 1);
        const firstWord = content.split(/[\s/]/).filter(s => s.length > 0)[0]?.toLowerCase();

        if (allowedTags.includes(firstWord)) {
          // Preserve valid HTML tag
          result += part;
        } else {
          // Unknown tag: drop tag without leaking attributes
          result += "";
        }
      } else {
        // Normal text: escape everything
        result += escapeHtml(part);
      }
    }
    return result;
  }

  function processNotificationMarkdown(text) {
    return sanitizeMarkdown(text);
  }

  function generateImageId(notification, image) {
    if (image && image.startsWith("image://")) {
      if (image.startsWith("image://qsimage/")) {
        const key = (notification.appName || "") + "|" + (notification.summary || "");
        return Checksum.sha256(key);
      }
      return Checksum.sha256(image);
    }
    return "";
  }

  function pauseTimeout(id) {
    const notifData = activeNotifications[id];
    if (notifData && !notifData.metadata.paused) {
      notifData.metadata.paused = true;
      notifData.metadata.pauseTime = Date.now();
    }
  }

  function resumeTimeout(id) {
    const notifData = activeNotifications[id];
    if (notifData && notifData.metadata.paused) {
      notifData.metadata.timestamp += Date.now() - notifData.metadata.pauseTime;
      notifData.metadata.paused = false;
    }
  }

  // Public API
  function dismissActiveNotification(id) {
    const index = findNotificationIndex(id);
    if (index >= 0) {
      activeList.remove(index);
    }
  }

  // User dismissed from active view (e.g. clicked close, or swipe)
  // This behaves like "overflow" - removes from active list but KEEPS data for history
  function userDismissNotification(id) {
    dismissActiveNotification(id);
    if (Settings.data.notifications.clearDismissed) {
      removeFromHistory(id);
    }
  }

  function dismissOldestActive() {
    if (activeList.count > 0) {
      const lastNotif = activeList.get(activeList.count - 1);
      userDismissNotification(lastNotif.id);
    }
  }

  function dismissAllActive() {
    for (const id in activeNotifications) {
      activeNotifications[id].notification?.dismiss();
      activeNotifications[id].watcher?.destroy();
      if (Settings.data.notifications.clearDismissed) {
        userDismissNotification(id);
      }
    }
    activeList.clear();
    activeNotifications = {};
    quickshellIdToInternalId = {};
  }

  function invokeActionAndSuppressClose(id, actionId) {
    const notifData = activeNotifications[id];
    if (notifData && notifData.notification && notifData.onClosed) {
      try {
        notifData.notification.closed.disconnect(notifData.onClosed);
      } catch (e) {}
    }

    return invokeAction(id, actionId);
  }

  function invokeAction(id, actionId) {
    let invoked = false;
    const notifData = activeNotifications[id];

    if (notifData && notifData.notification) {
      const actionsToUse = (notifData.notification.actions && notifData.notification.actions.length > 0) ? notifData.notification.actions : (notifData.cachedActions || []);

      if (actionsToUse && actionsToUse.length > 0) {
        for (const item of actionsToUse) {
          const itemId = item.identifier;
          const actionObj = item.actionObject ? item.actionObject : item;

          if (itemId === actionId) {
            if (actionObj.invoke) {
              try {
                actionObj.invoke();
                invoked = true;
              } catch (e) {
                Logger.w("NotificationService", "invoke() failed, trying manual fallback: " + e);
                if (manualInvoke(notifData.metadata.originalId, itemId)) {
                  invoked = true;
                }
              }
            } else {
              if (manualInvoke(notifData.metadata.originalId, itemId)) {
                invoked = true;
              }
            }
            break;
          }
        }
      }

      if (!invoked && notifData.metadata.originalId) {
        Logger.w("NotificationService", "Action objects exhausted, trying manual invoke for id=" + id + " action=" + actionId);
        invoked = manualInvoke(notifData.metadata.originalId, actionId);
      }
    } else if (!notifData) {
      Logger.w("NotificationService", "No active notification data for id=" + id + ", searching history for manual invoke");
      for (var i = 0; i < historyList.count; i++) {
        if (historyList.get(i).id === id) {
          const histEntry = historyList.get(i);
          if (histEntry.originalId) {
            invoked = manualInvoke(histEntry.originalId, actionId);
          }
          break;
        }
      }
    }

    if (!invoked) {
      Logger.w("NotificationService", "Failed to invoke action '" + actionId + "' for notification " + id);
      return false;
    }

    // Clear actions after use
    updateModel(activeList, id, "actionsJson", "[]");
    updateModel(historyList, id, "actionsJson", "[]");
    saveHistory();

    return true;
  }

  function manualInvoke(originalId, actionId) {
    if (!originalId) {
      return false;
    }

    try {
      // Construct the signal emission using dbus-send
      // dbus-send --session --type=signal /org/freedesktop/Notifications org.freedesktop.Notifications.ActionInvoked uint32:ID string:"KEY"
      const args = ["dbus-send", "--session", "--type=signal", "/org/freedesktop/Notifications", "org.freedesktop.Notifications.ActionInvoked", "uint32:" + originalId, "string:" + actionId];

      Quickshell.execDetached(args);
      return true;
    } catch (e) {
      Logger.e("NotificationService", "Manual invoke failed: " + e);
      return false;
    }
  }

  function focusSenderWindow(appName) {
    if (!appName || appName === "" || appName === "Unknown")
      return false;

    const normalizedName = appName.toLowerCase().replace(/\s+/g, "");

    for (var i = 0; i < CompositorService.windows.count; i++) {
      const win = CompositorService.windows.get(i);
      const winAppId = (win.appId || "").toLowerCase();

      const segments = winAppId.split(".");
      const lastSegment = segments[segments.length - 1] || "";

      if (winAppId === normalizedName || lastSegment === normalizedName || winAppId.includes(normalizedName) || normalizedName.includes(lastSegment)) {
        CompositorService.focusWindow(win);
        return true;
      }
    }

    Logger.d("NotificationService", "No window found for app: " + appName);
    return false;
  }

  function removeFromHistory(notificationId) {
    for (var i = 0; i < historyList.count; i++) {
      const notif = historyList.get(i);
      if (notif.id === notificationId) {
        // Only delete cached images that are in our cache directory
        const cachedPath = notif.cachedImage ? notif.cachedImage.replace(/^file:\/\//, "") : "";
        if (cachedPath && cachedPath.startsWith(ImageCacheService.notificationsDir)) {
          Quickshell.execDetached(["rm", "-f", cachedPath]);
        }
        historyList.remove(i);
        saveHistory();
        return true;
      }
    }
    return false;
  }

  function removeOldestHistory() {
    if (historyList.count > 0) {
      const oldest = historyList.get(historyList.count - 1);
      // Only delete cached images that are in our cache directory
      const cachedPath = oldest.cachedImage ? oldest.cachedImage.replace(/^file:\/\//, "") : "";
      if (cachedPath && cachedPath.startsWith(ImageCacheService.notificationsDir)) {
        Quickshell.execDetached(["rm", "-f", cachedPath]);
      }
      historyList.remove(historyList.count - 1);
      saveHistory();
      return true;
    }
    return false;
  }

  function clearHistory() {
    try {
      Quickshell.execDetached(["sh", "-c", `rm -rf "${ImageCacheService.notificationsDir}"*`]);
    } catch (e) {
      Logger.e("Notifications", "Failed to clear cache directory:", e);
    }

    historyList.clear();
    saveHistory();
  }

  function getHistorySnapshot() {
    const items = [];
    for (var i = 0; i < historyList.count; i++) {
      const entry = historyList.get(i);
      items.push({
                   "id": entry.id,
                   "summary": entry.summary,
                   "body": entry.body,
                   "appName": entry.appName,
                   "urgency": entry.urgency,
                   "timestamp": entry.timestamp instanceof Date ? entry.timestamp.getTime() : entry.timestamp,
                   "originalImage": entry.originalImage,
                   "cachedImage": entry.cachedImage
                 });
    }
    return items;
  }

  // Signals
  signal animateAndRemove(string notificationId)

  onDoNotDisturbChanged: {
    ToastService.showNotice(doNotDisturb ? I18n.tr("toast.do-not-disturb.enabled") : I18n.tr("toast.do-not-disturb.disabled"), doNotDisturb ? I18n.tr("toast.do-not-disturb.enabled-desc") : I18n.tr("toast.do-not-disturb.disabled-desc"), doNotDisturb ? "bell-off" : "bell");
  }

  // Media toast functionality
  property string previousMediaTitle: ""
  property string previousMediaArtist: ""
  property bool previousMediaIsPlaying: false
  property bool mediaToastInitialized: false

  Timer {
    id: mediaToastInitTimer
    interval: 3000 // Wait 3 seconds after startup to avoid initial toast
    running: true
    onTriggered: {
      root.mediaToastInitialized = true;
      root.previousMediaTitle = MediaService.trackTitle;
      root.previousMediaArtist = MediaService.trackArtist;
      root.previousMediaIsPlaying = MediaService.isPlaying;
    }
  }

  Timer {
    id: mediaToastDebounce
    interval: 250 // Dynamic interval based on player
    onTriggered: {
      checkMediaToast();
    }
  }

  function checkMediaToast() {
    if (!Settings.data.notifications.enableMediaToast || !mediaToastInitialized)
      return;

    if (doNotDisturb || PowerProfileService.noctaliaPerformanceMode)
      return;

    // Re-evaluate player identity here to handle race conditions where
    // the identity wasn't updated yet when the timer started.
    const player = (MediaService.playerIdentity || "").toLowerCase();
    const browsers = ["firefox", "chromium", "chrome", "brave", "edge", "opera", "vivaldi", "zen"];
    const isBrowser = browsers.some(b => player.includes(b));

    // Safety check: If it's a browser, ensure we waited long enough.
    // If we started with a short interval (e.g. 250ms because we thought it was Spotify),
    // correct it now and wait the full duration.
    if (isBrowser && mediaToastDebounce.interval < 1500) {
      mediaToastDebounce.interval = 1500;
      mediaToastDebounce.restart();
      return;
    }

    const title = MediaService.trackTitle || "";
    const artist = MediaService.trackArtist || "";
    const isPlaying = MediaService.isPlaying;

    // Only show toast if something meaningful changed
    const titleChanged = title !== previousMediaTitle && title !== "";
    const playStateChanged = isPlaying !== previousMediaIsPlaying;
    const hasMedia = title !== "" || artist !== "";

    // Browser Specific Logic:
    // If a browser reports a new title but is PAUSED, ignore it.
    if (isBrowser && !isPlaying && titleChanged) {
      previousMediaTitle = title;
      previousMediaArtist = artist;
      previousMediaIsPlaying = isPlaying;
      return;
    }

    if (hasMedia && (titleChanged || playStateChanged)) {
      const icon = isPlaying ? "media-play" : "media-pause";
      let message = "";

      if (artist && title) {
        message = artist + " — " + title;
      } else if (title) {
        message = title;
      } else if (artist) {
        message = artist;
      }

      if (message !== "") {
        const toastTitle = isPlaying ? I18n.tr("common.play") : I18n.tr("common.pause");
        ToastService.showNotice(toastTitle, message, icon, 3000);
      }
    }

    previousMediaTitle = title;
    previousMediaArtist = artist;
    previousMediaIsPlaying = isPlaying;
  }

  Connections {
    target: MediaService

    function onTrackTitleChanged() {
      restartDebounce();
    }

    function onTrackArtistChanged() {
      restartDebounce();
    }

    function onIsPlayingChanged() {
      restartDebounce();
    }

    function onPlayerIdentityChanged() {
      restartDebounce();
    }
  }

  function restartDebounce() {
    const player = (MediaService.playerIdentity || "").toLowerCase();
    const browsers = ["firefox", "chromium", "chrome", "brave", "edge", "opera", "vivaldi"];
    const isBrowser = browsers.some(b => player.includes(b));

    // Use long delay for browsers to filter hover previews, short for music apps
    mediaToastDebounce.interval = isBrowser ? 1500 : 250;
    mediaToastDebounce.restart();
  }
}
