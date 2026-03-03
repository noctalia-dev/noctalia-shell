import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true
  Layout.fillHeight: true

  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NComboBox {
      id: controlCenterPosition
      label: I18n.tr("common.position")
      description: I18n.tr("panels.control-center.position-description")
      Layout.fillWidth: true
      model: [
        {
          "key": "close_to_bar_button",
          "name": I18n.tr("positions.close-to-bar")
        },
        {
          "key": "center",
          "name": I18n.tr("positions.center")
        },
        {
          "key": "top_center",
          "name": I18n.tr("positions.top-center")
        },
        {
          "key": "top_left",
          "name": I18n.tr("positions.top-left")
        },
        {
          "key": "top_right",
          "name": I18n.tr("positions.top-right")
        },
        {
          "key": "bottom_center",
          "name": I18n.tr("positions.bottom-center")
        },
        {
          "key": "bottom_left",
          "name": I18n.tr("positions.bottom-left")
        },
        {
          "key": "bottom_right",
          "name": I18n.tr("positions.bottom-right")
        }
      ]
      currentKey: Settings.data.controlCenter.position
      onSelected: function (key) {
        Settings.data.controlCenter.position = key;
      }
      defaultValue: Settings.getDefaultValue("controlCenter.position")
    }

    NComboBox {
      id: diskPathComboBox
      Layout.fillWidth: true
      label: I18n.tr("panels.control-center.system-monitor-disk-path-label")
      description: I18n.tr("panels.control-center.system-monitor-disk-path-description")
      model: {
        const paths = Object.keys(SystemStatService.diskPercents).sort();
        return paths.map(path => ({
                                    key: path,
                                    name: path
                                  }));
      }
      currentKey: Settings.data.controlCenter.diskPath || "/"
      onSelected: key => Settings.data.controlCenter.diskPath = key
      defaultValue: Settings.getDefaultValue("controlCenter.diskPath") || "/"
    }
  }

  Rectangle {
    Layout.fillHeight: true
  }
}
