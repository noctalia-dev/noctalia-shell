import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Location
import qs.Widgets

// Weather overview card (placeholder data)
NBox {
  id: root

  property int forecastDays: 6
  property bool showLocation: true
  property bool showEffects: Settings.data.location.weatherShowEffects
  readonly property bool weatherReady: Settings.data.location.weatherEnabled && (LocationService.data.weather !== null)

  // Test mode: set to "rain" or "snow"
  property string testEffects: ""

  // Weather condition detection
  readonly property int currentWeatherCode: weatherReady ? LocationService.data.weather.current_weather.weathercode : 0
  readonly property bool isRaining: testEffects === "rain" || (testEffects === "" && ((currentWeatherCode >= 51 && currentWeatherCode <= 67) || (currentWeatherCode >= 80 && currentWeatherCode <= 82)))
  readonly property bool isSnowing: testEffects === "snow" || (testEffects === "" && ((currentWeatherCode >= 71 && currentWeatherCode <= 77) || (currentWeatherCode >= 85 && currentWeatherCode <= 86)))

  visible: Settings.data.location.weatherEnabled
  implicitHeight: Math.max(100 * Style.uiScaleRatio, content.implicitHeight + (Style.marginXL * 2))

  // Weather effect layer (rain/snow)
  Loader {
    id: weatherEffectLoader
    anchors.fill: parent
    active: root.showEffects && (root.isRaining || root.isSnowing)

    sourceComponent: Item {
      anchors.fill: parent

      // Animated time for shaders
      property real shaderTime: 0
      NumberAnimation on shaderTime {
        loops: Animation.Infinite
        from: 0
        to: 1000
        duration: 100000
      }

      ShaderEffect {
        id: weatherEffect
        anchors.fill: parent
        // Snow fills the box, rain matches content margins
        anchors.margins: root.isSnowing ? root.border.width : Style.marginXL

        property var source: ShaderEffectSource {
          sourceItem: content
          hideSource: root.isRaining // Only hide for rain (distortion), show for snow
        }

        property real time: parent.shaderTime
        property real itemWidth: weatherEffect.width
        property real itemHeight: weatherEffect.height
        property color bgColor: root.color
        property real cornerRadius: root.isSnowing ? (root.radius - root.border.width) : 0

        fragmentShader: root.isSnowing ? Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/weather_snow.frag.qsb") : Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/weather_rain.frag.qsb")
      }
    }
  }

  ColumnLayout {
    id: content
    anchors.fill: parent
    anchors.margins: Style.marginXL
    spacing: Style.marginM
    clip: true

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      Item {
        Layout.preferredWidth: Style.marginXXS
      }

      RowLayout {
        spacing: Style.marginL
        Layout.fillWidth: true

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
              const chunks = Settings.data.location.name.split(",");
              return chunks[0];
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
                  return "";
                }
                var temp = LocationService.data.weather.current_weather.temperature;
                var suffix = "C";
                if (Settings.data.location.useFahrenheit) {
                  temp = LocationService.celsiusToFahrenheit(temp);
                  var suffix = "F";
                }
                temp = Math.round(temp);
                return `${temp}°${suffix}`;
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
              var weatherDate = new Date(LocationService.data.weather.daily.time[index].replace(/-/g, "/"));
              return I18n.locale.toString(weatherDate, "ddd");
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
              var max = LocationService.data.weather.daily.temperature_2m_max[index];
              var min = LocationService.data.weather.daily.temperature_2m_min[index];
              if (Settings.data.location.useFahrenheit) {
                max = LocationService.celsiusToFahrenheit(max);
                min = LocationService.celsiusToFahrenheit(min);
              }
              max = Math.round(max);
              min = Math.round(min);
              return `${max}°/${min}°`;
            }
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }
        }
      }
    }

    Loader {
      active: !weatherReady
      Layout.alignment: Qt.AlignCenter
      sourceComponent: NBusyIndicator {}
    }
  }
}
