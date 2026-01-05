import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Location
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NHeader {
    label: I18n.tr("settings.location.location.section.label")
    description: I18n.tr("settings.location.location.section.description")
  }

  // Location section
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginL

    NTextInput {
      label: I18n.tr("settings.location.location.search.label")
      description: I18n.tr("settings.location.location.search.description")
      text: Settings.data.location.name || Settings.defaultLocation
      placeholderText: I18n.tr("settings.location.location.search.placeholder")
      onEditingFinished: {
        // Verify the location has really changed to avoid extra resets
        var newLocation = text.trim();
        // If empty, set to default location
        if (newLocation === "") {
          newLocation = Settings.defaultLocation;
          text = Settings.defaultLocation; // Update the input field to show the default
        }
        if (newLocation != Settings.data.location.name) {
          Settings.data.location.name = newLocation;
          LocationService.resetWeather();
        }
      }
    }

    NText {
      visible: LocationService.coordinatesReady
      text: I18n.tr("system.location-display", {
                      "name": LocationService.stableName,
                      "coordinates": LocationService.displayCoordinates
                    })
      pointSize: Style.fontSizeS
      color: Color.mOnSurfaceVariant
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: Text.AlignRight
      Layout.alignment: Qt.AlignBottom
      Layout.bottomMargin: Style.marginM
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // Weather section
  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.location.weather.section.label")
      description: I18n.tr("settings.location.weather.section.description")
    }

    NToggle {
      label: I18n.tr("settings.location.weather.enabled.label")
      description: I18n.tr("settings.location.weather.enabled.description")
      checked: Settings.data.location.weatherEnabled
      onToggled: checked => Settings.data.location.weatherEnabled = checked
      isSettings: true
      defaultValue: Settings.getDefaultValue("location.weatherEnabled")
    }

    NToggle {
      label: I18n.tr("settings.location.weather.fahrenheit.label")
      description: I18n.tr("settings.location.weather.fahrenheit.description")
      checked: Settings.data.location.useFahrenheit
      onToggled: checked => Settings.data.location.useFahrenheit = checked
      enabled: Settings.data.location.weatherEnabled
    }

    NToggle {
      label: I18n.tr("settings.location.weather.show-effects.label")
      description: I18n.tr("settings.location.weather.show-effects.description")
      checked: Settings.data.location.weatherShowEffects
      onToggled: checked => Settings.data.location.weatherShowEffects = checked
      enabled: Settings.data.location.weatherEnabled
    }

    NToggle {
      label: I18n.tr("settings.location.weather.hide-city.label")
      description: I18n.tr("settings.location.weather.hide-city.description")
      checked: Settings.data.location.hideWeatherCityName
      onToggled: checked => Settings.data.location.hideWeatherCityName = checked
      enabled: Settings.data.location.weatherEnabled
    }

    NToggle {
      label: I18n.tr("settings.location.weather.hide-timezone.label")
      description: I18n.tr("settings.location.weather.hide-timezone.description")
      checked: Settings.data.location.hideWeatherTimezone
      onToggled: checked => Settings.data.location.hideWeatherTimezone = checked
      enabled: Settings.data.location.weatherEnabled
    }
  }
}
