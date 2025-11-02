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
            var widgets = Settings.data.bar.widgets[section];
            if (widgets && sectionWidgetIndex < widgets.length) {
                return widgets[sectionWidgetIndex];
            }
        }
        return {};
    }

    // Weather data from LocationService
    readonly property bool weatherReady: Settings.data.location.weatherEnabled && (LocationService.data.weather !== null)
    readonly property bool weatherEnabled: Settings.data.location.weatherEnabled
    readonly property var weatherData: LocationService.data.weather

    // Location name (first part before comma)
    readonly property string location: {
        if (!Settings.data.location.name)
            return "N/A";
        const chunks = Settings.data.location.name.split(",");
        return chunks[0];
    }

    // Current temperature (converted to F if needed)
    readonly property real temperature: {
        if (!weatherReady || !weatherData || !weatherData.current_weather)
            return 0;
        var temp = weatherData.current_weather.temperature;
        if (Settings.data.location.useFahrenheit) {
            temp = LocationService.celsiusToFahrenheit(temp);
        }
        return temp;
    }

    // Weather icon based on weather code
    readonly property string weatherIcon: {
        if (!weatherReady || !weatherData || !weatherData.current_weather)
            return "partly_cloudy_day";
        return LocationService.weatherSymbolFromCode(weatherData.current_weather.weathercode);
    }

    readonly property string weatherCode: (weatherReady && weatherData && weatherData.current_weather) ? weatherData.current_weather.weathercode : ""
    readonly property bool useFahrenheit: Settings.data.location.useFahrenheit || false

    // Bar orientation and density settings (matching SystemMonitor pattern)
    readonly property string barPosition: Settings.data.bar.position
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
    readonly property bool density: Settings.data.bar.density

    // Dynamic text sizing based on orientation and density (matching SystemMonitor)
    readonly property real textSize: {
        var base = isBarVertical ? width * 0.45 : height;
        return isBarVertical ? Math.max(1, (density === "compact") ? base * 0.30 : base * 0.20) : Math.max(1, (density === "compact") ? base * 0.45 : base * 0.35);
    }
    readonly property real iconSize: textSize * 1.4

    // Text metrics for measuring text dimensions
    TextMetrics {
        id: temperatureMetrics
        font.family: Settings.data.ui.fontDefault
        font.weight: Style.fontWeightMedium
        font.pointSize: textSize
        text: "99°F" // Longest possible temperature text
    }

    TextMetrics {
        id: disabledMetrics
        font.family: Settings.data.ui.fontDefault
        font.weight: Style.fontWeightMedium
        font.pointSize: textSize
        text: "Weather disabled" // Disabled message text
    }

    // Text width calculations
    readonly property int temperatureTextWidth: Math.ceil(temperatureMetrics.boundingRect.width + 3)
    readonly property int disabledTextWidth: Math.ceil(disabledMetrics.boundingRect.width + 3)

    // User configurable settings from widget metadata
    property bool showIcon: widgetSettings.showIcon !== undefined ? widgetSettings.showIcon : (widgetMetadata && widgetMetadata.showIcon !== undefined ? widgetMetadata.showIcon : true)
    property bool showTemperature: widgetSettings.showTemperature !== undefined ? widgetSettings.showTemperature : (widgetMetadata && widgetMetadata.showTemperature !== undefined ? widgetMetadata.showTemperature : true)

    // Capsule settings (background/border) from Bar configuration
    property bool showCapsule: Settings.data.bar.showCapsule

    // Widget dimensions
    implicitHeight: Math.round(Style.capsuleHeight * scaling)
    implicitWidth: Math.round((showIcon && showTemperature ? 80 : 50) * scaling)

    // Capsule styling
    radius: showCapsule ? Math.round(Style.radiusS * scaling) : 0
    color: showCapsule ? Color.mSurfaceVariant : "transparent"
    border.width: showCapsule ? Math.max(1, Style.borderS * scaling) : 0
    border.color: showCapsule ? Color.mOutline : "transparent"

    // Widget content layout
    Item {
        id: layoutContainer
        anchors.fill: parent
        anchors.margins: Math.round(Style.marginXS * scaling)

        // Horizontal layout for top/bottom bars
        Loader {
            id: horizontalLayout
            active: !isBarVertical
            anchors.centerIn: parent
            sourceComponent: RowLayout {
                spacing: Math.round(Style.marginXS * scaling)

                // Loading indicator (shown while fetching weather data)
                NBusyIndicator {
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
                    Layout.preferredWidth: Math.round(Style.iconSizeS * scaling)
                    Layout.preferredHeight: Math.round(Style.iconSizeS * scaling)
                    visible: weatherEnabled && !weatherReady
                }

                // Weather icon
                NIcon {
                    id: icon
                    visible: root.showIcon && root.weatherReady
                    Layout.alignment: Qt.AlignVCenter
                    icon: root.weatherIcon
                    pointSize: root.iconSize
                    color: Color.mPrimary
                }

                // Temperature text
                NText {
                    id: tempText
                    visible: root.showTemperature && root.weatherReady
                    Layout.alignment: Qt.AlignVCenter
                    text: Math.round(root.temperature) + "°" + (root.useFahrenheit ? "F" : "C")
                    font.pointSize: root.textSize
                    font.family: Settings.data.ui.fontDefault
                    font.weight: Style.fontWeightMedium
                    Layout.preferredWidth: root.temperatureTextWidth
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    color: Color.mOnSurface
                }

                // Weather disabled message
                NText {
                    visible: !weatherEnabled
                    Layout.alignment: Qt.AlignVCenter
                    text: "Weather disabled"
                    font.pointSize: root.textSize
                    font.family: Settings.data.ui.fontDefault
                    font.weight: Style.fontWeightMedium
                    Layout.preferredWidth: root.disabledTextWidth
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    color: Color.mOnSurfaceVariant
                }
            }
        }

        // Vertical layout for left/right bars
        Loader {
            id: verticalLayout
            active: isBarVertical
            anchors.centerIn: parent
            sourceComponent: ColumnLayout {
                spacing: Math.round(Style.marginXS * scaling)

                // Loading indicator (shown while fetching weather data)
                NBusyIndicator {
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    Layout.preferredWidth: Math.round(Style.iconSizeS * scaling)
                    Layout.preferredHeight: Math.round(Style.iconSizeS * scaling)
                    visible: weatherEnabled && !weatherReady
                }

                // Weather icon (top)
                NIcon {
                    id: iconVertical
                    visible: root.showIcon && root.weatherReady
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    icon: root.weatherIcon
                    pointSize: root.iconSize
                    color: Color.mPrimary
                }

                // Temperature text (bottom)
                NText {
                    id: tempTextVertical
                    visible: root.showTemperature && root.weatherReady
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    text: Math.round(root.temperature) + "°" + (root.useFahrenheit ? "F" : "C")
                    font.pointSize: root.textSize
                    font.family: Settings.data.ui.fontDefault
                    font.weight: Style.fontWeightMedium
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Color.mOnSurface
                    scale: isBarVertical ? Math.min(1.0, root.width / (root.temperatureTextWidth + Style.marginM * 2)) : 1.0
                }

                // Weather disabled message
                NText {
                    visible: !weatherEnabled
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    text: "Weather disabled"
                    font.pointSize: root.textSize
                    font.family: Settings.data.ui.fontDefault
                    font.weight: Style.fontWeightMedium
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Color.mOnSurfaceVariant
                    scale: isBarVertical ? Math.min(1.0, root.width / (root.disabledTextWidth + Style.marginM * 2)) : 1.0
                }
            }
        }
    }

    // Click handler - toggle popup
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true

        onClicked: function (mouse) {
            // Toggle weather panel using PanelService
            PanelService.getPanel("weatherPanel")?.toggle(this);
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
        console.log("Weather widget initialized");
        console.log("Weather enabled:", root.weatherEnabled);
        console.log("Weather ready:", root.weatherReady);
        console.log("Location:", root.location);

        if (!root.weatherEnabled) {
            console.warn("Weather is disabled in settings. Enable it in Settings > Location > Weather");
        }
    }
}
