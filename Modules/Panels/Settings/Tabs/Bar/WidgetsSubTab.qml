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

  // This sub-tab edits the global default widget configuration (Settings.data.bar.widgets).
  // Per-screen widget overrides are edited in MonitorWidgetsConfig.qml (Monitors sub-tab).

  // determine bar orientation
  readonly property string barPosition: Settings.data.bar.position
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"

  function getSectionIcons() {
    return {
      "left": "arrow-bar-to-up",
      "center": "layout-distribute-horizontal",
      "right": "arrow-bar-to-down"
    };
  }

  NText {
    text: I18n.tr("panels.bar.widgets-desc")
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  // Left Section
  NSectionEditor {
    sectionName: root.barIsVertical ? I18n.tr("positions.top") : I18n.tr("positions.left")
    sectionId: "left"
    barIsVertical: root.barIsVertical
    settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
    widgetRegistry: BarWidgetRegistry
    widgetModel: Settings.data.bar.widgets.left
    sectionIcons: root.getSectionIcons()
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
    sectionName: I18n.tr("positions.center")
    sectionId: "center"
    barIsVertical: root.barIsVertical
    settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
    widgetRegistry: BarWidgetRegistry
    widgetModel: Settings.data.bar.widgets.center
    sectionIcons: root.getSectionIcons()
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
    sectionName: root.barIsVertical ? I18n.tr("positions.bottom") : I18n.tr("positions.right")
    sectionId: "right"
    barIsVertical: root.barIsVertical
    settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
    widgetRegistry: BarWidgetRegistry
    widgetModel: Settings.data.bar.widgets.right
    sectionIcons: root.getSectionIcons()
    availableWidgets: root.availableWidgets
    onAddWidget: (widgetId, section) => root.addWidgetToSection(widgetId, section)
    onRemoveWidget: (section, index) => root.removeWidgetFromSection(section, index)
    onReorderWidget: (section, fromIndex, toIndex) => root.reorderWidgetInSection(section, fromIndex, toIndex)
    onUpdateWidgetSettings: (section, index, settings) => root.updateWidgetSettingsInSection(section, index, settings)
    onMoveWidget: (fromSection, index, toSection) => root.moveWidgetBetweenSections(fromSection, index, toSection)
    onOpenPluginSettingsRequested: manifest => root.openPluginSettings(manifest)
  }
}
