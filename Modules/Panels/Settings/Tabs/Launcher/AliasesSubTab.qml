import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NText {
    text: I18n.tr("launcher.aliases-desc")
    color: Color.mOnSurfaceVariant
    wrapMode: Text.Wrap
    Layout.fillWidth: true
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM
      Layout.leftMargin: Style.marginS
      Layout.rightMargin: Style.marginS
      visible: Settings.data.appLauncher.commandAliases.length > 0

      NText {
        text: I18n.tr("launcher.settings-command-label")
        font.weight: Font.Bold
        Layout.fillWidth: true
      }
      NText {
        text: I18n.tr("launcher.settings-alias-label")
        font.weight: Font.Bold
        Layout.preferredWidth: 150
      }
      Item { Layout.preferredWidth: Style.baseWidgetSize }
    }

    NDivider {
        Layout.fillWidth: true
        visible: Settings.data.appLauncher.commandAliases.length > 0
    }

    Repeater {
      model: Settings.data.appLauncher.commandAliases

      RowLayout {
        id: row
        required property var modelData
        required property int index
        Layout.fillWidth: true
        spacing: Style.marginM
        Layout.leftMargin: Style.marginS
        Layout.rightMargin: Style.marginS

        NTextInput {
          Layout.fillWidth: true
          text: modelData.command || ""
          placeholderText: I18n.tr("launcher.settings-command-placeholder")
          onEditingFinished: {
            if (text !== modelData.command) {
              var aliases = JSON.parse(JSON.stringify(Settings.data.appLauncher.commandAliases));
              aliases[index].command = text.trim();
              Settings.data.appLauncher.commandAliases = aliases;
            }
          }
        }

        NTextInput {
          Layout.preferredWidth: 150
          text: modelData.alias || ""
          placeholderText: I18n.tr("launcher.settings-alias-placeholder")
          onEditingFinished: {
            if (text !== modelData.alias) {
              var aliases = JSON.parse(JSON.stringify(Settings.data.appLauncher.commandAliases));
              aliases[index].alias = text.trim();
              Settings.data.appLauncher.commandAliases = aliases;
            }
          }
        }

        NIconButton {
          icon: "trash"
          tooltipText: I18n.tr("launcher.settings-alias-delete")
          colorFgHover: Color.mError
          onClicked: {
            var aliases = JSON.parse(JSON.stringify(Settings.data.appLauncher.commandAliases));
            aliases.splice(index, 1);
            Settings.data.appLauncher.commandAliases = aliases;
          }
        }
      }
    }

    NButton {
      text: I18n.tr("launcher.settings-alias-add")
      icon: "plus"
      onClicked: {
        var aliases = JSON.parse(JSON.stringify(Settings.data.appLauncher.commandAliases));
        aliases.push({ "alias": "", "command": "" });
        Settings.data.appLauncher.commandAliases = aliases;
      }
    }
  }
}
