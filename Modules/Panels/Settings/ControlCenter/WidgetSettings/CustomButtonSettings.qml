import QtQml.Models
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM
  Layout.preferredWidth: Math.round(600 * Style.uiScaleRatio)
  implicitWidth: Layout.preferredWidth

  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  QtObject {
    id: _settings

    property string icon: (widgetData && widgetData.icon !== undefined) ? widgetData.icon : (widgetMetadata && widgetMetadata.icon ? widgetMetadata.icon : "")
    property string onClicked: (widgetData && widgetData.onClicked !== undefined) ? widgetData.onClicked : (widgetMetadata && widgetMetadata.onClicked ? widgetMetadata.onClicked : "")
    property string onRightClicked: (widgetData && widgetData.onRightClicked !== undefined) ? widgetData.onRightClicked : (widgetMetadata && widgetMetadata.onRightClicked ? widgetMetadata.onRightClicked : "")
    property string onMiddleClicked: (widgetData && widgetData.onMiddleClicked !== undefined) ? widgetData.onMiddleClicked : (widgetMetadata && widgetMetadata.onMiddleClicked ? widgetMetadata.onMiddleClicked : "")
    property ListModel _stateChecksListModel: ListModel {}
    property string stateChecksJson: "[]"
    property string generalTooltipText: (widgetData && widgetData.generalTooltipText !== undefined) ? widgetData.generalTooltipText : (widgetMetadata && widgetMetadata.generalTooltipText ? widgetMetadata.generalTooltipText : "Custom Button")
    property bool enableOnStateLogic: (widgetData && widgetData.enableOnStateLogic !== undefined) ? widgetData.enableOnStateLogic : (widgetMetadata && widgetMetadata.enableOnStateLogic !== undefined ? widgetMetadata.enableOnStateLogic : false)

    function populateStateChecks() {
      try {
        var initialChecks = JSON.parse(stateChecksJson);
        if (initialChecks && Array.isArray(initialChecks)) {
          for (var i = 0; i < initialChecks.length; i++) {
            var item = initialChecks[i];
            if (item && typeof item === "object") {
              _settings._stateChecksListModel.append({
                                                       "command": item.command || "",
                                                       "icon": item.icon || ""
                                                     });
            } else {
              Logger.w("CustomButtonSettings", "Invalid stateChecks entry at index " + i + ":", item);
            }
          }
        }
      } catch (e) {
        Logger.e("CustomButtonSettings", "Failed to parse stateChecksJson:", e.message);
      }
    }

    Component.onCompleted: {
      stateChecksJson = (widgetData && widgetData.stateChecksJson !== undefined) ? widgetData.stateChecksJson : (widgetMetadata && widgetMetadata.stateChecksJson ? widgetMetadata.stateChecksJson : "[]");
      Qt.callLater(populateStateChecks);
    }
  }

  function saveSettings() {
    var savedStateChecksArray = [];
    for (var i = 0; i < _settings._stateChecksListModel.count; i++) {
      savedStateChecksArray.push(_settings._stateChecksListModel.get(i));
    }
    _settings.stateChecksJson = JSON.stringify(savedStateChecksArray);

    return {
      "id": widgetData.id,
      "icon": _settings.icon,
      "onClicked": _settings.onClicked,
      "onRightClicked": _settings.onRightClicked,
      "onMiddleClicked": _settings.onMiddleClicked,
      "stateChecksJson": _settings.stateChecksJson,
      "generalTooltipText": _settings.generalTooltipText,
      "enableOnStateLogic": _settings.enableOnStateLogic
    };
  }

  RowLayout {
    spacing: Style?.marginM ?? 8

    NLabel {
      label: I18n.tr("common.icon")
      description: I18n.tr("bar.custom-button.icon-description")
    }

    NIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: _settings.icon || (widgetMetadata && widgetMetadata.icon ? widgetMetadata.icon : "")
      pointSize: Style?.fontSizeXL ?? 24
      visible: (_settings.icon || (widgetMetadata && widgetMetadata.icon ? widgetMetadata.icon : "")) !== ""
    }

    NButton {
      text: I18n.tr("common.browse")
      onClicked: iconPicker.open()
    }
  }

  NIconPicker {
    id: iconPicker
    initialIcon: _settings.icon
    onIconSelected: function (iconName) {
      _settings.icon = iconName;
      settingsChanged(saveSettings());
    }
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("panels.control-center.shortcuts-custom-button-general-tooltip-text-label")
    description: I18n.tr("panels.control-center.shortcuts-custom-button-general-tooltip-text-description")
    placeholderText: I18n.tr("placeholders.enter-tooltip")
    text: _settings.generalTooltipText
    onEditingFinished: {
      _settings.generalTooltipText = text;
      settingsChanged(saveSettings());
    }
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("panels.control-center.shortcuts-custom-button-on-clicked-label")
    description: I18n.tr("bar.custom-button.left-click-description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onClicked
    onEditingFinished: {
      _settings.onClicked = text;
      settingsChanged(saveSettings());
    }
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("panels.control-center.shortcuts-custom-button-on-right-clicked-label")
    description: I18n.tr("bar.custom-button.right-click-description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onRightClicked
    onEditingFinished: {
      _settings.onRightClicked = text;
      settingsChanged(saveSettings());
    }
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("panels.control-center.shortcuts-custom-button-on-middle-clicked-label")
    description: I18n.tr("bar.custom-button.middle-click-description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onMiddleClicked
    onEditingFinished: {
      _settings.onMiddleClicked = text;
      settingsChanged(saveSettings());
    }
  }

  NDivider {}

  NToggle {
    id: enableOnStateLogicToggle
    Layout.fillWidth: true
    label: I18n.tr("panels.control-center.shortcuts-custom-button-enable-on-state-logic-label")
    description: I18n.tr("panels.control-center.shortcuts-custom-button-enable-on-state-logic-description")
    checked: _settings.enableOnStateLogic
    onToggled: checked => {
                 _settings.enableOnStateLogic = checked;
                 settingsChanged(saveSettings());
               }
  }

  ColumnLayout {
    Layout.fillWidth: true
    visible: _settings.enableOnStateLogic
    spacing: (Style?.marginM ?? 8) * 2

    NLabel {
      label: I18n.tr("panels.control-center.shortcuts-custom-button-state-checks-label")
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
            placeholderText: I18n.tr("panels.control-center.shortcuts-custom-button-state-checks-command")
            text: model.command
            onEditingFinished: {
              _settings._stateChecksListModel.set(currentIndex, {
                                                    "command": text,
                                                    "icon": model.icon
                                                  });
              settingsChanged(saveSettings());
            }
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
              tooltipText: I18n.tr("common.browse")
              baseSize: Style?.buttonSizeS ?? 24
              onClicked: iconPickerDelegate.open()
            }

            NIconButton {
              icon: "close"
              tooltipText: I18n.tr("panels.control-center.shortcuts-custom-button-state-checks-remove")
              baseSize: Style?.buttonSizeS ?? 24
              colorBorder: Qt.alpha(Color.mOutline, Style.opacityLight)
              colorBg: Color.mError
              colorFg: Color.mOnError
              colorBgHover: Qt.alpha(Color.mError, Style.opacityMedium)
              colorFgHover: Color.mOnError
              onClicked: {
                _settings._stateChecksListModel.remove(currentIndex);
                settingsChanged(saveSettings());
              }
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
                                                });
            settingsChanged(saveSettings());
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
        text: I18n.tr("panels.control-center.shortcuts-custom-button-state-checks-add")
        onClicked: {
          _settings._stateChecksListModel.append({
                                                   "command": "",
                                                   "icon": ""
                                                 });
          settingsChanged(saveSettings());
        }
      }

      Item {
        Layout.fillWidth: true
      }
    }
  }

  NDivider {}
}
