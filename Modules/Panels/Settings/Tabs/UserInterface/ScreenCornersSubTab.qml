import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  function screenLabel(screen) {
    if (!screen) {
      return I18n.tr("common.unknown");
    }
    return screen.name || I18n.tr("common.unknown");
  }

  NToggle {
    label: I18n.tr("panels.general.screen-corners-show-corners-label")
    description: I18n.tr("panels.general.screen-corners-show-corners-description")
    checked: Settings.data.general.showScreenCorners
    defaultValue: Settings.getDefaultValue("general.showScreenCorners")
    onToggled: checked => Settings.data.general.showScreenCorners = checked
  }

  NToggle {
    label: I18n.tr("panels.general.screen-corners-solid-black-label")
    description: I18n.tr("panels.general.screen-corners-solid-black-description")
    checked: Settings.data.general.forceBlackScreenCorners
    defaultValue: Settings.getDefaultValue("general.forceBlackScreenCorners")
    onToggled: checked => Settings.data.general.forceBlackScreenCorners = checked
  }

  ColumnLayout {
    spacing: Style.marginXXS
    Layout.fillWidth: true

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("panels.general.screen-corners-radius-label")
      description: I18n.tr("panels.general.screen-corners-radius-description")
      from: 0
      to: 2
      stepSize: 0.01
      showReset: true
      value: Settings.data.general.screenRadiusRatio
      defaultValue: Settings.getDefaultValue("general.screenRadiusRatio")
      onMoved: value => Settings.data.general.screenRadiusRatio = value
      text: Math.floor(Settings.data.general.screenRadiusRatio * 100) + "%"
    }
  }

  NDivider {
    Layout.fillWidth: trues
  }

  NHeader {
    label: I18n.tr("panels.general.screen-corners-hot-corners-header")
  }

  Repeater {
    model: Quickshell.screens || []
    delegate: NBox {
      Layout.fillWidth: true
      radius: Style.radiusM
      color: Color.mSurface
      implicitHeight: content.implicitHeight + Style.marginL * 2

      property string screenName: modelData.name || ""

      ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginS

        NToggle {
          Layout.fillWidth: true
          label: root.screenLabel(modelData)
          description: {
            const compositorScale = CompositorService.getDisplayScale(modelData.name);
            const monitorDesc = I18n.tr("system.monitor-description", {
                                        "model": modelData.model,
                                        "width": modelData.width * compositorScale,
                                        "height": modelData.height * compositorScale,
                                        "scale": compositorScale
                                      });
            return monitorDesc + "\n" + I18n.tr("panels.general.screen-corners-hot-corner-monitor-toggle-description");
          }
          checked: Settings.getHotCornerMonitorEnabledForScreen(screenName)
          onToggled: checked => Settings.setHotCornerMonitorEnabledForScreen(screenName, checked)
        }

        NDivider {
          Layout.fillWidth: true
          visible: Settings.getHotCornerMonitorEnabledForScreen(screenName)
        }

        ColumnLayout {
          spacing: Style.marginS
          Layout.fillWidth: true
          visible: Settings.getHotCornerMonitorEnabledForScreen(modelData.name)

          Repeater {
            model: [
              {
                "key": "TopLeft",
                "icon": "arrow-up-left",
                "labelKey": "positions.top-left"
              },
              {
                "key": "TopRight",
                "icon": "arrow-up-right",
                "labelKey": "positions.top-right"
              },
              {
                "key": "BottomLeft",
                "icon": "arrow-down-left",
                "labelKey": "positions.bottom-left"
              },
              {
                "key": "BottomRight",
                "icon": "arrow-down-right",
                "labelKey": "positions.bottom-right"
              }
            ]
            delegate: RowLayout {
              spacing: Style.marginM
              Layout.fillWidth: true

              RowLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: 200 * Style.uiScaleRatio
                spacing: Style.marginS

                NIcon {
                  icon: modelData.icon
                  pointSize: Style.fontSizeL
                  color: Color.mOnSurface
                  Layout.alignment: Qt.AlignVCenter
                  Layout.preferredWidth: Style.fontSizeL * 2 * Style.uiScaleRatio
                }

                NText {
                  text: I18n.tr(modelData.labelKey)
                  pointSize: Style.fontSizeL
                  font.weight: Style.fontWeightSemiBold
                  Layout.alignment: Qt.AlignVCenter
                  Layout.fillWidth: true
                }
              }

              NTextInput {
                Layout.fillWidth: true
                label: ""
                description: ""
                placeholderText: I18n.tr("panels.general.screen-corners-hot-corner-command-placeholder")
                text: Settings.getHotCornerCommandForScreen(screenName, modelData.key)
                fontFamily: Settings.data.ui.fontFixed
                enabled: Settings.getHotCornerEnabledForScreen(screenName, modelData.key)
                opacity: Settings.getHotCornerEnabledForScreen(screenName, modelData.key) ? 1 : 0
                onAccepted: Settings.setHotCornerCommandForScreen(screenName, modelData.key, text)
                onEditingFinished: Settings.setHotCornerCommandForScreen(screenName, modelData.key, text)
              }

              NToggle {
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignVCenter
                label: ""
                description: ""
                checked: Settings.getHotCornerEnabledForScreen(screenName, modelData.key)
                onToggled: checked => Settings.setHotCornerEnabledForScreen(screenName, modelData.key, checked)
              }
            }
          }
        }
      }
    }
  }
}
