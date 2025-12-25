pragma Singleton

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import "../../Helpers/sha256.js" as Checksum
import qs.Commons
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
  property var imageQueue: []

  // Rate limiting for notification sounds (minimum 100ms between sounds)
  property var lastSoundTime: 0
  readonly property int minSoundInterval: 100

  PanelWindow {
    implicitHeight: 0
    implicitWidth: 0
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "noctalia-notification-image-renderer"
    color: Color.transparent
    mask: Region {}

    Image {
      id: cacher
      width: 64
      height: 64
      visible: true
      cache: false
      asynchronous: true
      mipmap: true
      antialiasing: true

      onStatusChanged: {
        if (imageQueue.length === 0) {
          return;
        }

        const req = imageQueue[0];

        if (status === Image.Ready) {
          Quickshell.execDetached(["mkdir", "-p", Settings.cacheDirImagesNotifications]);
          grabToImage(result => {
                        if (result.saveToFile(req.dest))
                        updateImagePath(req.imageId, req.dest);
                        processNextImage();
                      });
        } else if (status === Image.Error) {
          processNextImage();
        }
      }

      function processNextImage() {
        imageQueue.shift();
        if (imageQueue.length > 0) {
          source = imageQueue[0].src;
        } else {
          source = "";
        }
      }
    }
  }

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
    if (saveToHistorySettings) {
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
    } else {
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
    activeList.setProperty(index, "body", data.body);
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
    notification.tracked = true;
    notification.closed.connect(() => removeNotification(internalId));

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

    // Store notification data
    activeNotifications[data.id] = {
      "notification": notification,
      "watcher": watcher,
      "metadata": {
        "timestamp": data.timestamp.getTime(),
        "duration": calculateDuration(data),
        "urgency": data.urgency,
        "paused": false,
        "pauseTime": 0
      }
    };

    notification.tracked = true;
    notification.closed.connect(() => removeNotification(data.id));

    // Add to list
    activeList.insert(0, data);

    // Remove overflow
    while (activeList.count > maxVisible) {
      const last = activeList.get(activeList.count - 1);
      activeNotifications[last.id]?.notification?.dismiss();
      activeList.remove(activeList.count - 1);
      cleanupNotification(last.id);
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
    queueImage(image, imageId);

    return {
      "id": id,
      "summary": n.summary || "",
      "body": stripTags(n.body || ""),
      "appName": getAppName(n.appName || n.desktopEntry || ""),
      "urgency": n.urgency < 0 || n.urgency > 2 ? 1 : n.urgency,
      "expireTimeout": n.expireTimeout,
      "timestamp": time,
      "progress": 1.0,
      "originalImage": image,
      "cachedImage": imageId ? (Settings.cacheDirImagesNotifications + imageId + ".png") : image,
      "actionsJson": JSON.stringify((n.actions || []).map(a => ({
                                                                  "text": a.text || "Action",
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
    activeList.setProperty(index, "body", data.body);
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
  function queueImage(path, imageId) {
    if (!path || !path.startsWith("image://") || !imageId)
      return;
    const dest = Settings.cacheDirImagesNotifications + imageId + ".png";

    for (const req of imageQueue) {
      if (req.imageId === imageId)
        return;
    }

    imageQueue.push({
                      "src": path,
                      "dest": dest,
                      "imageId": imageId
                    });

    if (imageQueue.length === 1)
      cacher.source = path;
  }

  function updateImagePath(id, path) {
    updateModel(activeList, id, "cachedImage", path);
    updateModel(historyList, id, "cachedImage", path);
    saveHistory();
  }

  function updateModel(model, id, prop, value) {
    for (var i = 0; i < model.count; i++) {
      if (model.get(i).id === id) {
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
      if (old.cachedImage && old.cachedImage.startsWith(Settings.cacheDirImagesNotifications)) {
        Quickshell.execDetached(["rm", "-f", old.cachedImage]);
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

        let cachedImage = item.cachedImage || "";
        if (item.originalImage && item.originalImage.startsWith("image://") && !cachedImage) {
          const imageId = generateImageId(item, item.originalImage);
          if (imageId) {
            cachedImage = Settings.cacheDirImagesNotifications + imageId + ".png";
          }
        }

        historyList.append({
                             "id": item.id || "",
                             "summary": item.summary || "",
                             "body": item.body || "",
                             "appName": item.appName || "",
                             "urgency": item.urgency < 0 || item.urgency > 2 ? 1 : item.urgency,
                             "timestamp": time,
                             "originalImage": item.originalImage || "",
                             "cachedImage": cachedImage
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

  function stripTags(text) {
    return text.replace(/<[^>]*>?/gm, '');
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
    activeNotifications[id]?.notification?.dismiss();
    removeNotification(id);
  }

  function dismissOldestActive() {
    if (activeList.count > 0) {
      const lastNotif = activeList.get(activeList.count - 1);
      dismissActiveNotification(lastNotif.id);
    }
  }

  function dismissAllActive() {
    for (const id in activeNotifications) {
      activeNotifications[id].notification?.dismiss();
      activeNotifications[id].watcher?.destroy();
    }
    activeList.clear();
    activeNotifications = {};
    quickshellIdToInternalId = {};
  }

  function invokeAction(id, actionId) {
    const notifData = activeNotifications[id];
    if (!notifData?.notification?.actions)
      return false;

    for (const action of notifData.notification.actions) {
      if (action.identifier === actionId && action.invoke) {
        action.invoke();
        return true;
      }
    }
    return false;
  }

  function removeFromHistory(notificationId) {
    for (var i = 0; i < historyList.count; i++) {
      const notif = historyList.get(i);
      if (notif.id === notificationId) {
        // Only delete cached images that are in our cache directory
        if (notif.cachedImage && notif.cachedImage.startsWith(Settings.cacheDirImagesNotifications)) {
          Quickshell.execDetached(["rm", "-f", notif.cachedImage]);
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
      if (oldest.cachedImage && oldest.cachedImage.startsWith(Settings.cacheDirImagesNotifications)) {
        Quickshell.execDetached(["rm", "-f", oldest.cachedImage]);
      }
      historyList.remove(historyList.count - 1);
      saveHistory();
      return true;
    }
    return false;
  }

  function clearHistory() {
    try {
      Quickshell.execDetached(["sh", "-c", `rm -rf "${Settings.cacheDirImagesNotifications}"*`]);
    } catch (e) {
      Logger.e("Notifications", "Failed to clear cache directory:", e);
    }

    historyList.clear();
    saveHistory();
  }

  // Signals
  signal animateAndRemove(string notificationId)

  onDoNotDisturbChanged: {
    ToastService.showNotice(doNotDisturb ? I18n.tr("toast.do-not-disturb.enabled") : I18n.tr("toast.do-not-disturb.disabled"), doNotDisturb ? I18n.tr("toast.do-not-disturb.enabled-desc") : I18n.tr("toast.do-not-disturb.disabled-desc"), doNotDisturb ? "bell-off" : "bell");
  }
}
