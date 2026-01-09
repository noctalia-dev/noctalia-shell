import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NComboBox {
    label: I18n.tr("panels.audio.visualizer-type-label")
    description: I18n.tr("panels.audio.visualizer-type-description")
    model: [
      {
        "key": "none",
        "name": I18n.tr("common.none")
      },
      {
        "key": "linear",
        "name": I18n.tr("options.visualizer-types.linear")
      },
      {
        "key": "mirrored",
        "name": I18n.tr("options.visualizer-types.mirrored")
      },
      {
        "key": "wave",
        "name": I18n.tr("options.visualizer-types.wave")
      }
    ]
    currentKey: Settings.data.audio.visualizerType
    defaultValue: Settings.getDefaultValue("audio.visualizerType")
    onSelected: key => Settings.data.audio.visualizerType = key
  }

  NComboBox {
    label: I18n.tr("panels.audio.media-frame-rate-label")
    description: I18n.tr("panels.audio.media-frame-rate-description")
    model: [
      {
        "key": "30",
        "name": I18n.tr("options.frame-rates-fps", {
                          "fps": "30"
                        })
      },
      {
        "key": "60",
        "name": I18n.tr("options.frame-rates-fps", {
                          "fps": "60"
                        })
      },
      {
        "key": "100",
        "name": I18n.tr("options.frame-rates-fps", {
                          "fps": "100"
                        })
      },
      {
        "key": "120",
        "name": I18n.tr("options.frame-rates-fps", {
                          "fps": "120"
                        })
      },
      {
        "key": "144",
        "name": I18n.tr("options.frame-rates-fps", {
                          "fps": "144"
                        })
      },
      {
        "key": "165",
        "name": I18n.tr("options.frame-rates-fps", {
                          "fps": "165"
                        })
      },
      {
        "key": "240",
        "name": I18n.tr("options.frame-rates-fps", {
                          "fps": "240"
                        })
      }
    ]
    currentKey: Settings.data.audio.cavaFrameRate
    defaultValue: Settings.getDefaultValue("audio.cavaFrameRate")
    onSelected: key => Settings.data.audio.cavaFrameRate = key
  }
}
