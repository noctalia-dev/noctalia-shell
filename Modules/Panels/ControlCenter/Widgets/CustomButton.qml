import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Widgets

Item {
  id: root

  property string widgetId: "CustomButton"
  property var widgetSettings: null

  property string onClickedCommand: ""
  property string onRightClickedCommand: ""
  property string onMiddleClickedCommand: ""
  property string stateChecksJson: "[]" // Store state checks as JSON string

  property string generalTooltipText: "Custom Button"
  property bool enableOnStateLogic: false

  property string _currentIcon: "heart" // Default icon
  property bool _isHot: false
  property var _parsedStateChecks: [] // Local array for parsed state checks

  property int _currentStateCheckIndex: -1
  property string _activeStateIcon: ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Connections {
    target: root

    function _updatePropertiesFromSettings() {
      if (!widgetSettings) {
        return
      }

      onClickedCommand = widgetSettings.onClicked || ""
      onRightClickedCommand = widgetSettings.onRightClicked || ""
      onMiddleClickedCommand = widgetSettings.onMiddleClicked || ""
      stateChecksJson = widgetSettings.stateChecksJson || "[]" // Populate from widgetSettings
      try {
        _parsedStateChecks = JSON.parse(stateChecksJson)
      } catch (e) {
        console.error("CustomButton: Failed to parse stateChecksJson:", e.message)
        _parsedStateChecks = []
      }
      generalTooltipText = widgetSettings.generalTooltipText || "Custom Button"
      enableOnStateLogic = widgetSettings.enableOnStateLogic || false

      updateState()
    }

    function onWidgetSettingsChanged() {
      if (widgetSettings) {
        _updatePropertiesFromSettings()
      }
    }
  }

  Process {
    id: stateCheckProcessExecutor
    running: false
    command: _currentStateCheckIndex !== -1 && _parsedStateChecks.length > _currentStateCheckIndex ? ["sh", "-c", _parsedStateChecks[_currentStateCheckIndex].command] : []
    onExited: function (exitCode, stdout, stderr) {
      var currentCheckItem = _parsedStateChecks[_currentStateCheckIndex]
      var currentCommand = currentCheckItem.command
      if (exitCode === 0) {
        // Command succeeded, this is the active state
        _isHot = true
        _activeStateIcon = currentCheckItem.icon || widgetSettings.icon || "heart"
      } else {
        // Command failed, try next one
        _currentStateCheckIndex++
        _checkNextState()
      }
    }
  }

  Timer {
    id: stateUpdateTimer
    interval: 200
    running: false
    repeat: false
    onTriggered: {
      if (enableOnStateLogic && _parsedStateChecks.length > 0) {
        _currentStateCheckIndex = 0
        _checkNextState()
      } else {
        _isHot = false
        _activeStateIcon = widgetSettings.icon || "heart"
      }
    }
  }

  function _checkNextState() {
    if (_currentStateCheckIndex < _parsedStateChecks.length) {
      var currentCheckItem = _parsedStateChecks[_currentStateCheckIndex]
      if (currentCheckItem && currentCheckItem.command) {
        stateCheckProcessExecutor.running = true
      } else {
        _currentStateCheckIndex++
        _checkNextState()
      }
    } else {
      // All checks failed
      _isHot = false
      _activeStateIcon = widgetSettings.icon || "heart"
    }
  }

  function updateState() {
    if (!enableOnStateLogic || _parsedStateChecks.length === 0) {
      _isHot = false
      _activeStateIcon = widgetSettings.icon || "heart"
      return
    }
    stateUpdateTimer.restart()
  }

  function _buildTooltipText() {
    let tooltip = generalTooltipText
    if (onClickedCommand) {
      tooltip += `\nLeft click: ${onClickedCommand}`
    }
    if (onRightClickedCommand) {
      tooltip += `\nRight click: ${onRightClickedCommand}`
    }
    if (onMiddleClickedCommand) {
      tooltip += `\nMiddle click: ${onMiddleClickedCommand}`
    }

    return tooltip
  }

  NIconButtonHot {
    id: button
    icon: _activeStateIcon
    hot: _isHot
    tooltipText: _buildTooltipText()
    onClicked: {
      if (onClickedCommand) {
        Quickshell.execDetached(["sh", "-c", onClickedCommand])
        updateState()
      }
    }
    onRightClicked: {
      if (onRightClickedCommand) {
        Quickshell.execDetached(["sh", "-c", onRightClickedCommand])
        updateState()
      }
    }
    onMiddleClicked: {
      if (onMiddleClickedCommand) {
        Quickshell.execDetached(["sh", "-c", onMiddleClickedCommand])
        updateState()
      }
    }
  }
}
