import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.UI
import qs.Widgets

Rectangle {
  id: root

  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  // Settings
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

  // Bar orientation
  readonly property bool isVertical: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"

  // Widget settings
  readonly property string fromCurrency: (widgetSettings.fromCurrency !== undefined) ? widgetSettings.fromCurrency : widgetMetadata.fromCurrency
  readonly property string toCurrency: (widgetSettings.toCurrency !== undefined) ? widgetSettings.toCurrency : widgetMetadata.toCurrency
  readonly property int updateInterval: (widgetSettings.updateInterval !== undefined) ? widgetSettings.updateInterval : widgetMetadata.updateInterval
  readonly property string displayMode: (widgetSettings.displayMode !== undefined) ? widgetSettings.displayMode : widgetMetadata.displayMode

  // State
  property real exchangeRate: 0.0
  property bool loading: false
  property bool error: false
  property string errorMessage: ""
  property real customAmount: 1.0
  property var allRates: ({})  // Store all exchange rates

  implicitWidth: isVertical ? Style.capsuleHeight : contentWidth
  implicitHeight: isVertical ? contentHeight : Style.capsuleHeight
  radius: Style.radiusM
  color: Style.capsuleColor
  border.color: Style.capsuleBorderColor
  border.width: Style.capsuleBorderWidth

  readonly property real contentWidth: {
    if (isVertical) return Style.capsuleHeight;
    var iconWidth = Style.toOdd(Style.capsuleHeight * 0.6);
    var textWidth = rateText.implicitWidth + Style.marginS;
    if (displayMode === "icon") return iconWidth + Style.marginM * 2;
    if (displayMode === "text") return textWidth + Style.marginM * 2;
    return iconWidth + textWidth + Style.marginM * 2;
  }

  readonly property real contentHeight: {
    if (!isVertical) return Style.capsuleHeight;
    var iconHeight = Style.toOdd(Style.capsuleHeight * 0.6);
    var textHeight = rateText.implicitHeight;
    return Math.max(iconHeight, textHeight) + Style.marginS * 2;
  }

  // API call process
  Process {
    id: apiProcess
    running: false

    command: [
      "curl",
      "-s",
      `https://api.exchangerate-api.com/v4/latest/${fromCurrency}`
    ]

    stdout: StdioCollector {}

    onExited: exitCode => {
      loading = false;
      if (exitCode === 0) {
        try {
          var response = JSON.parse(stdout.text);
          if (response.rates) {
            allRates = response.rates;
            if (response.rates[toCurrency]) {
              exchangeRate = response.rates[toCurrency];
              error = false;
              errorMessage = "";
            } else {
              error = true;
              errorMessage = I18n.tr("currency-converter.error.invalid-currency") || "Invalid currency";
            }
          } else {
            error = true;
            errorMessage = I18n.tr("currency-converter.error.invalid-currency") || "Invalid currency";
          }
        } catch (e) {
          error = true;
          errorMessage = I18n.tr("currency-converter.error.parse") || "Parse error";
        }
      } else {
        error = true;
        errorMessage = I18n.tr("currency-converter.error.network") || "Network error";
      }
    }
  }

  // Update timer
  Timer {
    id: updateTimer
    interval: updateInterval * 60000 // Convert minutes to milliseconds
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: fetchExchangeRate()
  }

  function fetchExchangeRate() {
    if (loading) return;
    loading = true;
    error = false;
    apiProcess.running = true;
  }

  readonly property string displayText: {
    if (loading) return I18n.tr("currency-converter.loading") || "Loading...";
    if (error) return I18n.tr("currency-converter.error") || "Error";
    if (exchangeRate === 0.0) return "--";
    return `1 ${fromCurrency} = ${exchangeRate.toFixed(2)} ${toCurrency}`;
  }

  readonly property string tooltipText: {
    if (error) return errorMessage;
    if (exchangeRate === 0.0) return I18n.tr("currency-converter.tooltip.waiting") || "Waiting for data...";
    return `${displayText}\n${I18n.tr("currency-converter.tooltip.click") || "Click to open converter"}`;
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: isVertical ? 0 : Style.marginM
    anchors.rightMargin: isVertical ? 0 : Style.marginM
    anchors.topMargin: isVertical ? Style.marginS : 0
    anchors.bottomMargin: isVertical ? Style.marginS : 0
    spacing: Style.marginS
    visible: !isVertical

    NIcon {
      icon: error ? "alert-circle" : (loading ? "loader" : "currency-dollar")
      color: error ? Color.mError : Color.mPrimary
      pointSize: Style.toOdd(Style.capsuleHeight * 0.5)
      Layout.alignment: Qt.AlignVCenter
      visible: displayMode !== "text"
      
      RotationAnimator on rotation {
        running: loading && !error
        from: 0
        to: 360
        duration: 1000
        loops: Animation.Infinite
      }
    }

    NText {
      id: rateText
      text: displayText
      color: error ? Color.mError : Color.mOnSurface
      pointSize: Style.barFontSize
      applyUiScale: false
      Layout.alignment: Qt.AlignVCenter
      visible: displayMode !== "icon"
    }
  }

  // Vertical layout
  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginS
    spacing: Style.marginXS
    visible: isVertical

    NIcon {
      icon: error ? "alert-circle" : (loading ? "loader" : "currency-dollar")
      color: error ? Color.mError : Color.mPrimary
      pointSize: Style.toOdd(Style.capsuleHeight * 0.45)
      Layout.alignment: Qt.AlignHCenter
      
      RotationAnimator on rotation {
        running: loading && !error
        from: 0
        to: 360
        duration: 1000
        loops: Animation.Infinite
      }
    }

    NText {
      text: `${exchangeRate.toFixed(2)}`
      color: error ? Color.mError : Color.mOnSurface
      pointSize: Style.barFontSize * 0.8
      applyUiScale: false
      Layout.alignment: Qt.AlignHCenter
      visible: !loading && !error && exchangeRate > 0
    }
  }

  // Mouse interaction
  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: mouse => {
      if (mouse.button === Qt.LeftButton) {
        // Open converter panel
        var panel = PanelService.getPanel("currencyConverterPanel", screen);
        if (panel) {
          panel.converterWidget = root;
          panel.toggle();
        }
      } else if (mouse.button === Qt.RightButton) {
        TooltipService.hide();
        var popupWindow = PanelService.getPopupMenuWindow(screen);
        if (popupWindow) {
          popupWindow.showContextMenu(contextMenu);
          contextMenu.openAtItem(root, screen);
        }
      }
    }

    onEntered: {
      TooltipService.show(root, tooltipText, BarService.getTooltipDirection());
    }
    onExited: TooltipService.hide()
  }

  // Context menu
  NPopupContextMenu {
    id: contextMenu
    model: [
      {
        "label": I18n.tr("currency-converter.refresh") || "Refresh",
        "action": "refresh",
        "icon": "refresh"
      },
      {
        "label": I18n.tr("context-menu.widget-settings") || "Widget Settings",
        "action": "settings",
        "icon": "settings"
      }
    ]

    onTriggered: action => {
      var popupWindow = PanelService.getPopupMenuWindow(screen);
      if (popupWindow)
        popupWindow.close();

      if (action === "refresh") {
        fetchExchangeRate();
      } else if (action === "settings") {
        BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
      }
    }
  }
}
