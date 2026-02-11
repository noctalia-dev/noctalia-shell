import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  width: parent.width

  // Keybinds section
  NLabel {
    label: I18n.tr("panels.general.keybinds-title")
    description: I18n.tr("panels.general.keybinds-description")
    Layout.fillWidth: true
  }

  NKeybindRecorder {
    Layout.fillWidth: true
    label: I18n.tr("panels.general.keybinds-up")
    currentKeybinds: Settings.data.general.keybinds.keyUp
    defaultKeybind: "Up"
    onKeybindsChanged: newKeybinds => Settings.data.general.keybinds.keyUp = newKeybinds
  }

  NKeybindRecorder {
    Layout.fillWidth: true
    label: I18n.tr("panels.general.keybinds-down")
    currentKeybinds: Settings.data.general.keybinds.keyDown
    defaultKeybind: "Down"
    onKeybindsChanged: newKeybinds => Settings.data.general.keybinds.keyDown = newKeybinds
  }

  NKeybindRecorder {
    Layout.fillWidth: true
    label: I18n.tr("panels.general.keybinds-left")
    currentKeybinds: Settings.data.general.keybinds.keyLeft
    defaultKeybind: "Left"
    onKeybindsChanged: newKeybinds => Settings.data.general.keybinds.keyLeft = newKeybinds
  }

  NKeybindRecorder {
    Layout.fillWidth: true
    label: I18n.tr("panels.general.keybinds-right")
    currentKeybinds: Settings.data.general.keybinds.keyRight
    defaultKeybind: "Right"
    onKeybindsChanged: newKeybinds => Settings.data.general.keybinds.keyRight = newKeybinds
  }

  NKeybindRecorder {
    Layout.fillWidth: true
    label: I18n.tr("panels.general.keybinds-enter")
    currentKeybinds: Settings.data.general.keybinds.keyEnter
    defaultKeybind: "Return"
    onKeybindsChanged: newKeybinds => Settings.data.general.keybinds.keyEnter = newKeybinds
  }

  NKeybindRecorder {
    Layout.fillWidth: true
    label: I18n.tr("panels.general.keybinds-escape")
    currentKeybinds: Settings.data.general.keybinds.keyEscape
    defaultKeybind: "Esc"
    onKeybindsChanged: newKeybinds => Settings.data.general.keybinds.keyEscape = newKeybinds
  }
}
