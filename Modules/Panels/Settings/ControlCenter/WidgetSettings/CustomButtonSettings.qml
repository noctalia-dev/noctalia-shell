import QtQuick
import QtQuick.Layouts
import QtQml.Models
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var widgetData: null
  property var widgetMetadata: null

  QtObject {
    id: _settings

    property string icon: (widgetData && widgetData.icon !== undefined) ? widgetData.icon : widgetMetadata.icon
    property string onClicked: (widgetData && widgetData.onClicked !== undefined) ? widgetData.onClicked : widgetMetadata.onClicked
    property string onRightClicked: (widgetData && widgetData.onRightClicked !== undefined) ? widgetData.onRightClicked : widgetMetadata.onRightClicked
    property string onMiddleClicked: (widgetData && widgetData.onMiddleClicked !== undefined) ? widgetData.onMiddleClicked : widgetMetadata.onMiddleClicked
    property ListModel _stateChecksListModel: ListModel {}
    property string stateChecksJson: "[]"
    property string generalTooltipText: (widgetData && widgetData.generalTooltipText !== undefined) ? widgetData.generalTooltipText : widgetMetadata.generalTooltipText
    property bool enableOnStateLogic: (widgetData && widgetData.enableOnStateLogic !== undefined) ? widgetData.enableOnStateLogic : widgetMetadata.enableOnStateLogic

    Component.onCompleted: {
      stateChecksJson = (widgetData && widgetData.stateChecksJson !== undefined) ? widgetData.stateChecksJson : widgetMetadata.stateChecksJson || "[]"
      try {
        var initialChecks = JSON.parse(stateChecksJson)
        if (initialChecks && Array.isArray(initialChecks)) {
          for (var i = 0; i < initialChecks.length; i++) {
            var item = initialChecks[i]
            if (item && typeof item === "object") {
              _settings._stateChecksListModel.append({
                                                       "command": item.command || "",
                                                       "icon": item.icon || ""
                                                     })
            } else {
              console.warn("⚠️ Invalid stateChecks entry at index " + i + ":", item)
            }
          }
        }
      } catch (e) {
        console.error("CustomButtonSettings: Failed to parse stateChecksJson:", e.message)
      }
    }
  }

  function saveSettings() {
    var savedStateChecksArray = []
    for (var i = 0; i < _settings._stateChecksListModel.count; i++) {
      savedStateChecksArray.push(_settings._stateChecksListModel.get(i))
    }
    _settings.stateChecksJson = JSON.stringify(savedStateChecksArray)

    return {
      "id": widgetData.id,
      "icon": _settings.icon,
      "onClicked": _settings.onClicked,
      "onRightClicked": _settings.onRightClicked,
      "onMiddleClicked": _settings.onMiddleClicked,
      "stateChecksJson": _settings.stateChecksJson,
      "generalTooltipText": _settings.generalTooltipText,
      "enableOnStateLogic": _settings.enableOnStateLogic
    }
  }

  RowLayout {
    spacing: Style?.marginM ?? 8

    NLabel {
      label: I18n.tr("settings.control-center.shortcuts.custom-button.icon.label")
      description: I18n.tr("settings.control-center.shortcuts.custom-button.icon.description")
    }

    NIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: _settings.icon || widgetMetadata.icon
      pointSize: Style?.fontSizeXL ?? 24
      visible: (_settings.icon || widgetMetadata.icon) !== ""
    }

    NButton {
      text: I18n.tr("settings.control-center.shortcuts.custom-button.browse")
      onClicked: iconPicker.open()
    }
  }

  NIconPicker {
    id: iconPicker
    initialIcon: _settings.icon
    onIconSelected: function (iconName) {
      _settings.icon = iconName
    }
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.general-tooltip-text.label")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.general-tooltip-text.description")
    placeholderText: I18n.tr("placeholders.enter-tooltip")
    text: _settings.generalTooltipText
    onTextChanged: _settings.generalTooltipText = text
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.on-clicked.label")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.on-clicked.description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onClicked
    onTextChanged: _settings.onClicked = text
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.on-right-clicked.label")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.on-right-clicked.description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onRightClicked
    onTextChanged: _settings.onRightClicked = text
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.on-middle-clicked.label")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.on-middle-clicked.description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onMiddleClicked
    onTextChanged: _settings.onMiddleClicked = text
  }

  NDivider {}

  NToggle {
    id: enableOnStateLogicToggle
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.enable-on-state-logic.label")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.enable-on-state-logic.description")
    checked: _settings.enableOnStateLogic
    onToggled: checked => _settings.enableOnStateLogic = checked
  }

  ColumnLayout {
    Layout.fillWidth: true
    visible: _settings.enableOnStateLogic
    spacing: (Style?.marginM ?? 8) * 2

    NLabel {
      label: I18n.tr("settings.control-center.shortcuts.custom-button.state-checks.label")
    }

    Repeater {
      model: _settings._stateChecksListModel
      delegate: Item {
        property int currentIndex: index

        implicitHeight: contentRow.implicitHeight + ((divider.visible) ? divider.height : 0)
        Layout.fillWidth: true

        RowLayout {
          id: contentRow
          anchors.fill: parent
          spacing: Style?.marginM ?? 8

          NTextInput {
            Layout.fillWidth: true
            placeholderText: I18n.tr("settings.control-center.shortcuts.custom-button.state-checks.command")
            text: model.command
            onEditingFinished: _settings._stateChecksListModel.set(currentIndex, {
                                                                     "command": text,
                                                                     "icon": model.icon
                                                                   })
          }

          RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: Style?.marginS ?? 4

            NIcon {
              icon: model.icon
              pointSize: Style?.fontSizeL ?? 20
              visible: model.icon !== undefined && model.icon !== ""
            }

            NIconButton {
              icon: "folder"
              tooltipText: I18n.tr("settings.control-center.shortcuts.custom-button.state-checks.browse-icon")
              baseSize: Style?.buttonSizeS ?? 24
              onClicked: iconPickerDelegate.open()
            }

            NIconButton {
              icon: "close"
              tooltipText: I18n.tr("settings.control-center.shortcuts.custom-button.state-checks.remove")
              baseSize: Style?.buttonSizeS ?? 24
              colorBorder: Qt.alpha(Color.mOutline, Style.opacityLight)
              colorBg: Color.mError
              colorFg: Color.mOnError
              colorBgHover: Qt.alpha(Color.mError, Style.opacityMedium)
              colorFgHover: Color.mOnError
              onClicked: _settings._stateChecksListModel.remove(currentIndex)
            }
          }
        }

        NIconPicker {
          id: iconPickerDelegate
          initialIcon: model.icon
          onIconSelected: function (iconName) {
            _settings._stateChecksListModel.set(currentIndex, {
                                                  "command": model.command,
                                                  "icon": iconName
                                                })
          }
        }

        NDivider {
          id: divider
          anchors.bottom: parent.bottom
          visible: index < _settings._stateChecksListModel.count - 1 // Only show divider if not the last item
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style?.marginM ?? 8

      NButton {
        text: I18n.tr("settings.control-center.shortcuts.custom-button.state-checks.add")
        onClicked: _settings._stateChecksListModel.append({
                                                            "command": "",
                                                            "icon": ""
                                                          })
      }

      Item {
        Layout.fillWidth: true
      }
    }
  }

  NDivider {}
}
