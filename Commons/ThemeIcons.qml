pragma Singleton

import QtQuick
import Quickshell

Singleton {
  id: root

  function iconFromName(iconName, fallbackName) {
    const fallback = fallbackName || "application-x-executable";
    try {
      if (iconName && typeof Quickshell !== 'undefined' && Quickshell.iconPath) {
        const p = Quickshell.iconPath(iconName, "");
        if (p && p !== "") return p;
      }
    } catch (e) {
      // ignore
    }
    
    try {
      return Quickshell.iconPath ? Quickshell.iconPath(fallback, "") : "";
    } catch (e2) {
      return "";
    }
  }

  function iconForAppId(appId, fallbackName) {
    const fallback = fallbackName || "application-x-executable";
    
    if (!appId) return root.iconFromName(fallback, fallback);

    try {
      // 1. Use the working logic from AppSearch to guess the icon name
      // We check if AppSearch exists to prevent crashes if the file fails to load
      if (typeof AppSearch !== 'undefined') {
        const guessedIconName = AppSearch.guessIcon(appId);
        
        // 2. Resolve that name to a path
        const path = root.iconFromName(guessedIconName, fallback);
        if (path && path !== "") return path;
      }
    } catch (e) {
      console.warn("ThemeIcons: Error calling AppSearch.guessIcon:", e);
    }

    try {
      if (typeof DesktopEntries !== 'undefined') {
        const entry = DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(appId) : null;
        if (entry && entry.icon) return root.iconFromName(entry.icon, fallback);
      }
    } catch (e) {
      // ignore
    }

    return root.iconFromName(fallback, fallback);
  }

  function distroLogoPath() {
    try {
      return (typeof OSInfo !== 'undefined' && OSInfo.distroIconPath) ? OSInfo.distroIconPath : "";
    } catch (e) {
      return "";
    }
  }
}