import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
  id: root

  // Provider metadata
  property string name: I18n.tr("common.settings")
  property var launcher: null
  property bool handleSearch: Settings.data.appLauncher.enableSettingsSearch
  property string supportedLayouts: "list"

  property var searchIndex: []

  FileView {
    id: searchIndexFile
    path: Quickshell.shellDir + "/Assets/settings-search-index.json"
    watchChanges: false
    printErrors: false

    onLoaded: {
      try {
        root.searchIndex = JSON.parse(text());
      } catch (e) {
        root.searchIndex = [];
      }
    }
  }

  function init() {
    Logger.d("SettingsProvider", "Initialized");
  }

  function getResults(query) {
    if (!query || searchIndex.length === 0)
      return [];

    const trimmed = query.trim();
    if (!trimmed || trimmed.length < 2)
      return [];

    // Build searchable items with resolved translations
    let items = [];
    for (let j = 0; j < searchIndex.length; j++) {
      const entry = searchIndex[j];
      items.push({
                   "labelKey": entry.labelKey,
                   "descriptionKey": entry.descriptionKey,
                   "widget": entry.widget,
                   "tab": entry.tab,
                   "tabLabel": entry.tabLabel,
                   "subTab": entry.subTab,
                   "subTabLabel": entry.subTabLabel || null,
                   "label": I18n.tr(entry.labelKey),
                   "description": entry.descriptionKey ? I18n.tr(entry.descriptionKey) : "",
                   "subTabName": entry.subTabLabel ? I18n.tr(entry.subTabLabel) : ""
                 });
    }

    const results = FuzzySort.go(trimmed, items, {
                                   "keys": ["label", "subTabName", "description"],
                                   "limit": 10,
                                   "scoreFn": function (r) {
                                     const labelScore = r[0].score;
                                     const subTabScore = r[1].score * 1.5;
                                     const descScore = r[2].score;
                                     return Math.max(labelScore, subTabScore, descScore);
                                   }
                                 });

    let launcherItems = [];
    for (let i = 0; i < results.length; i++) {
      const entry = results[i].obj;
      const score = results[i].score;
      const tabName = I18n.tr(entry.tabLabel);
      const subTabName = entry.subTabName || "";
      const breadcrumb = subTabName ? (tabName + " › " + subTabName) : tabName;

      launcherItems.push({
                           "name": entry.label,
                           "description": breadcrumb,
                           "icon": "settings",
                           "isTablerIcon": true,
                           "isImage": false,
                           "_score": score - 2,
                           "provider": root,
                           "onActivate": createActivateHandler(entry)
                         });
    }

    return launcherItems;
  }

  function createActivateHandler(entry) {
    return function () {
      if (launcher)
        launcher.close();

      Qt.callLater(() => {
                     var settingsPanel = PanelService.getPanel("settingsPanel", launcher.screen);
                     if (settingsPanel) {
                       settingsPanel.requestedEntry = entry;
                       settingsPanel.open();
                     }
                   });
    };
  }
}
