import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

// Weather overview card (placeholder data)
NBox {
  id: root

  readonly property bool weatherReady: (LocationService.data.weather !== null)

  // TBC weatherReady is not turning to false when we reset weather...
  Layout.fillWidth: true
  // Height driven by content
  implicitHeight: content.implicitHeight + Style.marginLarge * 2 * scaling

  ColumnLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.marginMedium * scaling
    spacing: Style.marginMedium * scaling

    RowLayout {
      spacing: Style.marginSmall * scaling
      NIcon {
        text: weatherReady ? LocationService.weatherSymbolFromCode(
                               LocationService.data.weather.current_weather.weathercode) : ""
        font.pointSize: Style.fontSizeXXL * 1.5 * scaling
        color: Color.mPrimary
      }

      ColumnLayout {
        spacing: -Style.marginTiny * scaling
        NText {
          text: {
            // Ensure the name is not too long if one had to specify the country
            const chunks = Settings.data.location.name.split(",")
            return chunks[0]
          }
          font.pointSize: Style.fontSizeLarger * scaling
          font.weight: Style.fontWeightBold
        }

        RowLayout {
          NText {
            visible: weatherReady
            text: {
              if (!weatherReady) {
                return ""
              }
              var temp = LocationService.data.weather.current_weather.temperature
              var suffix = "C"
              if (Settings.data.location.useFahrenheit) {
                temp = LocationService.celsiusToFahrenheit(temp)
                var suffix = "F"
              }
              temp = Math.round(temp)
              return `${temp}°${suffix}`
            }
            font.pointSize: Style.fontSizeXL * scaling
            font.weight: Style.fontWeightBold
          }

          NText {
            text: weatherReady ? `(${LocationService.data.weather.timezone_abbreviation})` : ""
            font.pointSize: Style.fontSizeSmall * scaling
            visible: LocationService.data.weather
          }
        }
      }
    }

    NDivider {
      visible: weatherReady
      Layout.fillWidth: true
    }

    RowLayout {
      visible: weatherReady
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignHCenter
      spacing: Style.marginLarge * scaling
      Repeater {
        model: weatherReady ? LocationService.data.weather.daily.time : []
        delegate: ColumnLayout {
          Layout.alignment: Qt.AlignHCenter
          spacing: Style.marginSmall * scaling
          NText {
            text: Qt.formatDateTime(new Date(LocationService.data.weather.daily.time[index]), "ddd")
            color: Color.mOnSurface
          }
          NIcon {
            text: LocationService.weatherSymbolFromCode(LocationService.data.weather.daily.weathercode[index])
            font.pointSize: Style.fontSizeXL * scaling
            color: Color.mPrimary
          }
          NText {
            text: {
              var max = LocationService.data.weather.daily.temperature_2m_max[index]
              var min = LocationService.data.weather.daily.temperature_2m_min[index]
              if (Settings.data.location.useFahrenheit) {
                max = LocationService.celsiusToFahrenheit(max)
                min = LocationService.celsiusToFahrenheit(min)
              }
              max = Math.round(max)
              min = Math.round(min)
              return `${max}°/${min}°`
            }
            font.pointSize: Style.fontSizeSmall * scaling
            color: Color.mOnSurfaceVariant
          }
        }
      }
    }

    RowLayout {
      visible: !weatherReady
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignHCenter
      NBusyIndicator {}
    }
  }
}
