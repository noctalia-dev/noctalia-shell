import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.Settings
import qs.Modules.Bar.Extras

Item {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  // Use settings or defaults from BarWidgetRegistry
  readonly property string customIcon: widgetSettings.icon || widgetMetadata.icon
  readonly property string leftClickExec: widgetSettings.leftClickExec || widgetMetadata.leftClickExec
  readonly property string rightClickExec: widgetSettings.rightClickExec || widgetMetadata.rightClickExec
  readonly property string middleClickExec: widgetSettings.middleClickExec || widgetMetadata.middleClickExec
  readonly property string textCommand: widgetSettings.textCommand !== undefined ? widgetSettings.textCommand : (widgetMetadata.textCommand || "")
  readonly property bool textStream: widgetSettings.textStream !== undefined ? widgetSettings.textStream : (widgetMetadata.textStream || false)
  readonly property int textIntervalMs: widgetSettings.textIntervalMs !== undefined ? widgetSettings.textIntervalMs : (widgetMetadata.textIntervalMs || 3000)
  readonly property string textCollapse: widgetSettings.textCollapse !== undefined ? widgetSettings.textCollapse : (widgetMetadata.textCollapse || "")
  readonly property bool parseJson: widgetSettings.parseJson !== undefined ? widgetSettings.parseJson : (widgetMetadata.parseJson || false)
  readonly property bool hasExec: (leftClickExec || rightClickExec || middleClickExec)

  implicitWidth: pill.width
  implicitHeight: pill.height

  BarPill {
    id: pill

    oppositeDirection: BarService.getPillDirection(root)
    icon: _dynamicIcon !== "" ? _dynamicIcon : customIcon
    text: _dynamicText
    density: Settings.data.bar.density
    autoHide: false
    forceOpen: _dynamicText !== ""
    tooltipText: {
      if (!hasExec) {
        return "Custom button, configure in settings."
      } else {
        var lines = []
        if (leftClickExec !== "") {
          lines.push(`Left click: ${leftClickExec}.`)
        }
        if (rightClickExec !== "") {
          lines.push(`Right click: ${rightClickExec}.`)
        }
        if (middleClickExec !== "") {
          lines.push(`Middle click: ${middleClickExec}.`)
        }
        return lines.join("\n")
      }
    }

    onClicked: root.onClicked()
    onRightClicked: root.onRightClicked()
    onMiddleClicked: root.onMiddleClicked()
  }

  // Internal state for dynamic text
  property string _dynamicText: ""
  property string _dynamicIcon: ""

  // Periodically run the text command (if set)
  Timer {
    id: refreshTimer
    interval: Math.max(250, textIntervalMs)
    repeat: true
    running: !textStream && textCommand && textCommand.length > 0
    triggeredOnStart: true
    onTriggered: root.runTextCommand()
  }

  // Restart exited text stream commands after a delay
  Timer {
    id: restartTimer
    interval: 1000
    running: textStream && !textProc.running
    onTriggered: root.runTextCommand()
  }

  SplitParser {
    id: textStdoutSplit
    onRead: line => root.parseDynamicContent(line)
  }

  StdioCollector {
    id: textStdoutCollect
    onStreamFinished: () => root.parseDynamicContent(this.text)
  }

  Process {
    id: textProc
    stdout: textStream ? textStdoutSplit : textStdoutCollect
    stderr: StdioCollector {}
    onExited: (exitCode, exitStatus) => {
                if (textStream) {
                  Logger.w("CustomButton", `Streaming text command exited (code: ${exitCode}), restarting...`)
                  return
                }
              }
  }

  function parseDynamicContent(content) {
    var contentStr = String(content || "").trim()
    if (contentStr.indexOf("\n") !== -1) {
      contentStr = contentStr.split("\n")[0]
    }

    if (parseJson) {
      try {
        var parsed = JSON.parse(contentStr)
        var text = parsed.text || ""

        if (checkCollapse(text)) {
          _dynamicText = ""
          _dynamicIcon = ""
          return
        }

        _dynamicText = text
        _dynamicIcon = parsed.icon || ""
        return
      } catch (e) {

        // Not a valid JSON, treat as plain text
      }
    }

    if (checkCollapse(contentStr)) {
      _dynamicText = ""
      _dynamicIcon = ""
      return
    }

    _dynamicText = contentStr
    _dynamicIcon = ""
  }

  function checkCollapse(text) {
    if (!textCollapse || textCollapse.length === 0) {
      return false
    }

    if (textCollapse.startsWith("/") && textCollapse.endsWith("/") && textCollapse.length > 1) {
      // Treat as regex
      var pattern = textCollapse.substring(1, textCollapse.length - 1)
      try {
        var regex = new RegExp(pattern)
        return regex.test(text)
      } catch (e) {
        Logger.w("CustomButton", `Invalid regex for textCollapse: ${textCollapse} - ${e.message}`)
        return (textCollapse === text) // Fallback to exact match on invalid regex
      }
    } else {
      // Treat as plain string
      return (textCollapse === text)
    }
  }

  function onClicked() {
    if (leftClickExec) {
      Quickshell.execDetached(["sh", "-c", leftClickExec])
      Logger.i("CustomButton", `Executing command: ${leftClickExec}`)
    } else if (!hasExec) {
      // No script was defined, open settings
      var settingsPanel = PanelService.getPanel("settingsPanel")
      settingsPanel.requestedTab = SettingsPanel.Tab.Bar
      settingsPanel.open()
    }
  }

  function onRightClicked() {
    if (rightClickExec) {
      Quickshell.execDetached(["sh", "-c", rightClickExec])
      Logger.i("CustomButton", `Executing command: ${rightClickExec}`)
    }
  }

  function onMiddleClicked() {
    if (middleClickExec) {
      Quickshell.execDetached(["sh", "-c", middleClickExec])
      Logger.i("CustomButton", `Executing command: ${middleClickExec}`)
    }
  }

  function runTextCommand() {
    if (!textCommand || textCommand.length === 0)
      return
    if (textProc.running)
      return
    textProc.command = ["sh", "-lc", textCommand]
    textProc.running = true
  }
}
