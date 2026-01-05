import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Media
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NHeader {
    label: I18n.tr("settings.audio.media.section.label")
    description: I18n.tr("settings.audio.media.section.description")
  }

  // Preferred player
  NTextInput {
    label: I18n.tr("settings.audio.media.primary-player.label")
    description: I18n.tr("settings.audio.media.primary-player.description")
    placeholderText: I18n.tr("settings.audio.media.primary-player.placeholder")
    text: Settings.data.audio.preferredPlayer
    isSettings: true
    defaultValue: Settings.getDefaultValue("audio.preferredPlayer")
    onTextChanged: {
      Settings.data.audio.preferredPlayer = text;
      MediaService.updateCurrentPlayer();
    }
  }

  // Blacklist editor
  ColumnLayout {
    spacing: Style.marginS
    Layout.fillWidth: true

    NTextInputButton {
      id: blacklistInput
      label: I18n.tr("settings.audio.media.excluded-player.label")
      description: I18n.tr("settings.audio.media.excluded-player.description")
      placeholderText: I18n.tr("settings.audio.media.excluded-player.placeholder")
      buttonIcon: "add"
      Layout.fillWidth: true
      onButtonClicked: {
        const val = (blacklistInput.text || "").trim();
        if (val !== "") {
          const arr = (Settings.data.audio.mprisBlacklist || []);
          if (!arr.find(x => String(x).toLowerCase() === val.toLowerCase())) {
            Settings.data.audio.mprisBlacklist = [...arr, val];
            blacklistInput.text = "";
            MediaService.updateCurrentPlayer();
          }
        }
      }
    }

    // Current blacklist entries
    Flow {
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginS
      spacing: Style.marginS

      Repeater {
        model: Settings.data.audio.mprisBlacklist
        delegate: Rectangle {
          required property string modelData
          property real pad: Style.marginS
          color: Qt.alpha(Color.mOnSurface, 0.125)
          border.color: Qt.alpha(Color.mOnSurface, Style.opacityLight)
          border.width: Style.borderS

          RowLayout {
            id: chipRow
            spacing: Style.marginXS
            anchors.fill: parent
            anchors.margins: pad

            NText {
              text: modelData
              color: Color.mOnSurface
              pointSize: Style.fontSizeS
              Layout.alignment: Qt.AlignVCenter
              Layout.leftMargin: Style.marginS
            }

            NIconButton {
              icon: "close"
              baseSize: Style.baseWidgetSize * 0.8
              Layout.alignment: Qt.AlignVCenter
              Layout.rightMargin: Style.marginXS
              onClicked: {
                const arr = (Settings.data.audio.mprisBlacklist || []);
                const idx = arr.findIndex(x => String(x) === modelData);
                if (idx >= 0) {
                  arr.splice(idx, 1);
                  Settings.data.audio.mprisBlacklist = arr;
                  MediaService.updateCurrentPlayer();
                }
              }
            }
          }

          implicitWidth: chipRow.implicitWidth + pad * 2
          implicitHeight: Math.max(chipRow.implicitHeight + pad * 2, Style.baseWidgetSize * 0.8)
          radius: Style.radiusM
        }
      }
    }
  }

  // Audio Visualizer section
  NComboBox {
    label: I18n.tr("settings.audio.media.visualizer-type.label")
    description: I18n.tr("settings.audio.media.visualizer-type.description")
    model: [
      {
        "key": "none",
        "name": I18n.tr("options.visualizer-types.none")
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
    isSettings: true
    defaultValue: Settings.getDefaultValue("audio.visualizerType")
    onSelected: key => Settings.data.audio.visualizerType = key
  }

  NComboBox {
    label: I18n.tr("settings.audio.media.frame-rate.label")
    description: I18n.tr("settings.audio.media.frame-rate.description")
    model: [
      {
        "key": "30",
        "name": I18n.tr("options.frame-rates.fps", {
                          "fps": "30"
                        })
      },
      {
        "key": "60",
        "name": I18n.tr("options.frame-rates.fps", {
                          "fps": "60"
                        })
      },
      {
        "key": "100",
        "name": I18n.tr("options.frame-rates.fps", {
                          "fps": "100"
                        })
      },
      {
        "key": "120",
        "name": I18n.tr("options.frame-rates.fps", {
                          "fps": "120"
                        })
      },
      {
        "key": "144",
        "name": I18n.tr("options.frame-rates.fps", {
                          "fps": "144"
                        })
      },
      {
        "key": "165",
        "name": I18n.tr("options.frame-rates.fps", {
                          "fps": "165"
                        })
      },
      {
        "key": "240",
        "name": I18n.tr("options.frame-rates.fps", {
                          "fps": "240"
                        })
      }
    ]
    currentKey: Settings.data.audio.cavaFrameRate
    isSettings: true
    defaultValue: Settings.getDefaultValue("audio.cavaFrameRate")
    onSelected: key => Settings.data.audio.cavaFrameRate = key
  }
}
