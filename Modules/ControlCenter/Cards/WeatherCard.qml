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

  ColumnLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.marginM * scaling
    spacing: Style.marginM * scaling
    clip: true

    RowLayout {
      spacing: Style.marginS * scaling
      NIcon {
        Layout.alignment: Qt.AlignVCenter
        icon: weatherReady ? LocationService.weatherSymbolFromCode(LocationService.data.weather.current_weather.weathercode) : ""
        pointSize: Style.fontSizeXXXL * 1.75 * scaling
        color: Color.mPrimary
      }

      ColumnLayout {
        spacing: Style.marginXXS * scaling
        NText {
          text: {
            // Ensure the name is not too long if one had to specify the country
            const chunks = Settings.data.location.name.split(",")
            return chunks[0]
          }
          pointSize: Style.fontSizeL * scaling
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
            pointSize: Style.fontSizeXL * scaling
            font.weight: Style.fontWeightBold
          }

          NText {
            text: weatherReady ? `(${LocationService.data.weather.timezone_abbreviation})` : ""
            pointSize: Style.fontSizeXS * scaling
            color: Color.mOnSurfaceVariant
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
      Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
      spacing: Style.marginL * scaling
      Repeater {
        model: weatherReady ? LocationService.data.weather.daily.time : []
        delegate: ColumnLayout {
          Layout.alignment: Qt.AlignHCenter
          spacing: Style.marginS * scaling
          NText {
            text: {
              var weatherDate = new Date(LocationService.data.weather.daily.time[index].replace(/-/g, "/"))
              return Qt.locale().toString(weatherDate, "ddd")
            }
            color: Color.mOnSurface
            Layout.alignment: Qt.AlignHCenter
          }
          NIcon {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            icon: LocationService.weatherSymbolFromCode(LocationService.data.weather.daily.weathercode[index])
            pointSize: Style.fontSizeXXL * 1.6 * scaling
            color: Color.mPrimary
          }
          NText {
            Layout.alignment: Qt.AlignHCenter
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
            pointSize: Style.fontSizeXS * scaling
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
