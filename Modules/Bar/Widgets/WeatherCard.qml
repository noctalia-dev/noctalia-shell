import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

/**
 * Weather forecast popup card
 * Simple and elegant design matching SidePanel style
 */
NPanel {
  id: root

  property var weatherData: LocationService.data.weather
  readonly property bool weatherReady: Settings.data.location.weatherEnabled && (weatherData !== null)

  preferredWidth: 500
  preferredHeight: 280
  panelKeyboardFocus: false

  panelContent: NBox {
    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM
      clip: true

      // Header with current weather
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        // Weather icon
        NIcon {
          Layout.alignment: Qt.AlignVCenter
          icon: weatherReady ? LocationService.weatherSymbolFromCode(root.weatherData.current_weather.weathercode) : ""
          pointSize: Style.fontSizeXXXL * 1.75
          color: Color.mPrimary
          visible: weatherReady
        }

        // Location and temperature
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginXXS

          NText {
            text: {
              if (!Settings.data.location.name) return ""
              const chunks = Settings.data.location.name.split(",")
              return chunks[0]
            }
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
          }

          RowLayout {
            spacing: Style.marginXS

            NText {
              visible: weatherReady
              text: {
                if (!weatherReady) return ""
                var temp = root.weatherData.current_weather.temperature
                var suffix = "C"
                if (Settings.data.location.useFahrenheit) {
                  temp = LocationService.celsiusToFahrenheit(temp)
                  suffix = "F"
                }
                return Math.round(temp) + "°" + suffix
              }
              pointSize: Style.fontSizeXL
              font.weight: Style.fontWeightBold
            }

            NText {
              text: weatherReady ? "(" + root.weatherData.timezone_abbreviation + ")" : ""
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
              visible: weatherReady
            }
          }
        }

        Item { Layout.fillWidth: true }

        // Close button
        NIconButton {
          Layout.alignment: Qt.AlignTop
          icon: "close"
          tooltipText: "Close"
          baseSize: Style.baseWidgetSize * 0.8
          onClicked: root.close()
        }
      }

      // Divider
      NDivider {
        visible: weatherReady
        Layout.fillWidth: true
      }

      // 7-Day Forecast
      RowLayout {
        visible: weatherReady
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.marginM

        Repeater {
          model: weatherReady ? root.weatherData.daily.time : []

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginXS

            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: 0
            }

            // Day name
            NText {
              Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
              text: {
                var weatherDate = new Date(root.weatherData.daily.time[index].replace(/-/g, "/"))
                return Qt.locale().toString(weatherDate, "ddd")
              }
              pointSize: Style.fontSizeS
              color: Color.mOnSurface
            }

            // Weather icon
            NIcon {
              Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
              icon: LocationService.weatherSymbolFromCode(root.weatherData.daily.weathercode[index])
              pointSize: Style.fontSizeXXL * 1.6
              color: Color.mPrimary
            }

            // Max/Min temperature
            NText {
              Layout.alignment: Qt.AlignHCenter
              text: {
                var max = root.weatherData.daily.temperature_2m_max[index]
                var min = root.weatherData.daily.temperature_2m_min[index]
                if (Settings.data.location.useFahrenheit) {
                  max = LocationService.celsiusToFahrenheit(max)
                  min = LocationService.celsiusToFahrenheit(min)
                }
                return Math.round(max) + "°/" + Math.round(min) + "°"
              }
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }
          }
        }
      }

      // Loading indicator
      RowLayout {
        visible: !weatherReady
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignHCenter

        NBusyIndicator {
          Layout.alignment: Qt.AlignHCenter
        }
      }
    }
  }
}