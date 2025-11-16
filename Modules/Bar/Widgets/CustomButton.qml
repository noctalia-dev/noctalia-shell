import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets
import qs.Modules.Panels.Settings
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

  readonly property bool isVerticalBar: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"

  readonly property string customIcon: widgetSettings.icon || widgetMetadata.icon
  readonly property string leftClickExec: widgetSettings.leftClickExec || widgetMetadata.leftClickExec
  readonly property bool leftClickUpdateText: widgetSettings.leftClickUpdateText ?? widgetMetadata.leftClickUpdateText
  readonly property string rightClickExec: widgetSettings.rightClickExec || widgetMetadata.rightClickExec
  readonly property bool rightClickUpdateText: widgetSettings.rightClickUpdateText ?? widgetMetadata.rightClickUpdateText
  readonly property string middleClickExec: widgetSettings.middleClickExec || widgetMetadata.middleClickExec
  readonly property bool middleClickUpdateText: widgetSettings.middleClickUpdateText ?? widgetMetadata.middleClickUpdateText
  readonly property string wheelExec: widgetSettings.wheelExec || widgetMetadata.wheelExec
  readonly property bool wheelUpdateText: widgetSettings.wheelUpdateText ?? widgetMetadata.wheelUpdateText
  readonly property string textCommand: widgetSettings.textCommand !== undefined ? widgetSettings.textCommand : (widgetMetadata.textCommand || "")
  readonly property bool textStream: widgetSettings.textStream !== undefined ? widgetSettings.textStream : (widgetMetadata.textStream || false)
  readonly property int textIntervalMs: widgetSettings.textIntervalMs !== undefined ? widgetSettings.textIntervalMs : (widgetMetadata.textIntervalMs || 3000)
  readonly property string textCollapse: widgetSettings.textCollapse !== undefined ? widgetSettings.textCollapse : (widgetMetadata.textCollapse || "")
  readonly property bool parseJson: widgetSettings.parseJson !== undefined ? widgetSettings.parseJson : (widgetMetadata.parseJson || false)
  readonly property bool hideTextInVerticalBar: widgetSettings.hideTextInVerticalBar !== undefined ? widgetSettings.hideTextInVerticalBar : (widgetMetadata.hideTextInVerticalBar || false)
  readonly property bool hasExec: (leftClickExec || rightClickExec || middleClickExec || wheelExec)

  readonly property bool shouldShowText: !isVerticalBar || !hideTextInVerticalBar

  implicitWidth: pill.width
  implicitHeight: pill.height

  BarPill {
    id: pill

    oppositeDirection: BarService.getPillDirection(root)
    icon: _dynamicIcon !== "" ? _dynamicIcon : customIcon
    text: shouldShowText ? _dynamicText : ""
    density: Settings.data.bar.density
    rotateText: isVerticalBar && !hideTextInVerticalBar
    autoHide: false
    forceOpen: _dynamicText !== ""
    tooltipText: {
      var tooltipLines = []

      if (hasExec) {
        if (leftClickExec !== "") {
          tooltipLines.push(`Left click: ${leftClickExec}.`)
        }
        if (rightClickExec !== "") {
          tooltipLines.push(`Right click: ${rightClickExec}.`)
        }
        if (middleClickExec !== "") {
          tooltipLines.push(`Middle click: ${middleClickExec}.`)
        }
        if (wheelExec !== "") {
          tooltipLines.push(`Wheel: ${wheelExec}.`)
        }
      }

      if (_dynamicTooltip !== "") {
        if (tooltipLines.length > 0) {
          tooltipLines.push("")
        }
        tooltipLines.push(_dynamicTooltip)
      }

      if (tooltipLines.length === 0) {
        return "Custom button, configure in settings."
      } else {
        return tooltipLines.join("\n")
      }
    }

    onClicked: root.onClicked()
    onRightClicked: root.onRightClicked()
    onMiddleClicked: root.onMiddleClicked()
    onWheel: delta => root.onWheel(delta)
  }

  // Internal state for dynamic text
  property string _dynamicText: ""
  property string _dynamicIcon: ""
  property string _dynamicTooltip: ""

  // Periodically run the text command (if set)
  Timer {
    id: refreshTimer
    interval: Math.max(250, textIntervalMs)
    repeat: true
    running: shouldShowText && !textStream && textCommand && textCommand.length > 0
    triggeredOnStart: true
    onTriggered: root.runTextCommand()
  }

  // Restart exited text stream commands after a delay
  Timer {
    id: restartTimer
    interval: 1000
    running: shouldShowText && textStream && !textProc.running
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

    if (parseJson) {
      var lineToParse = contentStr

      if (!textStream && contentStr.includes('\n')) {
        const lines = contentStr.split('\n').filter(line => line.trim() !== '')
        if (lines.length > 0) {
          lineToParse = lines[lines.length - 1]
        }
      }

      try {
        const parsed = JSON.parse(lineToParse)
        const text = parsed.text || ""
        const icon = parsed.icon || ""
        const tooltip = parsed.tooltip || ""

        if (checkCollapse(text)) {
          _dynamicText = ""
          _dynamicIcon = ""
          _dynamicTooltip = ""
          return
        }

        _dynamicText = text
        _dynamicIcon = icon
        _dynamicTooltip = tooltip
        return
      } catch (e) {
        Logger.w("CustomButton", `Failed to parse JSON. Content: "${lineToParse}"`)
      }
    }

    if (checkCollapse(contentStr)) {
      _dynamicText = ""
      _dynamicIcon = ""
      _dynamicTooltip = ""
      return
    }

    _dynamicText = contentStr
    _dynamicIcon = ""
    _dynamicTooltip = ""
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
    } else if (!hasExec && !leftClickUpdateText) {
      // No script was defined, open settings
      var settingsPanel = PanelService.getPanel("settingsPanel", screen)
      settingsPanel.requestedTab = SettingsPanel.Tab.Bar
      settingsPanel.open()
    }
    if (!textStream && leftClickUpdateText) {
      runTextCommand()
    }
  }

  function onRightClicked() {
    if (rightClickExec) {
      Quickshell.execDetached(["sh", "-c", rightClickExec])
      Logger.i("CustomButton", `Executing command: ${rightClickExec}`)
    }
    if (!textStream && rightClickUpdateText) {
      runTextCommand()
    }
  }

  function onMiddleClicked() {
    if (middleClickExec) {
      Quickshell.execDetached(["sh", "-c", middleClickExec])
      Logger.i("CustomButton", `Executing command: ${middleClickExec}`)
    }
    if (!textStream && middleClickUpdateText) {
      runTextCommand()
    }
  }

  function onWheel(delta) {
    if (wheelExec) {
      let command = wheelExec.replace(/\$delta/g, delta)
      Quickshell.execDetached(["sh", "-c", command])
      Logger.i("CustomButton", `Executing command: ${command}`)
    }
    if (!textStream && wheelUpdateText) {
      runTextCommand()
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
