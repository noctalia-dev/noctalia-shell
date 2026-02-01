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

  // Language
  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("panels.general.language-select-label")
    description: I18n.tr("panels.general.language-select-description")
    defaultValue: Settings.getDefaultValue("general.language")
    model: [
      {
        "key": "",
        "name": I18n.tr("panels.general.language-select-auto-detect") + " (" + I18n.systemDetectedLangCode + ")"
      }
    ].concat(I18n.availableLanguages.map(function (langCode) {
      return {
        "key": langCode,
        "name": langCode
      };
    }))
    currentKey: Settings.data.general.language
    settingsPath: "general.language"
    onSelected: key => {
                  // Need to change language on next frame using "callLater" or it will pull the rug below our feet: the NComboBox would be rebuilt immediately before it can close properly.
                  Qt.callLater(() => {
                                 Settings.data.general.language = key;
                                 if (key === "") {
                                   I18n.detectLanguage(); // Re-detect system language if "Automatic" is selected
                                 } else {
                                   I18n.setLanguage(key); // Set specific language
                                 }
                               });
                }
  }

  NDivider {
    Layout.fillWidth: true
  }

  // Location
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NTextInput {
      Layout.maximumWidth: root.width / 2

      label: I18n.tr("panels.location.location-search-label")
      description: I18n.tr("panels.location.location-search-description")
      text: Settings.data.location.name || Settings.defaultLocation
      placeholderText: I18n.tr("panels.location.location-search-placeholder")
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
    }
  }

  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NToggle {
      label: I18n.tr("panels.location.weather-enabled-label")
      description: I18n.tr("panels.location.weather-enabled-description")
      checked: Settings.data.location.weatherEnabled
      onToggled: checked => Settings.data.location.weatherEnabled = checked
      defaultValue: Settings.getDefaultValue("location.weatherEnabled")
    }

    NToggle {
      label: I18n.tr("panels.location.weather-fahrenheit-label")
      description: I18n.tr("panels.location.weather-fahrenheit-description")
      checked: Settings.data.location.useFahrenheit
      onToggled: checked => Settings.data.location.useFahrenheit = checked
      enabled: Settings.data.location.weatherEnabled
    }

    NToggle {
      label: I18n.tr("panels.location.weather-show-effects-label")
      description: I18n.tr("panels.location.weather-show-effects-description")
      checked: Settings.data.location.weatherShowEffects
      onToggled: checked => Settings.data.location.weatherShowEffects = checked
      enabled: Settings.data.location.weatherEnabled
    }

    NToggle {
      label: I18n.tr("panels.location.weather-hide-city-label")
      description: I18n.tr("panels.location.weather-hide-city-description")
      checked: Settings.data.location.hideWeatherCityName
      onToggled: checked => Settings.data.location.hideWeatherCityName = checked
      enabled: Settings.data.location.weatherEnabled
    }

    NToggle {
      label: I18n.tr("panels.location.weather-hide-timezone-label")
      description: I18n.tr("panels.location.weather-hide-timezone-description")
      checked: Settings.data.location.hideWeatherTimezone
      onToggled: checked => Settings.data.location.hideWeatherTimezone = checked
      enabled: Settings.data.location.weatherEnabled
    }
  }
}
