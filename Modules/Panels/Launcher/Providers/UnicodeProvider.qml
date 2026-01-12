import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Keyboard

Item {
  id: root

  // Provider metadata
  property string name: I18n.tr("launcher.providers.unicode")
  property var launcher: null
  property string iconMode: Settings.data.appLauncher.iconMode
  property bool handleSearch: false
  property string supportedLayouts: "list" // List layout for better readability
  property bool supportsAutoPaste: true // Characters can be auto-pasted

  property string selectedCategory: "recent"
  property bool showsCategories: true // Default to showing categories

  // Empty state message for category view
  readonly property string emptyBrowsingMessage: selectedCategory === "recent" ? I18n.tr("launcher.providers.unicode-no-recent") : ""

  // Category icons derived from Unicode blocks
  property var categoryIcons: {
    var icons = { "recent": "clock" };
    for (var i = 0; i < UnicodeService.unicodeBlocks.length; i++) {
      var block = UnicodeService.unicodeBlocks[i];
      icons[block.name] = block.icon;
    }
    return icons;
  }

  // Categories list: recent + all unicode blocks
  property var categories: {
    var cats = ["recent"];
    for (var i = 0; i < UnicodeService.unicodeBlocks.length; i++) {
      cats.push(UnicodeService.unicodeBlocks[i].name);
    }
    return cats;
  }

  function getCategoryName(category) {
    var names = {
      "recent": I18n.tr("launcher.categories.unicode-recent"),
      "arrows": I18n.tr("launcher.categories.unicode-arrows"),
      "mathematical": I18n.tr("launcher.categories.unicode-mathematical"),
      "box-drawing": I18n.tr("launcher.categories.unicode-box-drawing"),
      "block-elements": I18n.tr("launcher.categories.unicode-block-elements"),
      "geometric": I18n.tr("launcher.categories.unicode-geometric"),
      "misc-symbols": I18n.tr("launcher.categories.unicode-misc-symbols"),
      "currency": I18n.tr("launcher.categories.unicode-currency"),
      "greek": I18n.tr("launcher.categories.unicode-greek"),
      "cyrillic": I18n.tr("launcher.categories.unicode-cyrillic"),
      "misc-technical": I18n.tr("launcher.categories.unicode-misc-technical"),
      "superscripts": I18n.tr("launcher.categories.unicode-superscripts"),
      "number-forms": I18n.tr("launcher.categories.unicode-number-forms"),
      "dingbats": I18n.tr("launcher.categories.unicode-dingbats"),
      "latin-extended": I18n.tr("launcher.categories.unicode-latin-extended"),
      "braille": I18n.tr("launcher.categories.unicode-braille")
    };
    return names[category] || category;
  }

  // Initialize provider
  function init() {
    Logger.d("UnicodeProvider", "Initialized");
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
    return searchText.startsWith(">unicode");
  }

  // Return available commands when user types ">"
  function commands() {
    return [
      {
        "name": ">unicode",
        "description": I18n.tr("launcher.providers.unicode-search-description"),
        "icon": iconMode === "tabler" ? "code" : "code",
        "isTablerIcon": true,
        "isImage": false,
        "onActivate": function() {
          launcher.setSearchText(">unicode ");
        }
      }
    ];
  }

  // Get search results
  function getResults(searchText) {
    if (!searchText.startsWith(">unicode")) {
      return [];
    }

    var query = searchText.slice(8).trim(); // ">unicode ".length = 8

    if (query === "") {
      showsCategories = true;
      var chars = UnicodeService.getCharactersByCategory(selectedCategory);
      return chars.map(formatCharEntry);
    } else {
      showsCategories = false;
      var chars = UnicodeService.search(query);
      return chars.map(formatCharEntry);
    }
  }

  // Format a character entry for the results list
  function formatCharEntry(charData) {
    var charValue = charData.char;
    // Show character + name in title, hex in description
    var title = charValue + "  " + (charData.name || charData.hex);
    var desc = charData.name ? charData.hex : getCategoryName(charData.category);

    return {
      "name": title,
      "description": desc,
      "icon": null,
      "isImage": false,
      "autoPasteText": charValue,
      "provider": root,
      "onAutoPaste": function() {
        UnicodeService.recordUsage(charValue);
      },
      "onActivate": function() {
        UnicodeService.copy(charValue);
        launcher.close();
      }
    };
  }
}
