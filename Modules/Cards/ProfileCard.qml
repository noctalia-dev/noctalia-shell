import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Modules.Panels.Settings
import qs.Services.System
import qs.Services.UI
import qs.Widgets

// Header card with avatar, user and quick actions
NBox {
  id: root

  property string uptimeText: "--"

  RowLayout {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.margins: Style.marginM
    spacing: Style.marginM

    NImageRounded {
      Layout.preferredWidth: Math.round(Style.baseWidgetSize * 1.25 * Style.uiScaleRatio)
      Layout.preferredHeight: Math.round(Style.baseWidgetSize * 1.25 * Style.uiScaleRatio)
      radius: Layout.preferredWidth / 2
      imagePath: Settings.preprocessPath(Settings.data.general.avatarImage)
      fallbackIcon: "person"
      borderColor: Color.mPrimary
      borderWidth: Style.borderS * 1.5
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginXXS
      NText {
        text: HostService.displayName
        font.weight: Style.fontWeightBold
      }
      NText {
        text: I18n.tr("system.uptime", {
                        "uptime": uptimeText
                      })
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }
    }

    RowLayout {
      spacing: Style.marginS
      Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
      Item {
        Layout.fillWidth: true
      }
      NIconButton {
        icon: "settings"
        tooltipText: I18n.tr("tooltips.open-settings")
        onClicked: {
          // Better close the control center in case the settings open in a separate window
          PanelService.openedPanel?.close();

          var panel = PanelService.getPanel("settingsPanel", screen);
          panel.requestedTab = SettingsPanel.Tab.General;
          panel.open();
        }
      }

      NIconButton {
        icon: "power"
        tooltipText: I18n.tr("tooltips.session-menu")
        onClicked: {
          PanelService.getPanel("sessionMenuPanel", screen)?.open();
          PanelService.getPanel("controlCenterPanel", screen)?.close();
        }
      }

      NIconButton {
        icon: "close"
        tooltipText: I18n.tr("common.close")
        onClicked: {
          PanelService.getPanel("controlCenterPanel", screen)?.close();
        }
      }
    }
  }

  // ----------------------------------
  // Uptime
  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: uptimeProcess.running = true
  }

  Process {
    id: uptimeProcess
    command: ["cat", "/proc/uptime"]
    running: true

    stdout: StdioCollector {
      onStreamFinished: {
        var uptimeSeconds = parseFloat(this.text.trim().split(' ')[0]);
        uptimeText = Time.formatVagueHumanReadableDuration(uptimeSeconds);
        uptimeProcess.running = false;
      }
    }
  }

  function updateSystemInfo() {
    uptimeProcess.running = true;
  }
}
