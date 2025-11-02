import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

/**
 * Weather forecast panel
 * Simple and elegant design matching SidePanel style
 */
NPanel {
  id: root

  property var weatherData: LocationService.data.weather
  readonly property bool weatherReady: Settings.data.location.weatherEnabled && (weatherData !== null)

  preferredWidth: 500 * Style.uiScaleRatio
  preferredHeight: 280 * Style.uiScaleRatio
  panelKeyboardFocus: false

  panelContent: NBox {
    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL * Style.uiScaleRatio
      spacing: Style.marginM * Style.uiScaleRatio
      clip: true

      // Header with current weather
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM * Style.uiScaleRatio

        // Weather icon
        NIcon {
          Layout.alignment: Qt.AlignVCenter
          icon: weatherReady ? LocationService.weatherSymbolFromCode(root.weatherData.current_weather.weathercode) : ""
          pointSize: (Style.fontSizeXXXL * 1.75) * Style.uiScaleRatio
          color: Color.mPrimary
          visible: weatherReady
        }

        // Location and temperature
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginXXS * Style.uiScaleRatio

          NText {
            text: {
              if (!Settings.data.location.name) return ""
              const chunks = Settings.data.location.name.split(",")
              return chunks[0]
            }
            pointSize: Style.fontSizeL * Style.uiScaleRatio
            font.weight: Style.fontWeightBold
          }

          RowLayout {
            spacing: Style.marginXS * Style.uiScaleRatio

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
              pointSize: Style.fontSizeXL * Style.uiScaleRatio
              font.weight: Style.fontWeightBold
            }

            NText {
              text: weatherReady ? "(" + root.weatherData.timezone_abbreviation + ")" : ""
              pointSize: Style.fontSizeXS * Style.uiScaleRatio
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
          baseSize: Style.baseWidgetSize * 0.8 * Style.uiScaleRatio
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
        spacing: Style.marginM * Style.uiScaleRatio

        Repeater {
          model: weatherReady ? root.weatherData.daily.time : []

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginXS * Style.uiScaleRatio

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
              pointSize: Style.fontSizeS * Style.uiScaleRatio
              color: Color.mOnSurface
            }

            // Weather icon
            NIcon {
              Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
              icon: LocationService.weatherSymbolFromCode(root.weatherData.daily.weathercode[index])
              pointSize: (Style.fontSizeXXXL * 1.6) * Style.uiScaleRatio
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
              pointSize: Style.fontSizeXS * Style.uiScaleRatio
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