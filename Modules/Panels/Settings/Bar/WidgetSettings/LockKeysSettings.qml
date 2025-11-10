import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property bool valueShowCapsLock: widgetData.showCapsLock !== undefined ? widgetData.showCapsLock : widgetMetadata.showCapsLock
  property bool valueShowNumLock: widgetData.showNumLock !== undefined ? widgetData.showNumLock : widgetMetadata.showNumLock
  property bool valueShowScrollLock: widgetData.showScrollLock !== undefined ? widgetData.showScrollLock : widgetMetadata.showScrollLock

  property string capsIcon: widgetData.capsLockIcon !== undefined ? widgetData.capsLockIcon : widgetMetadata.capsLockIcon
  property string numIcon: widgetData.numLockIcon !== undefined ? widgetData.numLockIcon : widgetMetadata.numLockIcon
  property string scrollIcon: widgetData.scrollLockIcon !== undefined ? widgetData.scrollLockIcon : widgetMetadata.scrollLockIcon

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.showCapsLock = valueShowCapsLock
    settings.showNumLock = valueShowNumLock
    settings.showScrollLock = valueShowScrollLock
    settings.capsLockIcon = capsIcon
    settings.numLockIcon = numIcon
    settings.scrollLockIcon = scrollIcon
    return settings
  }

  RowLayout {
    spacing: Style.marginM

    NToggle {
      label: I18n.tr("bar.widget-settings.lock-keys.show-caps-lock.label")
      description: I18n.tr("bar.widget-settings.lock-keys.show-caps-lock.description")
      checked: valueShowCapsLock
      onToggled: checked => valueShowCapsLock = checked
    }

    NIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: capsIcon
      pointSize: Style.fontSizeXL
      visible: capsIcon !== ""
    }

    NButton {
      text: I18n.tr("bar.widget-settings.lock-keys.browse")
      onClicked: capsPicker.open()
      enabled: valueShowCapsLock
    }
  }

  NIconPicker {
    id: capsPicker
    initialIcon: capsIcon
    query: "letter-c"
    onIconSelected: function (iconName) {
      capsIcon = iconName
    }
  }

  RowLayout {
    spacing: Style.marginM

    NToggle {
      label: I18n.tr("bar.widget-settings.lock-keys.show-num-lock.label")
      description: I18n.tr("bar.widget-settings.lock-keys.show-num-lock.description")
      checked: valueShowNumLock
      onToggled: checked => valueShowNumLock = checked
    }

    NIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: numIcon
      pointSize: Style.fontSizeXL
      visible: numIcon !== ""
    }

    NButton {
      text: I18n.tr("bar.widget-settings.lock-keys.browse")
      onClicked: numPicker.open()
      enabled: valueShowNumLock
    }
  }

  NIconPicker {
    id: numPicker
    initialIcon: numIcon
    query: "letter-n"
    onIconSelected: function (iconName) {
      numIcon = iconName
    }
  }

  RowLayout {
    spacing: Style.marginM

    NToggle {
      label: I18n.tr("bar.widget-settings.lock-keys.show-scroll-lock.label")
      description: I18n.tr("bar.widget-settings.lock-keys.show-scroll-lock.description")
      checked: valueShowScrollLock
      onToggled: checked => valueShowScrollLock = checked
    }

    NIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: scrollIcon
      pointSize: Style.fontSizeXL
      visible: scrollIcon !== ""
    }

    NButton {
      text: I18n.tr("bar.widget-settings.lock-keys.browse")
      onClicked: scrollPicker.open()
      enabled: valueShowScrollLock
    }
  }

  NIconPicker {
    id: scrollPicker
    initialIcon: scrollIcon
    query: "letter-s"
    onIconSelected: function (iconName) {
      scrollIcon = iconName
    }
  }
}
