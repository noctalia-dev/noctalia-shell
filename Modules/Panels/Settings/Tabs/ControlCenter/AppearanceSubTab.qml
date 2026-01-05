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

    NHeader {
      label: I18n.tr("settings.control-center.section.label")
      description: I18n.tr("settings.control-center.section.description")
    }

    NComboBox {
      id: controlCenterPosition
      label: I18n.tr("settings.control-center.position.label")
      description: I18n.tr("settings.control-center.position.description")
      Layout.fillWidth: true
      model: [
        {
          "key": "close_to_bar_button",
          "name": I18n.tr("options.control-center.position.close_to_bar_button")
        },
        {
          "key": "center",
          "name": I18n.tr("options.control-center.position.center")
        },
        {
          "key": "top_center",
          "name": I18n.tr("options.control-center.position.top_center")
        },
        {
          "key": "top_left",
          "name": I18n.tr("options.control-center.position.top_left")
        },
        {
          "key": "top_right",
          "name": I18n.tr("options.control-center.position.top_right")
        },
        {
          "key": "bottom_center",
          "name": I18n.tr("options.control-center.position.bottom_center")
        },
        {
          "key": "bottom_left",
          "name": I18n.tr("options.control-center.position.bottom_left")
        },
        {
          "key": "bottom_right",
          "name": I18n.tr("options.control-center.position.bottom_right")
        }
      ]
      currentKey: Settings.data.controlCenter.position
      onSelected: function (key) {
        Settings.data.controlCenter.position = key;
      }
      isSettings: true
      defaultValue: Settings.getDefaultValue("controlCenter.position")
    }

    NComboBox {
      id: diskPathComboBox
      Layout.fillWidth: true
      Layout.topMargin: Style.marginM
      label: I18n.tr("settings.control-center.system-monitor-disk-path.label")
      description: I18n.tr("settings.control-center.system-monitor-disk-path.description")
      model: {
        const paths = Object.keys(SystemStatService.diskPercents).sort();
        return paths.map(path => ({
                                    key: path,
                                    name: path
                                  }));
      }
      currentKey: Settings.data.controlCenter.diskPath || "/"
      onSelected: key => Settings.data.controlCenter.diskPath = key
      isSettings: true
      defaultValue: Settings.getDefaultValue("controlCenter.diskPath") || "/"
    }
  }

  Rectangle {
    Layout.fillHeight: true
  }
}
