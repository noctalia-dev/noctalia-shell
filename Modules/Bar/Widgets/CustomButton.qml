import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Modules.Panels.Settings
import qs.Services.Control
import qs.Services.UI
import qs.Widgets

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
      var widgets = Settings.data.bar.widgets[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property bool isVerticalBar: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"

  readonly property string customIcon: widgetSettings.icon || widgetMetadata.icon
  readonly property string leftClickExec: widgetSettings.leftClickExec || widgetMetadata.leftClickExec
  readonly property bool leftClickUpdateText: widgetSettings.leftClickUpdateText ?? widgetMetadata.leftClickUpdateText
  readonly property string rightClickExec: widgetSettings.rightClickExec || widgetMetadata.rightClickExec
  readonly property bool rightClickUpdateText: widgetSettings.rightClickUpdateText ?? widgetMetadata.rightClickUpdateText
  readonly property string middleClickExec: widgetSettings.middleClickExec || widgetMetadata.middleClickExec
  readonly property bool middleClickUpdateText: widgetSettings.middleClickUpdateText ?? widgetMetadata.middleClickUpdateText
  readonly property string ipcIdentifier: widgetSettings.ipcIdentifier !== undefined ? widgetSettings.ipcIdentifier : (widgetMetadata.ipcIdentifier || "")
  readonly property string wheelExec: widgetSettings.wheelExec || widgetMetadata.wheelExec
  readonly property string wheelUpExec: widgetSettings.wheelUpExec || widgetMetadata.wheelUpExec
  readonly property string wheelDownExec: widgetSettings.wheelDownExec || widgetMetadata.wheelDownExec
  readonly property string wheelMode: widgetSettings.wheelMode || widgetMetadata.wheelMode
  readonly property bool wheelUpdateText: widgetSettings.wheelUpdateText ?? widgetMetadata.wheelUpdateText
  readonly property bool wheelUpUpdateText: widgetSettings.wheelUpUpdateText ?? widgetMetadata.wheelUpUpdateText
  readonly property bool wheelDownUpdateText: widgetSettings.wheelDownUpdateText ?? widgetMetadata.wheelDownUpdateText
  readonly property string textCommand: widgetSettings.textCommand !== undefined ? widgetSettings.textCommand : (widgetMetadata.textCommand || "")
  readonly property bool textStream: widgetSettings.textStream !== undefined ? widgetSettings.textStream : (widgetMetadata.textStream || false)
  readonly property int textIntervalMs: widgetSettings.textIntervalMs !== undefined ? widgetSettings.textIntervalMs : (widgetMetadata.textIntervalMs || 3000)
  readonly property string textCollapse: widgetSettings.textCollapse !== undefined ? widgetSettings.textCollapse : (widgetMetadata.textCollapse || "")
  readonly property bool parseJson: widgetSettings.parseJson !== undefined ? widgetSettings.parseJson : (widgetMetadata.parseJson || false)
  readonly property bool hasExec: (leftClickExec || rightClickExec || middleClickExec || (wheelMode === "unified" && wheelExec) || (wheelMode === "separate" && (wheelUpExec || wheelDownExec)))
  readonly property bool showIcon: (widgetSettings.showIcon !== undefined) ? widgetSettings.showIcon : true
  readonly property string hideMode: widgetSettings.hideMode || "alwaysExpanded"
  readonly property bool hasOutput: _dynamicText !== ""
  readonly property bool shouldForceOpen: textStream && (hideMode === "alwaysExpanded" || hideMode === "maxTransparent")

  readonly property bool _useNewHideLogic: textCommand && textCommand.length > 0 && textStream
  readonly property bool _useTextCommandLogic: textCommand && textCommand.length > 0 && textStream

  readonly property bool _pillVisible: {
    if (!_useTextCommandLogic) {
      return true;
    }
    if (hideMode === "alwaysExpanded" || hideMode === "maxTransparent") {
      return true;
    }
    var hasActualIcon = (_dynamicIcon !== "" || customIcon !== "");
    return hasOutput || (showIcon && hasActualIcon);
  }

  readonly property real _pillOpacity: {
    if (!_useTextCommandLogic) {
      return 1.0;
    }
    if (hideMode === "maxTransparent" && !hasOutput) {
      return 0.0;
    }
    return 1.0;
  }

  readonly property bool _pillForceOpen: {
    if (!_useTextCommandLogic) {
      return _dynamicText !== "" || (textStream && currentMaxTextLength > 0);
    }
    if (currentMaxTextLength <= 0) {
      return false;
    }

    if (hideMode === "alwaysExpanded" || hideMode === "maxTransparent") {
      return true;
    }
    return hasOutput;
  }

  readonly property string _pillIcon: {
    if (!_useTextCommandLogic) {
      if (textCommand && textCommand.length > 0 && showIcon) {
        return _dynamicIcon !== "" ? _dynamicIcon : customIcon;
      } else if (!(textCommand && textCommand.length > 0)) {
        return _dynamicIcon !== "" ? _dynamicIcon : customIcon;
      } else {
        return "";
      }
    }
    if (!showIcon)
      return "";
    var actualIcon = _dynamicIcon !== "" ? _dynamicIcon : customIcon;
    if (hideMode === "expandWithOutput" && actualIcon === "") {
      return "question-mark";
    }
    return actualIcon;
  }

  readonly property string _pillText: {
    if (!_useTextCommandLogic) {
      return (!isVerticalBar || currentMaxTextLength > 0) ? _dynamicText : "";
    }
    if (currentMaxTextLength <= 0) {
      return "";
    }
    if (hasOutput) {
      return _dynamicText;
    }
    if (hideMode === "expandWithOutput") {
      return "";
    }
    return " ".repeat(currentMaxTextLength);
  }

  readonly property bool enableColorization: widgetSettings.enableColorization || false
  readonly property string colorizeSystemIcon: {
    if (widgetSettings.colorizeSystemIcon !== undefined)
      return widgetSettings.colorizeSystemIcon;
    return widgetMetadata.colorizeSystemIcon !== undefined ? widgetMetadata.colorizeSystemIcon : "none";
  }

  readonly property bool isColorizing: enableColorization && colorizeSystemIcon !== "none"

  readonly property color iconColor: {
    if (!isColorizing)
      return Color.mOnSurface;
    switch (colorizeSystemIcon) {
    case "primary":
      return Color.mPrimary;
    case "secondary":
      return Color.mSecondary;
    case "tertiary":
      return Color.mTertiary;
    case "error":
      return Color.mError;
    default:
      return Color.mOnSurface;
    }
  }
  readonly property color iconHoverColor: {
    if (!isColorizing)
      return Color.mOnHover;
    switch (colorizeSystemIcon) {
    case "primary":
      return Qt.darker(Color.mPrimary, 1.2);
    case "secondary":
      return Qt.darker(Color.mSecondary, 1.2);
    case "tertiary":
      return Qt.darker(Color.mTertiary, 1.2);
    case "error":
      return Qt.darker(Color.mError, 1.2);
    default:
      return Color.mOnHover;
    }
  }

  implicitWidth: pill.width
  implicitHeight: pill.height

  BarPill {
    id: pill

    visible: _pillVisible
    opacity: _pillOpacity
    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    icon: _pillIcon
    text: _pillText
    rotateText: isVerticalBar && currentMaxTextLength > 0
    autoHide: false
    forceOpen: _pillForceOpen
    customTextIconColor: isColorizing ? iconColor : "transparent"

    tooltipText: {
      var tooltipLines = [];

      if (hasExec) {
        if (leftClickExec !== "") {
          tooltipLines.push(`Left click: ${leftClickExec}.`);
        }
        if (rightClickExec !== "") {
          tooltipLines.push(`Right click: ${rightClickExec}.`);
        }
        if (middleClickExec !== "") {
          tooltipLines.push(`Middle click: ${middleClickExec}.`);
        }
        if (wheelMode === "unified" && wheelExec !== "") {
          tooltipLines.push(`Wheel: ${wheelExec}.`);
        } else if (wheelMode === "separate") {
          if (wheelUpExec !== "") {
            tooltipLines.push(`Wheel up: ${wheelUpExec}.`);
          }
          if (wheelDownExec !== "") {
            tooltipLines.push(`Wheel down: ${wheelDownExec}.`);
          }
        }
      }

      if (_dynamicTooltip !== "") {
        if (tooltipLines.length > 0) {
          tooltipLines.push("");
        }
        tooltipLines.push(_dynamicTooltip);
      }

      if (tooltipLines.length === 0) {
        return "Custom button, configure in settings.";
      } else {
        return tooltipLines.join("\n");
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

  // Maximum length for text display before scrolling (different values for horizontal and vertical)
  readonly property var maxTextLength: {
    "horizontal": ((widgetSettings && widgetSettings.maxTextLength && widgetSettings.maxTextLength.horizontal !== undefined) ? widgetSettings.maxTextLength.horizontal : ((widgetMetadata && widgetMetadata.maxTextLength && widgetMetadata.maxTextLength.horizontal !== undefined) ? widgetMetadata.maxTextLength.horizontal : 10)),
    "vertical": ((widgetSettings && widgetSettings.maxTextLength && widgetSettings.maxTextLength.vertical !== undefined) ? widgetSettings.maxTextLength.vertical : ((widgetMetadata && widgetMetadata.maxTextLength && widgetMetadata.maxTextLength.vertical !== undefined) ? widgetMetadata.maxTextLength.vertical : 10))
  }
  readonly property int _staticDuration: 6  // How many cycles to stay static at start/end

  // Encapsulated state for scrolling text implementation
  property var _scrollState: {
    "originalText": "",
    "needsScrolling": false,
    "offset": 0,
    "phase": 0 // 0=static start, 1=scrolling, 2=static end
        ,
    "phaseCounter": 0
  }

  // Current max text length based on bar orientation
  readonly property int currentMaxTextLength: isVerticalBar ? maxTextLength.vertical : maxTextLength.horizontal

  // Periodically run the text command (if set)
  Timer {
    id: refreshTimer
    interval: Math.max(250, textIntervalMs)
    repeat: true
    running: (!isVerticalBar || currentMaxTextLength > 0) && !textStream && textCommand && textCommand.length > 0
    triggeredOnStart: true
    onTriggered: root.runTextCommand()
  }

  // Restart exited text stream commands after a delay
  Timer {
    id: restartTimer
    interval: 1000
    running: (!isVerticalBar || currentMaxTextLength > 0) && textStream && !textProc.running
    onTriggered: root.runTextCommand()
  }

  // Timer for scrolling text display
  Timer {
    id: scrollTimer
    interval: 300
    repeat: true
    running: false
    onTriggered: {
      if (_scrollState.needsScrolling && _scrollState.originalText.length > currentMaxTextLength) {
        // Traditional marquee with pause at beginning and end
        if (_scrollState.phase === 0) {
          // Static at beginning
          _dynamicText = _scrollState.originalText.substring(0, Math.min(currentMaxTextLength, _scrollState.originalText.length));
          _scrollState.phaseCounter++;
          if (_scrollState.phaseCounter >= _staticDuration) {
            _scrollState.phaseCounter = 0;
            _scrollState.phase = 1;  // Move to scrolling
          }
        } else if (_scrollState.phase === 1) {
          // Scrolling
          _scrollState.offset++;
          var start = _scrollState.offset;
          var end = start + currentMaxTextLength;

          if (start >= _scrollState.originalText.length - currentMaxTextLength) {
            // Reached or passed the end, ensure we show the last part
            var textEnd = _scrollState.originalText.length;
            var textStart = Math.max(0, textEnd - currentMaxTextLength);
            _dynamicText = _scrollState.originalText.substring(textStart, textEnd);
            _scrollState.phase = 2;  // Move to static end phase
            _scrollState.phaseCounter = 0;
          } else {
            _dynamicText = _scrollState.originalText.substring(start, end);
          }
        } else if (_scrollState.phase === 2) {
          // Static at end
          // Ensure end text is displayed correctly
          var textEnd = _scrollState.originalText.length;
          var textStart = Math.max(0, textEnd - currentMaxTextLength);
          _dynamicText = _scrollState.originalText.substring(textStart, textEnd);
          _scrollState.phaseCounter++;
          if (_scrollState.phaseCounter >= _staticDuration) {
            // Do NOT loop back to start, just stop scrolling
            scrollTimer.stop();
          }
        }
      } else {
        scrollTimer.stop();
      }
    }
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
                  Logger.w("CustomButton", `Streaming text command exited (code: ${exitCode}), restarting...`);
                  return;
                }
              }
  }

  function parseDynamicContent(content) {
    var contentStr = String(content || "").trim();

    if (parseJson) {
      var lineToParse = contentStr;

      if (!textStream && contentStr.includes('\n')) {
        const lines = contentStr.split('\n').filter(line => line.trim() !== '');
        if (lines.length > 0) {
          lineToParse = lines[lines.length - 1];
        }
      }

      try {
        const parsed = JSON.parse(lineToParse);
        const text = parsed.text || "";
        const icon = parsed.icon || "";
        let tooltip = parsed.tooltip || "";

        if (checkCollapse(text)) {
          _scrollState.originalText = "";
          _dynamicText = "";
          _dynamicIcon = "";
          _dynamicTooltip = "";
          _scrollState.needsScrolling = false;
          _scrollState.phase = 0;
          _scrollState.phaseCounter = 0;
          return;
        }

        _scrollState.originalText = text;
        _scrollState.needsScrolling = text.length > currentMaxTextLength && currentMaxTextLength > 0;
        if (_scrollState.needsScrolling) {
          // Start with the beginning of the text
          _dynamicText = text.substring(0, currentMaxTextLength);
          _scrollState.phase = 0;  // Start at phase 0 (static beginning)
          _scrollState.phaseCounter = 0;
          _scrollState.offset = 0;
          scrollTimer.start();  // Start the scrolling timer
        } else {
          _dynamicText = text;
          scrollTimer.stop();
        }
        _dynamicIcon = icon;

        _dynamicTooltip = toHtml(tooltip);
        _scrollState.offset = 0;
        return;
      } catch (e) {
        Logger.w("CustomButton", `Failed to parse JSON. Content: "${lineToParse}"`);
      }
    }

    if (checkCollapse(contentStr)) {
      _scrollState.originalText = "";
      _dynamicText = "";
      _dynamicIcon = "";
      _dynamicTooltip = "";
      _scrollState.needsScrolling = false;
      _scrollState.phase = 0;
      _scrollState.phaseCounter = 0;
      return;
    }

    _scrollState.originalText = contentStr;
    _scrollState.needsScrolling = contentStr.length > currentMaxTextLength && currentMaxTextLength > 0;
    if (_scrollState.needsScrolling) {
      // Start with the beginning of the text
      _dynamicText = contentStr.substring(0, currentMaxTextLength);
      _scrollState.phase = 0;  // Start at phase 0 (static beginning)
      _scrollState.phaseCounter = 0;
      _scrollState.offset = 0;
      scrollTimer.start();  // Start the scrolling timer
    } else {
      _dynamicText = contentStr;
      scrollTimer.stop();
    }
    _dynamicIcon = "";
    _dynamicTooltip = toHtml(contentStr);
    _scrollState.offset = 0;
  }

  function checkCollapse(text) {
    if (!textCollapse || textCollapse.length === 0) {
      return false;
    }

    if (textCollapse.startsWith("/") && textCollapse.endsWith("/") && textCollapse.length > 1) {
      // Treat as regex
      var pattern = textCollapse.substring(1, textCollapse.length - 1);
      try {
        var regex = new RegExp(pattern);
        return regex.test(text);
      } catch (e) {
        Logger.w("CustomButton", `Invalid regex for textCollapse: ${textCollapse} - ${e.message}`);
        return (textCollapse === text); // Fallback to exact match on invalid regex
      }
    } else {
      // Treat as plain string
      return (textCollapse === text);
    }
  }

  Timer {
    id: subTabSwitchTimer
    interval: 200
    repeat: true
    running: false
    property int attempts: 0
    property int maxAttempts: 3

    function getAllChildren(item) {
      var children = [item];
      if (item.children) {
        for (var i = 0; i < item.children.length; i++) {
          children = children.concat(getAllChildren(item.children[i]));
        }
      }
      return children;
    }

    onTriggered: {
      attempts++;
      var panel = PanelService.getPanel("settingsPanel", root.screen);

      if (!panel?._settingsContent) {
        if (attempts >= maxAttempts) {
          Logger.w("CustomButton", "Timeout: settings panel not available");
          stop();
        }
        return;
      }

      var allChildren = getAllChildren(panel._settingsContent);
      for (var i = 0; i < allChildren.length; i++) {
        var child = allChildren[i];

        if (child && child.hasOwnProperty('currentIndex') &&
            child.toString && child.toString().toLowerCase().indexOf('tabview') !== -1) {
          var siblings = child.parent ? child.parent.children : [];
          for (var j = 0; j < siblings.length; j++) {
            var sibling = siblings[j];
            if (sibling !== child &&
                (sibling.objectName === "subTabBar" ||
                 (sibling.toString && sibling.toString().toLowerCase().indexOf('tabbar') !== -1))) {
              child.currentIndex = 1;
              sibling.currentIndex = 1;
              Logger.i("CustomButton", "Successfully switched to widgets tab");
              stop();
              return;
            }
          }
        }
      }

      if (attempts >= maxAttempts) {
        Logger.w("CustomButton", "Timeout: could not find tabView");
        stop();
      }
    }
  }

  function onClicked() {
    if (leftClickExec) {
      Quickshell.execDetached(["sh", "-lc", leftClickExec]);
      Logger.i("CustomButton", `Executing command: ${leftClickExec}`);
    } else if (!leftClickUpdateText) {
      openBarSettings();
    }
    if (!textStream && leftClickUpdateText) {
      runTextCommand();
    }
  }

  function openBarSettings() {
    var settingsPanel = PanelService.getPanel("settingsPanel", screen);
    settingsPanel.requestedTab = SettingsPanel.Tab.Bar;
    settingsPanel.open();
    subTabSwitchTimer.start();
  }

  function openWidgetSettings() {
    BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
  }

  function onRightClicked() {
    if (rightClickExec) {
      Quickshell.execDetached(["sh", "-lc", rightClickExec]);
      Logger.i("CustomButton", `Executing command: ${rightClickExec}`);
    }
    if (!textStream && rightClickUpdateText) {
      runTextCommand();
    }
  }

  function onMiddleClicked() {
    if (middleClickExec) {
      Quickshell.execDetached(["sh", "-lc", middleClickExec]);
      Logger.i("CustomButton", `Executing command: ${middleClickExec}`);
    }
    if (!textStream && middleClickUpdateText) {
      runTextCommand();
    }
  }

  function toHtml(str) {
    const htmlTagRegex = /<\/?[a-zA-Z][^>]*>/g;
    const placeholders = [];
    let i = 0;
    const protectedStr = str.replace(htmlTagRegex, tag => {
                                       placeholders.push(tag);
                                       return `___HTML_TAG_${i++}___`;
                                     });

    let escaped = protectedStr.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;").replace(/\r\n|\r|\n/g, "<br/>");

    escaped = escaped.replace(/___HTML_TAG_(\d+)___/g, (_, index) => placeholders[Number(index)]);

    return escaped;
  }

  function runTextCommand() {
    if (!textCommand || textCommand.length === 0)
      return;
    if (textProc.running)
      return;
    textProc.command = ["sh", "-lc", textCommand];
    textProc.running = true;
  }

  function onWheel(delta) {
    if (wheelMode === "unified" && wheelExec) {
      let normalizedDelta = delta > 0 ? 1 : -1;

      let command = wheelExec.replace(/\$delta([+\-*/]\d+)?/g, function (match, operation) {
        if (operation) {
          try {
            let operator = operation.charAt(0);
            let operand = parseInt(operation.substring(1));

            let result;
            switch (operator) {
            case '+':
              result = normalizedDelta + operand;
              break;
            case '-':
              result = normalizedDelta - operand;
              break;
            case '*':
              result = normalizedDelta * operand;
              break;
            case '/':
              result = Math.floor(normalizedDelta / operand);
              break;
            default:
              result = normalizedDelta;
            }

            return result.toString();
          } catch (e) {
            Logger.w("CustomButton", `Error evaluating expression: ${match}, using normalized value ${normalizedDelta}`);
            return normalizedDelta.toString();
          }
        } else {
          return normalizedDelta.toString();
        }
      });

      Quickshell.execDetached(["sh", "-lc", command]);
      Logger.i("CustomButton", `Executing command: ${command}`);
    } else if (wheelMode === "separate") {
      if ((delta > 0 && wheelUpExec) || (delta < 0 && wheelDownExec)) {
        let commandExec = delta > 0 ? wheelUpExec : wheelDownExec;
        let normalizedDelta = delta > 0 ? 1 : -1;

        let command = commandExec.replace(/\$delta([+\-*/]\d+)?/g, function (match, operation) {
          if (operation) {
            try {
              let operator = operation.charAt(0);
              let operand = parseInt(operation.substring(1));

              let result;
              switch (operator) {
              case '+':
                result = normalizedDelta + operand;
                break;
              case '-':
                result = normalizedDelta - operand;
                break;
              case '*':
                result = normalizedDelta * operand;
                break;
              case '/':
                result = Math.floor(normalizedDelta / operand);
                break;
              default:
                result = normalizedDelta;
              }

              return result.toString();
            } catch (e) {
              Logger.w("CustomButton", `Error evaluating expression: ${match}, using normalized value ${normalizedDelta}`);
              return normalizedDelta.toString();
            }
          } else {
            return normalizedDelta.toString();
          }
        });

        Quickshell.execDetached(["sh", "-lc", command]);
        Logger.i("CustomButton", `Executing command: ${command}`);
      }
    }

    if (!textStream) {
      if (wheelMode === "unified" && wheelUpdateText) {
        runTextCommand();
      } else if (wheelMode === "separate") {
        if ((delta > 0 && wheelUpUpdateText) || (delta < 0 && wheelDownUpdateText)) {
          runTextCommand();
        }
      }
    }
  }

  // Timer to handle registration attempts
  Timer {
    id: registrationTimer
    interval: 1500
    repeat: false
    onTriggered: {
      // Only register if ipcIdentifier is set
      if (ipcIdentifier && ipcIdentifier.trim() !== "") {
        // Try to access the service through the global application object
        try {
          if (typeof Qt !== 'undefined' && Qt.application && Qt.application.customButtonIPCService) {
            var service = Qt.application.customButtonIPCService;
            var success = service.registerButton(root);
            if (success) {
              Logger.i("CustomButton", `Successfully registered button with identifier: '${ipcIdentifier}'`);
            } else {
              Logger.w("CustomButton", `Failed to register button with identifier: '${ipcIdentifier}'`);
            }
          } else {
            Logger.w("CustomButton", `Service not available for button with identifier '${ipcIdentifier}'`);
          }
        } catch (e) {
          Logger.w("CustomButton", `Error during registration of button with identifier '${ipcIdentifier}': ${e.message}`);
        }
      } else {
        Logger.d("CustomButton", `No IPC identifier set for button, skipping registration`);
      }
    }
  }

  // Register this button with the IPC service when component is completed
  Component.onCompleted: {
    registrationTimer.start();
  }

  // Unregister this button when component is destroyed
  Component.onDestruction: {
    if (ipcIdentifier && ipcIdentifier.trim() !== "") {
      // Try to access the service through the global application object for unregistration
      try {
        if (typeof Qt !== 'undefined' && Qt.application && Qt.application.customButtonIPCService) {
          var service = Qt.application.customButtonIPCService;
          var success = service.unregisterButton(root);
          if (success) {
            Logger.i("CustomButton", `Successfully unregistered button with identifier: '${ipcIdentifier}'`);
          } else {
            Logger.w("CustomButton", `Failed to unregister button with identifier: '${ipcIdentifier}'`);
          }
        } else {
          Logger.w("CustomButton", `Service not available for unregistration of button with identifier '${ipcIdentifier}'`);
        }
      } catch (e) {
        Logger.w("CustomButton", `Error during unregistration of button with identifier '${ipcIdentifier}': ${e.message}`);
      }
    }
  }
}
