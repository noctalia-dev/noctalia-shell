import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Keyboard

Item {
  id: root

  property string name: I18n.tr("plugins.search")
  property var launcher: null
  property string iconMode: Settings.data.applauncher.iconMode
  property bool handleSearch: false

  property string defaultEngine: "ddg"

  property var engines: ([
                           {
                             "id": "ddg",
                             "name": "DuckDuckGo",
                             "url": "https://duckduckgo.com/?q=%s",
                             "icon": "qrc:/icons/duckduckgo.png"
                           },
                           {
                             "id": "google",
                             "name": "Google",
                             "url": "https://www.google.com/search?q=%s",
                             "icon": "qrc:/icons/google.png"
                           },
                           {
                             "id": "bing",
                             "name": "Bing",
                             "url": "https://www.bing.com/search?q=%s",
                             "icon": "qrc:/icons/bing.png"
                           },
                           {
                             "id": "youtube",
                             "name": "YouTube",
                             "url": "https://www.youtube.com/results?search_query=%s",
                             "icon": "qrc:/icons/youtube.png"
                           },
                           {
                             "id": "wikipedia",
                             "name": "Wikipedia",
                             "url": "https://en.wikipedia.org/wiki/Special:Search?search=%s",
                             "icon": "qrc:/icons/wikipedia.png"
                           },
                           {
                             "id": "github",
                             "name": "GitHub",
                             "url": "https://github.com/search?q=%s",
                             "icon": "qrc:/icons/github.png"
                           },
                           {
                             "id": "amazon",
                             "name": "Amazon",
                             "url": "https://www.amazon.com/s?k=%s",
                             "icon": "qrc:/icons/amazon.png"
                           },
                           {
                             "id": "reddit",
                             "name": "Reddit",
                             "url": "https://www.reddit.com/search/?q=%s",
                             "icon": "qrc:/icons/reddit.png"
                           },
                           {
                             "id": "stackoverflow",
                             "name": "Stack Overflow",
                             "url": "https://stackoverflow.com/search?q=%s",
                             "icon": "qrc:/icons/stackoverflow.png"
                           },
                         ])

  function getEngineById(id) {
    for (var i = 0; i < engines.length; i++) {
      if (engines[i].id === id) {
        return engines[i];
      }
    }
    return null;
  }

  function init() {
    Logger.i("WebSearchPlugin", "Initialized (default engine: " + defaultEngine + ")");
  }

  function onOpened() {
  }

  function handleCommand(searchText) {
    return searchText.startsWith(">search");
  }

  function commands() {
    return [
          {
            "name": "search",
            "description": "Search the web",
            "icon": iconMode === "tabler" ? "search" : "system-search",
            "isTablerIcon": true,
            "isImage": false,
            "onActivate": function () {
              launcher.setSearchText(">search");
            }
          }
        ];
  }

  function formateSearchEntry(engine, query) {
    var q = query.trim();
    var title = q === "" ? I18.tr("plugins.search.use-engine").replace("%engine%", engine.name) : I18.tr("plugins.search.search-with").replace("%engine%", engine.name).replace("%query%", q);
    var desc = q === "" ? I18n.tr("plugins.search.set-default") : I18n.tr("plugins.search.open-in-browser");
    var icon = engine.icon;

    return {
      "name": title,
      "description": desc,
      "icon": iconMode === "tabler" ? icon : icon,
      "isTablerIcon": true,
      "EngineId": engine.id,
      "Query": q,
      "onActivate": function () {
        if (this.Query === "") {
          root.defaultEngine = this.EngineId;
          if (launcher) {
            launcher.setSearchText(">search");
          }
        } else {
          var template = engine.url;
          var encoded = encodeURIComponent(this.Query);
          var url = template.replace("%s", encoded);
          try {
            Qt.openUrlExternally(url);
          } catch (e) {
            Logger.e("WebSearchPlugin", "Failed to open URL: " + url + " (" + e + ")");
          }
          if (launcher) {
            launcher.close();
          }
        }
      }
    };
  }

  function getResults(searchText) {
    if (!searchText.startsWith(">search")) {
      return [];
    }

    var rest = searchText.slice(7).trim();
    if (rest === "") {
      return engines.map(function (e) {
        return formatSearchEntry(e, "");
      });
    }

    var tokens = rest.split(/\s+/);
    var first = tokens[0];
    var chosenEngine = null;
    var query = rest;

    var aliases = {
      "g": "google",
      "google": "google",
      "ddg": "ddg",
      "duck": "ddg",
      "duckduckgo": "ddg",
      "b": "bing",
      "bing": "bing",
      "y": "yahoo",
      "yahoo": "yahoo"
    };

    if (aliases[first.toLowerCase()]) {
      var id = aliases[first.toLowerCase()];
      chosenEngine = getEngineById(id);
      query = tokens.slice(1).join("").trim();
      if (query === "") {
        return [formatSearchEntry(chosenEngine, "")];
      }
      return [formatSearchEntry(chosenEngine, query)];
    }

    var results = [];

    var def = getEngineById(root.defaultEngine);
    if (def) {
      results.push(formatSearchEntry(def, rest));
    }

    for (var i = 0; i < engines.length; ++i) {
      if (engines[i].id === root.defaultEngine)
        continue;
      results.push(formatSearchEntry(engines[i], rest));
    }

    return results;
  }
}
