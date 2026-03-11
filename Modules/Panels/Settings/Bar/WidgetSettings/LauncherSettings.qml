import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var screen: null
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  // Local state
  property string valueIcon: widgetData.icon !== undefined ? widgetData.icon : widgetMetadata.icon
  property bool valueUseDistroLogo: widgetData.useDistroLogo !== undefined ? widgetData.useDistroLogo : widgetMetadata.useDistroLogo
  property string valueCustomIconPath: widgetData.customIconPath !== undefined ? widgetData.customIconPath : widgetMetadata.customIconPath
  property bool valueEnableColorization: widgetData.enableColorization !== undefined ? widgetData.enableColorization : widgetMetadata.enableColorization
  property string valueColorizeSystemIcon: widgetData.colorizeSystemIcon !== undefined ? widgetData.colorizeSystemIcon : widgetMetadata.colorizeSystemIcon

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.icon = valueIcon;
    settings.useDistroLogo = valueUseDistroLogo;
    settings.customIconPath = valueCustomIconPath;
    settings.enableColorization = valueEnableColorization;
    settings.colorizeSystemIcon = valueColorizeSystemIcon;
    settingsChanged(settings);
  }

  NToggle {
    label: I18n.tr("bar.control-center.use-distro-logo-label")
    description: I18n.tr("bar.control-center.use-distro-logo-description")
    checked: valueUseDistroLogo
    onToggled: checked => {
                 valueUseDistroLogo = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.useDistroLogo
  }

  NToggle {
    label: I18n.tr("bar.custom-button.enable-colorization-label")
    description: I18n.tr("bar.control-center.enable-colorization-description")
    checked: valueEnableColorization
    onToggled: checked => {
                 valueEnableColorization = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.enableColorization
  }

  NColorChoice {
    visible: valueEnableColorization
    label: I18n.tr("common.select-icon-color")
    description: I18n.tr("bar.control-center.color-selection-description")
    currentKey: valueColorizeSystemIcon
    onSelected: function (key) {
      valueColorizeSystemIcon = key;
      saveSettings();
    }
    defaultValue: widgetMetadata.colorizeSystemIcon
  }

  RowLayout {
    spacing: Style.marginM

    NLabel {
      label: I18n.tr("common.icon")
      description: I18n.tr("bar.control-center.icon-description")
    }

    NImageRounded {
      Layout.preferredWidth: Style.fontSizeXL * 2
      Layout.preferredHeight: Style.fontSizeXL * 2
      Layout.alignment: Qt.AlignVCenter
      radius: Math.min(Style.radiusL, Layout.preferredWidth / 2)
      imagePath: valueCustomIconPath
      visible: valueCustomIconPath !== "" && !valueUseDistroLogo
    }

    NIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: valueIcon
      pointSize: Style.fontSizeXXL * 1.5
      visible: valueIcon !== "" && valueCustomIconPath === "" && !valueUseDistroLogo
    }
  }

  RowLayout {
    spacing: Style.marginM
    NButton {
      enabled: !valueUseDistroLogo
      text: I18n.tr("bar.control-center.browse-library")
      onClicked: iconPicker.open()
    }

    NButton {
      enabled: !valueUseDistroLogo
      text: I18n.tr("bar.control-center.browse-file")
      onClicked: imagePicker.openFilePicker()
    }
  }

  NIconPicker {
    id: iconPicker
    initialIcon: valueIcon
    onIconSelected: iconName => {
                      valueIcon = iconName;
                      valueCustomIconPath = "";
                      saveSettings();
                    }
  }

  NFilePicker {
    id: imagePicker
    title: I18n.tr("bar.control-center.select-custom-icon")
    selectionMode: "files"
    nameFilters: ImageCacheService.basicImageFilters.concat(["*.svg"])
    initialPath: Quickshell.env("HOME")
    onAccepted: paths => {
                  if (paths.length > 0) {
                    valueCustomIconPath = paths[0];
                    saveSettings();
                  }
                }
  }
}
