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
    currentKeybind: Settings.data.general.keybinds.keyUp
    defaultKeybind: "Up"
    onKeybindChanged: newKeybind => Settings.data.general.keybinds.keyUp = newKeybind
  }

  NKeybindRecorder {
    Layout.fillWidth: true
    label: I18n.tr("panels.general.keybinds-down")
    currentKeybind: Settings.data.general.keybinds.keyDown
    defaultKeybind: "Down"
    onKeybindChanged: newKeybind => Settings.data.general.keybinds.keyDown = newKeybind
  }

  NKeybindRecorder {
    Layout.fillWidth: true
    label: I18n.tr("panels.general.keybinds-left")
    currentKeybind: Settings.data.general.keybinds.keyLeft
    defaultKeybind: "Left"
    onKeybindChanged: newKeybind => Settings.data.general.keybinds.keyLeft = newKeybind
  }

  NKeybindRecorder {
    Layout.fillWidth: true
    label: I18n.tr("panels.general.keybinds-right")
    currentKeybind: Settings.data.general.keybinds.keyRight
    defaultKeybind: "Right"
    onKeybindChanged: newKeybind => Settings.data.general.keybinds.keyRight = newKeybind
  }

  NKeybindRecorder {
    Layout.fillWidth: true
    label: I18n.tr("panels.general.keybinds-enter")
    currentKeybind: Settings.data.general.keybinds.keyEnter
    defaultKeybind: "Return"
    onKeybindChanged: newKeybind => Settings.data.general.keybinds.keyEnter = newKeybind
  }

  NKeybindRecorder {
    Layout.fillWidth: true
    label: I18n.tr("panels.general.keybinds-escape")
    currentKeybind: Settings.data.general.keybinds.keyEscape
    defaultKeybind: "Esc"
    onKeybindChanged: newKeybind => Settings.data.general.keybinds.keyEscape = newKeybind
  }
}
