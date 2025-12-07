import QtQuick
import Quickshell
import qs.Commons

Item {
  property var launcher: null
  property string name: I18n.tr("plugins.command")

  function handleCommand(query) {
    return query.startsWith(">cmd");
  }

  function commands() {
    return [
          {
            "name": ">cmd",
            "description": I18n.tr("plugins.command-description"),
            "icon": "utilities-terminal",
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
            "name": I18n.tr("plugins.command-name"),
            "description": I18n.tr("plugins.command-description"),
            "icon": "utilities-terminal",
            "isImage": false,
            "onActivate": function () {
              launcher.close();
              Quickshell.execDetached(["sh", "-c", expression]);
            }
          }
        ];
  }
}
