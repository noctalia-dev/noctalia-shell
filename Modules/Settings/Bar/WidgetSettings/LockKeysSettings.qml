import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property string valueIndicatorStyle: widgetData.indicatorStyle !== undefined ? widgetData.indicatorStyle : widgetMetadata.indicatorStyle
  property bool valueShowCapsLock: widgetData.showCapsLock !== undefined ? widgetData.showCapsLock : widgetMetadata.showCapsLock
  property bool valueShowNumLock: widgetData.showNumLock !== undefined ? widgetData.showNumLock : widgetMetadata.showNumLock
  property bool valueShowScrollLock: widgetData.showScrollLock !== undefined ? widgetData.showScrollLock : widgetMetadata.showScrollLock

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.indicatorStyle = valueIndicatorStyle
    settings.showCapsLock = valueShowCapsLock
    settings.showNumLock = valueShowNumLock
    settings.showScrollLock = valueShowScrollLock
    return settings
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.lock-keys.indicator-style.label")
    description: I18n.tr("bar.widget-settings.lock-keys.indicator-style.description")
    model: [{
        "key": "large",
        "name": I18n.tr("bar.widget-settings.lock-keys.indicator-style.large")
      }, {
        "key": "small",
        "name": I18n.tr("bar.widget-settings.lock-keys.indicator-style.small")
      }, {
        "key": "square",
        "name": I18n.tr("bar.widget-settings.lock-keys.indicator-style.square")
      }, {
        "key": "square-round",
        "name": I18n.tr("bar.widget-settings.lock-keys.indicator-style.square-round")
      }, {
        "key": "circle",
        "name": I18n.tr("bar.widget-settings.lock-keys.indicator-style.circle")
      }, {
        "key": "circle-dash",
        "name": I18n.tr("bar.widget-settings.lock-keys.indicator-style.circle-dash")
      }, {
        "key": "circle-dot",
        "name": I18n.tr("bar.widget-settings.lock-keys.indicator-style.circle-dot")
      }, {
        "key": "hex",
        "name": I18n.tr("bar.widget-settings.lock-keys.indicator-style.hex")
      }]
    currentKey: valueIndicatorStyle
    onSelected: key => valueIndicatorStyle = key
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.lock-keys.show-caps-lock.label")
    description: I18n.tr("bar.widget-settings.lock-keys.show-caps-lock.description")
    checked: valueShowCapsLock
    onToggled: checked => valueShowCapsLock = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.lock-keys.show-num-lock.label")
    description: I18n.tr("bar.widget-settings.lock-keys.show-num-lock.description")
    checked: valueShowNumLock
    onToggled: checked => valueShowNumLock = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.lock-keys.show-scroll-lock.label")
    description: I18n.tr("bar.widget-settings.lock-keys.show-scroll-lock.description")
    checked: valueShowScrollLock
    onToggled: checked => valueShowScrollLock = checked
  }
}
