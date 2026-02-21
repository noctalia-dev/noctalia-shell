import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Services.Location
import qs.Widgets

DraggableDesktopWidget {
  id: root

  readonly property bool weatherReady: Settings.data.location.weatherEnabled && (LocationService.data.weather !== null)
  readonly property int currentWeatherCode: weatherReady ? LocationService.data.weather.current_weather.weathercode : 0
  readonly property real currentTemp: {
    if (!weatherReady)
      return 0;
    var temp = LocationService.data.weather.current_weather.temperature;
    if (Settings.data.location.useFahrenheit) {
      temp = LocationService.celsiusToFahrenheit(temp);
    }
    return Math.round(temp);
  }
  readonly property real todayMax: {
    if (!weatherReady || !LocationService.data.weather.daily || LocationService.data.weather.daily.temperature_2m_max.length === 0)
      return 0;
    var temp = LocationService.data.weather.daily.temperature_2m_max[0];
    if (Settings.data.location.useFahrenheit) {
      temp = LocationService.celsiusToFahrenheit(temp);
    }
    return Math.round(temp);
  }
  readonly property real todayMin: {
    if (!weatherReady || !LocationService.data.weather.daily || LocationService.data.weather.daily.temperature_2m_min.length === 0)
      return 0;
    var temp = LocationService.data.weather.daily.temperature_2m_min[0];
    if (Settings.data.location.useFahrenheit) {
      temp = LocationService.celsiusToFahrenheit(temp);
    }
    return Math.round(temp);
  }
  readonly property string tempUnit: Settings.data.location.useFahrenheit ? "F" : "C"
  readonly property string locationName: {
    const chunks = Settings.data.location.name.split(",");
    return chunks[0];
  }

  implicitWidth: Math.round(Math.max(240 * widgetScale, contentLayout.implicitWidth + Style.margin2M * widgetScale))
  implicitHeight: Math.round(64 * widgetScale + Style.margin2M * widgetScale)
  width: implicitWidth
  height: implicitHeight

  RowLayout {
    id: contentLayout
    anchors.fill: parent
    anchors.margins: Math.round(Style.marginM * widgetScale)
    spacing: Math.round(Style.marginM * widgetScale)
    z: 2

    Item {
      Layout.preferredWidth: Math.round(64 * widgetScale)
      Layout.preferredHeight: Math.round(64 * widgetScale)
      Layout.alignment: Qt.AlignVCenter

      NIcon {
        anchors.centerIn: parent
        icon: weatherReady ? LocationService.weatherSymbolFromCode(currentWeatherCode, LocationService.data.weather.current_weather.is_day) : "weather-cloud-off"
        pointSize: Math.round(Style.fontSizeXXXL * 2 * widgetScale)
        color: weatherReady ? Color.mPrimary : Color.mOnSurfaceVariant
      }
    }

    NText {
      text: weatherReady ? `${currentTemp}°${tempUnit}` : "---"
      pointSize: Math.round(Style.fontSizeXXXL * widgetScale)
      font.weight: Style.fontWeightBold
      color: Color.mOnSurface
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Math.round(Style.marginXXS * widgetScale)
      Layout.alignment: Qt.AlignVCenter

      NText {
        Layout.fillWidth: true
        text: locationName || "No location"
        pointSize: Math.round(Style.fontSizeS * widgetScale)
        font.weight: Style.fontWeightRegular
        color: Color.mOnSurfaceVariant
        elide: Text.ElideRight
        maximumLineCount: 1
        visible: !Settings.data.location.hideWeatherCityName
      }

      RowLayout {
        spacing: Math.round(Style.marginXS * widgetScale)
        visible: weatherReady && todayMax > 0 && todayMin > 0

        NText {
          text: "H:"
          pointSize: Math.round(Style.fontSizeXS * widgetScale)
          color: Color.mOnSurfaceVariant
        }
        NText {
          text: `${todayMax}°`
          pointSize: Math.round(Style.fontSizeXS * widgetScale)
          color: Color.mOnSurface
        }

        NText {
          text: "•"
          pointSize: Math.round(Style.fontSizeXXS * widgetScale)
          color: Color.mOnSurfaceVariant
          opacity: 0.5
        }

        NText {
          text: "L:"
          pointSize: Math.round(Style.fontSizeXS * widgetScale)
          color: Color.mOnSurfaceVariant
        }
        NText {
          text: `${todayMin}°`
          pointSize: Math.round(Style.fontSizeXS * widgetScale)
          color: Color.mOnSurfaceVariant
        }
      }
    }
  }
}
