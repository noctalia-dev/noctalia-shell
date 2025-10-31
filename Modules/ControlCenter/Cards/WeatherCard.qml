import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

// Weather overview card (placeholder data)
NBox {
  id: root

  property int forecastDays: 7
  property bool showLocation: true
  readonly property bool weatherReady: Settings.data.location.weatherEnabled && (LocationService.data.weather !== null)

  visible: Settings.data.location.weatherEnabled
  implicitHeight: Math.max(100 * Style.uiScaleRatio, content.implicitHeight + (Style.marginXL * 2))

  ColumnLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.marginXL
    spacing: Style.marginM
    clip: true

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS
      Item {
        Layout.preferredWidth: 0
      }
      NIcon {
        Layout.alignment: Qt.AlignVCenter
        icon: weatherReady ? LocationService.weatherSymbolFromCode(LocationService.data.weather.current_weather.weathercode) : ""
        pointSize: Style.fontSizeXXXL * 1.75
        color: Color.mPrimary
      }

      ColumnLayout {
        spacing: Style.marginXXS
        NText {
          text: {
            // Ensure the name is not too long if one had to specify the country
            const chunks = Settings.data.location.name.split(",")
            return chunks[0]
          }
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          visible: showLocation
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
            pointSize: showLocation ? Style.fontSizeXL : Style.fontSizeXL * 1.6
            font.weight: Style.fontWeightBold
          }

          NText {
            text: weatherReady ? `(${LocationService.data.weather.timezone_abbreviation})` : ""
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
            visible: LocationService.data.weather && showLocation
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
      Layout.alignment: Qt.AlignVCenter
      spacing: Style.marginM

      Repeater {
        model: weatherReady ? Math.min(root.forecastDays, LocationService.data.weather.daily.time.length) : 0
        delegate: ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginXS
          Item {
            Layout.fillWidth: true
          }
          NText {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            text: {
              var weatherDate = new Date(LocationService.data.weather.daily.time[index].replace(/-/g, "/"))
              return I18n.locale.toString(weatherDate, "ddd")
            }
            color: Color.mOnSurface
          }
          NIcon {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            icon: LocationService.weatherSymbolFromCode(LocationService.data.weather.daily.weathercode[index])
            pointSize: Style.fontSizeXXL * 1.6
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
            pointSize: Style.fontSizeXS
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
