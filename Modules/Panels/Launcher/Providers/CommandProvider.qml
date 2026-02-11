import QtQuick
import Quickshell
import qs.Commons

Item {
  property var launcher: null
  property string name: I18n.tr("common.command")
  property string iconMode: Settings.data.appLauncher.iconMode

  function handleCommand(query) {
    return query.startsWith(">cmd");
  }

  function commands() {
    return [
          {
            "name": ">cmd",
            "description": I18n.tr("launcher.providers.command-description"),
            "icon": iconMode === "tabler" ? "terminal" : "utilities-terminal",
            "isTablerIcon": true,
            "isImage": false,
            "onActivate": function () {
              launcher.setSearchText(">cmd ");
            }
          }
        ];
  }

  function getResults(query) {
    if (!query.startsWith(">cmd"))
      return [];

    let expression = query.substring(4).trim();
    return [
          {
            "name": I18n.tr("common.command"),
            "description": I18n.tr("launcher.providers.command-description"),
            "icon": iconMode === "tabler" ? "terminal" : "utilities-terminal",
            "isTablerIcon": true,
            "isImage": false,
            "onActivate": function () {
              launcher.closeImmediately();
              Qt.callLater(() => {
                             Logger.d("CommandProvider", "Executing shell command: " + expression);
                             Quickshell.execDetached(["sh", "-c", expression]);
                           });
            }
          }
        ];
  }
}
