import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Keyboard

Item {
  id: root

  // Provider metadata
  property string name: I18n.tr("launcher.providers.emoji")
  property var launcher: null
  property string iconMode: Settings.data.appLauncher.iconMode
  property bool handleSearch: false

  property string selectedCategory: "recent"
  property bool isBrowsingMode: false

  property var categoryIcons: ({
                                 "recent": "clock",
                                 "people": "user",
                                 "animals": "paw",
                                 "nature": "leaf",
                                 "food": "apple",
                                 "activity": "run",
                                 "travel": "plane",
                                 "objects": "home",
                                 "symbols": "star",
                                 "flags": "flag"
                               })

  property var categories: ["recent", "people", "animals", "nature", "food", "activity", "travel", "objects", "symbols", "flags"]

  function getCategoryName(category) {
    const names = {
      "recent": I18n.tr("launcher.categories.emoji.recent"),
      "people": I18n.tr("launcher.categories.emoji.people"),
      "animals": I18n.tr("launcher.categories.emoji.animals"),
      "nature": I18n.tr("launcher.categories.emoji.nature"),
      "food": I18n.tr("launcher.categories.emoji.food"),
      "activity": I18n.tr("launcher.categories.emoji.activity"),
      "travel": I18n.tr("launcher.categories.emoji.travel"),
      "objects": I18n.tr("launcher.categories.emoji.objects"),
      "symbols": I18n.tr("launcher.categories.emoji.symbols"),
      "flags": I18n.tr("launcher.categories.emoji.flags")
    };
    return names[category] || category;
  }

  // Force update results when emoji service loads
  Connections {
    target: EmojiService
    function onLoadedChanged() {
      if (EmojiService.loaded && root.launcher) {
        root.launcher.updateResults();
      }
    }
  }

  // Initialize provider
  function init() {
    Logger.d("EmojiProvider", "Initialized");
  }

  function selectCategory(category) {
    selectedCategory = category;
    if (launcher) {
      launcher.updateResults();
    }
  }

  function onOpened() {
    // Always reset to "recent" category when opening
    selectedCategory = "recent";
  }

  // Check if this provider handles the command
  function handleCommand(searchText) {
    return searchText.startsWith(">emoji");
  }

  // Return available commands when user types ">"
  function commands() {
    return [
          {
            "name": ">emoji",
            "description": I18n.tr("launcher.providers.emoji-search-description"),
            "icon": iconMode === "tabler" ? "mood-smile" : "face-smile",
            "isTablerIcon": true,
            "isImage": false,
            "onActivate": function () {
              launcher.setSearchText(">emoji ");
            }
          }
        ];
  }

  // Get search results
  function getResults(searchText) {
    if (!searchText.startsWith(">emoji")) {
      return [];
    }

    if (!EmojiService.loaded) {
      return [
            {
              "name": I18n.tr("launcher.providers.emoji-loading"),
              "description": I18n.tr("launcher.providers.emoji-loading-description"),
              "icon": iconMode === "tabler" ? "refresh" : "view-refresh",
              "isTablerIcon": true,
              "isImage": false,
              "onActivate": function () {}
            }
          ];
    }

    var query = searchText.slice(6).trim();

    if (query === "") {
      isBrowsingMode = true;
      var emojis = EmojiService.getEmojisByCategory(selectedCategory);
      return emojis.map(formatEmojiEntry);
    } else {
      isBrowsingMode = false;
      var emojis = EmojiService.search(query);
      return emojis.map(formatEmojiEntry);
    }
  }

  // Format an emoji entry for the results list
  function formatEmojiEntry(emoji) {
    let title = emoji.name;
    let description = emoji.keywords.join(", ");

    if (emoji.category) {
      description += " • Category: " + emoji.category;
    }

    const emojiChar = emoji.emoji;

    return {
      "name": title,
      "description": description,
      "icon": null,
      "isImage": false,
      "emojiChar": emojiChar,
      "onActivate": function () {
        EmojiService.copy(emojiChar);
        launcher.close();
      }
    };
  }
}
