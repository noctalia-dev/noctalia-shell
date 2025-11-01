import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

/**
 * Weather Widget for Noctalia Bar
 * Shows current weather icon and temperature
 * Click to open detailed forecast popup
 */
Rectangle {
  id: root

  // Properties provided by Bar.qml via NWidgetLoader
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0
  property real scaling: 1.0
  
  // Widget metadata and per-instance settings
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

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property bool density: Settings.data.bar.density

  // Weather data from LocationService
  readonly property bool weatherReady: Settings.data.location.weatherEnabled && (LocationService.data.weather !== null)
  readonly property bool weatherEnabled: Settings.data.location.weatherEnabled
  readonly property var weatherData: LocationService.data.weather

  readonly property real iconSize: textSize * 1.4
  readonly property real textSize: {
    var base = isVertical ? width * 0.43 : height
    return Math.max(1, (density === "compact") ? base * 0.43 : base * 0.33)
  }
  
  // Location name (first part before comma)
  readonly property string location: {
    if (!Settings.data.location.name) return "N/A"
    const chunks = Settings.data.location.name.split(",")
    return chunks[0]
  }
  
  // Current temperature (converted to F if needed)
  readonly property real temperature: {
    if (!weatherReady || !weatherData || !weatherData.current_weather) return 0
    var temp = weatherData.current_weather.temperature
    if (Settings.data.location.useFahrenheit) {
      temp = LocationService.celsiusToFahrenheit(temp)
    }
    return temp
  }
  
  // Weather icon based on weather code
  readonly property string weatherIcon: {
    if (!weatherReady || !weatherData || !weatherData.current_weather) return "partly_cloudy_day"
    return LocationService.weatherSymbolFromCode(weatherData.current_weather.weathercode)
  }
  
  readonly property string weatherCode: (weatherReady && weatherData && weatherData.current_weather) ? weatherData.current_weather.weathercode : ""
  readonly property bool useFahrenheit: Settings.data.location.useFahrenheit || false

  // User configurable settings from widget metadata
  property bool showIcon: widgetSettings.showIcon !== undefined ? widgetSettings.showIcon : (widgetMetadata && widgetMetadata.showIcon !== undefined ? widgetMetadata.showIcon : true)
  property bool showTemperature: widgetSettings.showTemperature !== undefined ? widgetSettings.showTemperature : (widgetMetadata && widgetMetadata.showTemperature !== undefined ? widgetMetadata.showTemperature : true)
  
  // Capsule settings (background/border) from Bar configuration
  property bool showCapsule: widgetSettings.showCapsule !== undefined ? widgetSettings.showCapsule : Settings.data.bar.showCapsule

  // Widget dimensions
  implicitHeight: Math.round(Style.capsuleHeight * scaling)
  implicitWidth: Math.round(48 * scaling)
  
  // Capsule styling
  radius: showCapsule ? Math.round(Style.radiusS * scaling) : 0
  color: showCapsule ? Color.mSurfaceVariant : "transparent"
  border.width: showCapsule ? Math.max(1, Style.borderS * scaling) : 0
  border.color: showCapsule ? Color.mOutline : "transparent"

  // Widget content layout
  RowLayout {
    id: layout
    anchors.fill: parent
    anchors.margins: Math.round(Style.marginXS * scaling)
    spacing: Math.round(Style.marginXS * scaling)

    // Loading indicator (shown while fetching weather data)
    NBusyIndicator {
      visible: weatherEnabled && !weatherReady
      Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
      Layout.preferredWidth: Math.round(Style.iconSizeS * scaling)
      Layout.preferredHeight: Math.round(Style.iconSizeS * scaling)
    }

    GridLayout {
      id: mainGrid
      anchors.centerIn: parent
      flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
      rows: isVertical ? -1 : 1
      columns: isVertical ? 1 : -1
      rowSpacing: isVertical ? (Style.marginM) : 0
      columnSpacing: isVertical ? 0 : (Style.marginM)

      Item {
        Layout.preferredWidth: isVertical ? root.width : iconSize + percentTextWidth + (Style.marginXXS)
        Layout.preferredHeight: Style.capsuleHeight
        Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter

        GridLayout {
          id: weatherContent
          anchors.centerIn: parent
          flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
          rows: isVertical ? 2 : 1
          columns: isVertical ? 1 : 2
          rowSpacing: Style.marginXXS
          columnSpacing: Style.marginXXS

            // Weather icon
            NIcon {
              id: weatherIcon
              icon: root.weatherIcon
              pointSize: iconSize
              applyUiScale: false
              Layout.alignment: Qt.AlignCenter
              Layout.row: isVertical ? 1 : 0
              Layout.column: 0
            }

            // Temperature text
            NText {
              text: Math.round(root.temperature) + "°" + (root.useFahrenheit ? "F" : "C")
              family: Settings.data.ui.fontFixed
              pointSize: textSize
              applyUiScale: false
              font.weight: Style.fontWeightMedium
              Layout.alignment: Qt.AlignCenter
              Layout.preferredWidth: isVertical ? -1 : percentTextWidth
              horizontalAlignment: isVertical ? Text.AlignHCenter : Text.AlignRight
              verticalAlignment: Text.AlignVCenter
              color: Color.mPrimary
              Layout.row: isVertical ? 0 : 0
              Layout.column: isVertical ? 0 : 1
              scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
            }

          }
      }
    }
  }

  // Weather forecast popup (uses NPanel for consistent positioning)
  WeatherCard {
    id: weatherPopup
  }

  // Click handler - toggle popup
  MouseArea {
    id: mouseArea
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true

    onClicked: function(mouse) {
      weatherPopup.open(root, "Weather")
    }  
  }

  // Monitor weather data changes from LocationService
  Connections {
    target: LocationService
    
    function onDataChanged() {
      // Weather data updated
    }
  }

  // Initialization
  Component.onCompleted: {
    console.log("Weather widget initialized")
    console.log("Weather enabled:", root.weatherEnabled)
    console.log("Weather ready:", root.weatherReady)
    console.log("Location:", root.location)
    
    if (!root.weatherEnabled) {
      console.warn("Weather is disabled in settings. Enable it in Settings > Location > Weather")
    }
  }
}