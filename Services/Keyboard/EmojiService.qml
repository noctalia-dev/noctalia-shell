pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Manages emoji data loading, searching, and clipboard operations
Singleton {
  id: root

  property var emojis: []
  property bool loaded: false

  // Usage tracking for popular emojis
  // Format: { "emoji": { count: number, lastUsed: timestamp } }
  property var usageCounts: ({})

  // File path for persisting usage data
  readonly property string usageFilePath: Settings.cacheDir + "emoji_usage.json"

  // Searches emojis based on query
  function search(query) {
    if (!loaded) {
      return [];
    }

    if (!query || query.trim() === "") {
      return emojis;
    }

    const terms = query.toLowerCase().split(" ").filter(t => t);
    const results = emojis.filter(emoji => {
                                    for (let term of terms) {
                                      const emojiMatch = emoji.emoji.toLowerCase().includes(term);
                                      const nameMatch = emoji.name.toLowerCase().includes(term);
                                      const keywordMatch = emoji.keywords.some(kw => kw.toLowerCase().includes(term));
                                      const categoryMatch = emoji.category.toLowerCase().includes(term);

                                      if (!emojiMatch && !nameMatch && !keywordMatch && !categoryMatch) {
                                        return false;
                                      }
                                    }
                                    return true;
                                  });

    return results;
  }

  function _getPopularEmojis(limit) {
    var emojisWithUsage = emojis.map(function (emoji) {
      const usageData = usageCounts[emoji.emoji];
      return {
        emoji: emoji,
        usageCount: usageData ? (usageData.count || 0) : 0,
        lastUsed: usageData ? (usageData.lastUsed || 0) : 0
      };
    }).filter(function (item) {
      return item.usageCount > 0;
    });

    // Sort by last used timestamp (descending - most recent first)
    // Then by usage count if timestamps are equal
    emojisWithUsage.sort(function (a, b) {
      if (b.lastUsed !== a.lastUsed) {
        return b.lastUsed - a.lastUsed;
      }
      if (b.usageCount !== a.usageCount) {
        return b.usageCount - a.usageCount;
      }
      return a.emoji.name.localeCompare(b.emoji.name);
    });

    // Return the emoji objects limited by the specified count
    return emojisWithUsage.slice(0, limit).map(function (item) {
      return item.emoji;
    });
  }

  function getCategoriesWithCounts() {
    if (!loaded) {
      return [];
    }

    var categoryCounts = {};

    for (var i = 0; i < emojis.length; i++) {
      var emoji = emojis[i];
      var category = emoji.category || "other";
      if (!categoryCounts[category]) {
        categoryCounts[category] = 0;
      }
      categoryCounts[category]++;
    }

    var categories = [];
    for (var cat in categoryCounts) {
      categories.push({
                        name: cat,
                        count: categoryCounts[cat]
                      });
    }

    return categories;
  }

  function getEmojisByCategory(category) {
    if (!loaded) {
      return [];
    }

    if (category === "recent") {
      return _getPopularEmojis(25);
    }

    return emojis.filter(function (emoji) {
      return emoji.category === category;
    });
  }

  // Record emoji usage
  function recordUsage(emojiChar) {
    if (emojiChar) {
      const currentData = usageCounts[emojiChar] || {
        count: 0,
        lastUsed: 0
      };
      usageCounts[emojiChar] = {
        count: currentData.count + 1,
        lastUsed: Date.now()
      };
      _saveUsageData();
    }
  }

  // Ensure usage file exists with default content
  function _ensureUsageFileExists() {
    Quickshell.execDetached(["sh", "-c", `mkdir -p "$(dirname "${root.usageFilePath}")" && echo '{}' > "${root.usageFilePath}"`]);
  }

  // File paths
  readonly property string userEmojiPath: Settings.configDir + "emoji.json"
  readonly property string builtinEmojiPath: `${Quickshell.shellDir}/Assets/Launcher/emoji.json`

  // Internal data
  property var _userEmojiData: []
  property var _builtinEmojiData: []
  property int _pendingLoads: 0

  // Initialize on component completion
  Component.onCompleted: {
    _loadUsageData();
    _loadEmojis();
  }

  // File loaders
  FileView {
    id: userEmojiFile
    path: root.userEmojiPath
    printErrors: false
    watchChanges: false

    onLoaded: {
      try {
        const content = text();
        if (content) {
          const parsed = JSON.parse(content);
          _userEmojiData = Array.isArray(parsed) ? parsed : [];
        } else {
          _userEmojiData = [];
        }
      } catch (e) {
        _userEmojiData = [];
      }
      _onLoadComplete();
    }

    onLoadFailed: function (error) {
      _userEmojiData = [];
      _onLoadComplete();
    }
  }

  FileView {
    id: builtinEmojiFile
    path: root.builtinEmojiPath
    printErrors: false
    watchChanges: false

    onLoaded: {
      try {
        const content = text();
        if (content) {
          const parsed = JSON.parse(content);
          _builtinEmojiData = Array.isArray(parsed) ? parsed : [];
        } else {
          _builtinEmojiData = [];
        }
      } catch (e) {
        _builtinEmojiData = [];
      }
      _onLoadComplete();
    }

    onLoadFailed: function (error) {
      _builtinEmojiData = [];
      _onLoadComplete();
    }
  }

  // Load emoji files
  function _loadEmojis() {
    _pendingLoads = 2;
    userEmojiFile.reload();
    builtinEmojiFile.reload();
  }

  // Called when one file finishes loading
  function _onLoadComplete() {
    _pendingLoads--;
    if (_pendingLoads <= 0) {
      _finalizeEmojis();
    }
  }

  // Merge and deduplicate emojis
  function _finalizeEmojis() {
    const emojiMap = new Map();

    // Add built-in emojis first
    for (const emoji of _builtinEmojiData) {
      if (emoji && emoji.emoji) {
        emojiMap.set(emoji.emoji, emoji);
      }
    }

    // Add user emojis (override built-ins if duplicate)
    for (const emoji of _userEmojiData) {
      if (emoji && emoji.emoji) {
        emojiMap.set(emoji.emoji, emoji);
      }
    }

    emojis = Array.from(emojiMap.values());
    loaded = true;
  }

  // FileView for usage data
  FileView {
    id: usageFile
    path: root.usageFilePath
    printErrors: false
    watchChanges: false

    onLoaded: {
      try {
        const content = text();
        if (content && content.trim() !== "") {
          const parsed = JSON.parse(content);
          if (parsed && typeof parsed === 'object') {
            root.usageCounts = parsed;
          } else {
            root.usageCounts = {};
          }
        } else {
          root.usageCounts = {};
        }
      } catch (e) {
        root.usageCounts = {};
      }
    }

    onLoadFailed: function (error) {
      root.usageCounts = {};
      Qt.callLater(_ensureUsageFileExists);
    }
  }

  // Timer for debouncing usage data saves
  Timer {
    id: saveTimer
    interval: 1000
    repeat: false
    onTriggered: _doSaveUsageData()
  }

  // Load usage data
  function _loadUsageData() {
    usageFile.reload();
  }

  // Save usage data with debounce
  function _saveUsageData() {
    saveTimer.restart();
  }

  // Actually save usage data to file
  function _doSaveUsageData() {
    try {
      const content = JSON.stringify(root.usageCounts);
      Quickshell.execDetached(["sh", "-c", `mkdir -p "$(dirname "${root.usageFilePath}")" && echo '${content}' > "${root.usageFilePath}"`]);
    } catch (e) {
      Logger.e("EmojiService", "Failed to save usage data: " + e.message);
    }
  }

  // Copies emoji to clipboard
  function copy(emojiChar) {
    if (emojiChar) {
      recordUsage(emojiChar);  // Record usage before copying
      Quickshell.execDetached(["sh", "-c", `echo -n "${emojiChar}" | wl-copy`]);
    }
  }
}
