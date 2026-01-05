import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property var screen

  NHeader {
    label: I18n.tr("settings.wallpaper.look-feel.section.label")
  }

  NComboBox {
    label: I18n.tr("settings.wallpaper.look-feel.fill-mode.label")
    description: I18n.tr("settings.wallpaper.look-feel.fill-mode.description")
    model: WallpaperService.fillModeModel
    currentKey: Settings.data.wallpaper.fillMode
    onSelected: key => Settings.data.wallpaper.fillMode = key
    isSettings: true
    defaultValue: Settings.getDefaultValue("wallpaper.fillMode")
  }

  RowLayout {
    NLabel {
      label: I18n.tr("settings.wallpaper.look-feel.fill-color.label")
      description: I18n.tr("settings.wallpaper.look-feel.fill-color.description")
      Layout.alignment: Qt.AlignTop
    }

    NColorPicker {
      screen: root.screen
      selectedColor: Settings.data.wallpaper.fillColor
      onColorSelected: color => Settings.data.wallpaper.fillColor = color
    }
  }

  NComboBox {
    label: I18n.tr("settings.wallpaper.look-feel.transition-type.label")
    description: I18n.tr("settings.wallpaper.look-feel.transition-type.description")
    model: WallpaperService.transitionsModel
    currentKey: Settings.data.wallpaper.transitionType
    onSelected: key => Settings.data.wallpaper.transitionType = key
    isSettings: true
    defaultValue: Settings.getDefaultValue("wallpaper.transitionType")
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("settings.wallpaper.look-feel.transition-duration.label")
    description: I18n.tr("settings.wallpaper.look-feel.transition-duration.description")
    from: 500
    to: 10000
    stepSize: 100
    value: Settings.data.wallpaper.transitionDuration
    onMoved: value => Settings.data.wallpaper.transitionDuration = value
    text: (Settings.data.wallpaper.transitionDuration / 1000).toFixed(1) + "s"
    isSettings: true
    defaultValue: Settings.getDefaultValue("wallpaper.transitionDuration")
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("settings.wallpaper.look-feel.edge-smoothness.label")
    description: I18n.tr("settings.wallpaper.look-feel.edge-smoothness.description")
    from: 0.0
    to: 1.0
    value: Settings.data.wallpaper.transitionEdgeSmoothness
    onMoved: value => Settings.data.wallpaper.transitionEdgeSmoothness = value
    text: Math.round(Settings.data.wallpaper.transitionEdgeSmoothness * 100) + "%"
    isSettings: true
    defaultValue: Settings.getDefaultValue("wallpaper.transitionEdgeSmoothness")
  }
}
