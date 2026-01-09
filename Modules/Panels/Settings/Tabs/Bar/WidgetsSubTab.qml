import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property var availableWidgets
  property var addWidgetToSection
  property var removeWidgetFromSection
  property var reorderWidgetInSection
  property var updateWidgetSettingsInSection
  property var moveWidgetBetweenSections

  signal openPluginSettings(var manifest)

  NText {
    text: I18n.tr("panels.bar.widgets-desc")
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }
  // Left Section
  NSectionEditor {
    sectionName: "Left"
    sectionId: "left"
    settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
    widgetRegistry: BarWidgetRegistry
    widgetModel: Settings.data.bar.widgets.left
    availableWidgets: root.availableWidgets
    onAddWidget: (widgetId, section) => root.addWidgetToSection(widgetId, section)
    onRemoveWidget: (section, index) => root.removeWidgetFromSection(section, index)
    onReorderWidget: (section, fromIndex, toIndex) => root.reorderWidgetInSection(section, fromIndex, toIndex)
    onUpdateWidgetSettings: (section, index, settings) => root.updateWidgetSettingsInSection(section, index, settings)
    onMoveWidget: (fromSection, index, toSection) => root.moveWidgetBetweenSections(fromSection, index, toSection)
    onOpenPluginSettingsRequested: manifest => root.openPluginSettings(manifest)
  }

  // Center Section
  NSectionEditor {
    sectionName: "Center"
    sectionId: "center"
    settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
    widgetRegistry: BarWidgetRegistry
    widgetModel: Settings.data.bar.widgets.center
    availableWidgets: root.availableWidgets
    onAddWidget: (widgetId, section) => root.addWidgetToSection(widgetId, section)
    onRemoveWidget: (section, index) => root.removeWidgetFromSection(section, index)
    onReorderWidget: (section, fromIndex, toIndex) => root.reorderWidgetInSection(section, fromIndex, toIndex)
    onUpdateWidgetSettings: (section, index, settings) => root.updateWidgetSettingsInSection(section, index, settings)
    onMoveWidget: (fromSection, index, toSection) => root.moveWidgetBetweenSections(fromSection, index, toSection)
    onOpenPluginSettingsRequested: manifest => root.openPluginSettings(manifest)
  }

  // Right Section
  NSectionEditor {
    sectionName: "Right"
    sectionId: "right"
    settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
    widgetRegistry: BarWidgetRegistry
    widgetModel: Settings.data.bar.widgets.right
    availableWidgets: root.availableWidgets
    onAddWidget: (widgetId, section) => root.addWidgetToSection(widgetId, section)
    onRemoveWidget: (section, index) => root.removeWidgetFromSection(section, index)
    onReorderWidget: (section, fromIndex, toIndex) => root.reorderWidgetInSection(section, fromIndex, toIndex)
    onUpdateWidgetSettings: (section, index, settings) => root.updateWidgetSettingsInSection(section, index, settings)
    onMoveWidget: (fromSection, index, toSection) => root.moveWidgetBetweenSections(fromSection, index, toSection)
    onOpenPluginSettingsRequested: manifest => root.openPluginSettings(manifest)
  }
}
