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
  property var rootSettings: null

  signal settingsChanged(var settings)

  QtObject {
    id: _settings

    property string icon: (widgetData && widgetData.icon !== undefined) ? widgetData.icon : (widgetMetadata && widgetMetadata.icon ? widgetMetadata.icon : "")
    property string onClicked: (widgetData && widgetData.onClicked !== undefined) ? widgetData.onClicked : (widgetMetadata && widgetMetadata.onClicked ? widgetMetadata.onClicked : "")
    property string onRightClicked: (widgetData && widgetData.onRightClicked !== undefined) ? widgetData.onRightClicked : (widgetMetadata && widgetMetadata.onRightClicked ? widgetMetadata.onRightClicked : "")
    property string onMiddleClicked: (widgetData && widgetData.onMiddleClicked !== undefined) ? widgetData.onMiddleClicked : (widgetMetadata && widgetMetadata.onMiddleClicked ? widgetMetadata.onMiddleClicked : "")
    property ListModel _stateChecksListModel: ListModel {}
    property string stateChecksJson: "[]"
    property string generalTooltipText: (widgetData && widgetData.generalTooltipText !== undefined) ? widgetData.generalTooltipText : (widgetMetadata && widgetMetadata.generalTooltipText ? widgetMetadata.generalTooltipText : "")
    property bool enableOnStateLogic: (widgetData && widgetData.enableOnStateLogic !== undefined) ? widgetData.enableOnStateLogic : (widgetMetadata && widgetMetadata.enableOnStateLogic !== undefined ? widgetMetadata.enableOnStateLogic : false)
    property bool showExecTooltip: (widgetData && widgetData.showExecTooltip !== undefined) ? widgetData.showExecTooltip : (widgetMetadata && widgetMetadata.showExecTooltip !== undefined ? widgetMetadata.showExecTooltip : true)

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
      root.rootSettings = _settings;
      stateChecksJson = (widgetData && widgetData.stateChecksJson !== undefined) ? widgetData.stateChecksJson : (widgetMetadata && widgetMetadata.stateChecksJson ? widgetMetadata.stateChecksJson : "[]");
      Qt.callLater(populateStateChecks);
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
        "enableOnStateLogic": _settings.enableOnStateLogic,
        "showExecTooltip": _settings.showExecTooltip
      };
    }
  }

  function saveSettings() {
    return _settings.saveSettings();
  }

  function updateStateCheck(index, command, icon) {
    _settings._stateChecksListModel.set(index, {
                                          "command": command,
                                          "icon": icon
                                        });
    _settings.saveSettings();
  }

  function removeStateCheck(index) {
    _settings._stateChecksListModel.remove(index);
    _settings.saveSettings();
  }

  function addStateCheck() {
    _settings._stateChecksListModel.append({
                                             "command": "",
                                             "icon": ""
                                           });
    _settings.saveSettings();
  }

  RowLayout {
    spacing: Style?.marginM ?? 8

    NLabel {
      label: I18n.tr("common.icon")
      description: I18n.tr("panels.control-center.shortcuts-custom-button-icon-description")
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
      saveSettings();
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
      saveSettings();
    }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.control-center.shortcuts-custom-button-show-exec-tooltip-label")
    description: I18n.tr("panels.control-center.shortcuts-custom-button-show-exec-tooltip-description")
    checked: _settings.showExecTooltip
    onToggled: checked => {
                 _settings.showExecTooltip = checked;
                 saveSettings();
               }
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("panels.control-center.shortcuts-custom-button-on-clicked-label")
    description: I18n.tr("panels.control-center.shortcuts-custom-button-on-clicked-description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onClicked
    onEditingFinished: {
      _settings.onClicked = text;
      saveSettings();
    }
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("panels.control-center.shortcuts-custom-button-on-right-clicked-label")
    description: I18n.tr("panels.control-center.shortcuts-custom-button-on-right-clicked-description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onRightClicked
    onEditingFinished: {
      _settings.onRightClicked = text;
      saveSettings();
    }
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("panels.control-center.shortcuts-custom-button-on-middle-clicked-label")
    description: I18n.tr("panels.control-center.shortcuts-custom-button-on-middle-clicked-description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onMiddleClicked
    onEditingFinished: {
      _settings.onMiddleClicked = text;
      saveSettings();
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
                 saveSettings();
               }
  }

  ColumnLayout {
    Layout.fillWidth: true
    visible: root.rootSettings && root.rootSettings.enableOnStateLogic
    spacing: Style?.marginM ?? 8

    NLabel {
      label: I18n.tr("panels.control-center.shortcuts-custom-button-state-checks-label")
    }

    Repeater {
      model: root.rootSettings ? root.rootSettings._stateChecksListModel : null
      delegate: Item {
        property int currentIndex: index

        implicitHeight: contentRow.implicitHeight
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
              updateStateCheck(currentIndex, text, model.icon);
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
                removeStateCheck(currentIndex);
              }
            }
          }
        }

        NIconPicker {
          id: iconPickerDelegate
          initialIcon: model.icon
          onIconSelected: function (iconName) {
            updateStateCheck(currentIndex, model.command, iconName);
          }
        }
      }
    }

    Item {
      Layout.fillWidth: true
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style?.marginM ?? 8

      NButton {
        text: I18n.tr("panels.control-center.shortcuts-custom-button-state-checks-add")
        onClicked: addStateCheck()
      }
    }
  }
}
