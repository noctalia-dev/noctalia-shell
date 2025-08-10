import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Settings
import qs.Components
import "../../Helpers/Weather.js" as WeatherHelper

Rectangle {
    id: weatherRoot
    width: 440 * Theme.scale(Screen)
    height: 180 * Theme.scale(Screen)
    color: "transparent"
    anchors.horizontalCenterOffset: -2

    property string city: Settings.settings.weatherCity !== undefined ? Settings.settings.weatherCity : ""
    property var weatherData: null
    property string errorString: ""
    property bool isVisible: false
    property int lastFetchTime: 0
    property bool isLoading: false

    // Auto-refetch weather when city changes
    Connections {
        target: Settings.settings
        function onWeatherCityChanged() {
            if (weatherRoot.isVisible && weatherRoot.city !== "") {
                // Force refresh when city changes
                weatherRoot.lastFetchTime = 0;
                weatherRoot.fetchCityWeather();
            }
        }
    }

    Component.onCompleted: {
        if (weatherRoot.isVisible) {
            weatherRoot.fetchCityWeather();
        }
    }

    function fetchCityWeather() {
        if (!city || city.trim() === "") {
            weatherRoot.errorString = "No city configured";
            return;
        }

        // Check if we should fetch new data (avoid fetching too frequently)
        const currentTime = Date.now();
        const timeSinceLastFetch = currentTime - weatherRoot.lastFetchTime;

        // Only skip if we have recent data AND lastFetchTime is not 0 (initial state)
        if (weatherRoot.lastFetchTime > 0 && timeSinceLastFetch < 60000) {
            // 1 minute
            return; // Skip if last fetch was less than 1 minute ago
        }

        weatherRoot.isLoading = true;
        weatherRoot.errorString = "";

        if (Settings.settings.autoDetectWeather) {
            weatherRoot.city = "Auto-Detect";   
        }

        WeatherHelper.fetchCityWeather(city, Settings.settings.autoDetectWeather).then(function (result) {
            weatherData = result.weather;
            weatherRoot.city = result.city;
            weatherRoot.lastFetchTime = currentTime;
            weatherRoot.errorString = "";
            weatherRoot.isLoading = false;
        }).catch(function (err) {
            weatherRoot.errorString = err;
            weatherRoot.isLoading = false;
        });
    }

    function startWeatherFetch() {
        weatherRoot.isVisible = true;
        // Force refresh when panel opens, regardless of time check
        weatherRoot.lastFetchTime = 0;
        weatherRoot.fetchCityWeather();
    }

    function stopWeatherFetch() {
        weatherRoot.isVisible = false;
    }

    Rectangle {
        id: card
        anchors.fill: parent
        color: Theme.surface
        radius: 18 * Theme.scale(Screen)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18 * Theme.scale(Screen)
            spacing: 12 * Theme.scale(Screen)

            RowLayout {
                spacing: 12 * Theme.scale(Screen)
                Layout.fillWidth: true

                RowLayout {
                    spacing: 12 * Theme.scale(Screen)
                    Layout.preferredWidth: 140 * Theme.scale(Screen)

                    Spinner {
                        id: loadingSpinner
                        running: weatherRoot.isLoading
                        color: Theme.accentPrimary
                        size: 28 * Theme.scale(Screen)
                        Layout.alignment: Qt.AlignVCenter
                        visible: weatherRoot.isLoading
                    }

                    Text {
                        id: weatherIcon
                        visible: !weatherRoot.isLoading
                        text: weatherRoot.weatherData && weatherRoot.weatherData.current_weather ? materialSymbolForCode(weatherRoot.weatherData.current_weather.weathercode) : "cloud"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 28 * Theme.scale(Screen)
                        verticalAlignment: Text.AlignVCenter
                        color: Theme.accentPrimary
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        spacing: 2 * Theme.scale(Screen)
                        RowLayout {
                            spacing: 4 * Theme.scale(Screen)
                            Text {
                                text: weatherRoot.city
                                font.family: Theme.fontFamily
                                font.pixelSize: 14 * Theme.scale(Screen)
                                font.bold: true
                                color: Theme.textPrimary
                            }
                            Text {
                                text: weatherRoot.weatherData && weatherRoot.weatherData.timezone_abbreviation ? `(${weatherRoot.weatherData.timezone_abbreviation})` : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 10 * Theme.scale(Screen)
                                color: Theme.textSecondary
                                leftPadding: 2 * Theme.scale(Screen)
                            }
                        }
                        Text {
                            text: weatherRoot.weatherData && weatherRoot.weatherData.current_weather ? ((Settings.settings.useFahrenheit !== undefined ? Settings.settings.useFahrenheit : false) ? `${Math.round(weatherRoot.weatherData.current_weather.temperature * 9 / 5 + 32)}°F` : `${Math.round(weatherRoot.weatherData.current_weather.temperature)}°C`) : ((Settings.settings.useFahrenheit !== undefined ? Settings.settings.useFahrenheit : false) ? "--°F" : "--°C")
                            font.family: Theme.fontFamily
                            font.pixelSize: 24 * Theme.scale(Screen)
                            font.bold: true
                            color: Theme.textPrimary
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                width: parent.width
                height: 1 * Theme.scale(Screen)
                color: Qt.rgba(Theme.textSecondary.g, Theme.textSecondary.g, Theme.textSecondary.b, 0.12)
                Layout.fillWidth: true
                Layout.topMargin: 2 * Theme.scale(Screen)
                Layout.bottomMargin: 2 * Theme.scale(Screen)
            }

            RowLayout {
                spacing: 12 * Theme.scale(Screen)
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                visible: weatherRoot.weatherData && weatherRoot.weatherData.daily && weatherRoot.weatherData.daily.time

                Repeater {
                    model: weatherRoot.weatherData && weatherRoot.weatherData.daily && weatherRoot.weatherData.daily.time ? 5 : 0
                    delegate: ColumnLayout {
                        spacing: 2 * Theme.scale(Screen)
                        Layout.alignment: Qt.AlignHCenter
                        Text {

                            text: Qt.formatDateTime(new Date(weatherRoot.weatherData.daily.time[index]), "ddd")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12 * Theme.scale(Screen)
                            color: Theme.textSecondary
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Text {

                            text: materialSymbolForCode(weatherRoot.weatherData.daily.weathercode[index])
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 22 * Theme.scale(Screen)
                            color: Theme.accentPrimary
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Text {

                            text: weatherRoot.weatherData && weatherRoot.weatherData.daily ? ((Settings.settings.useFahrenheit !== undefined ? Settings.settings.useFahrenheit : false) ? `${Math.round(weatherRoot.weatherData.daily.temperature_2m_max[index] * 9 / 5 + 32)}° / ${Math.round(weatherRoot.weatherData.daily.temperature_2m_min[index] * 9 / 5 + 32)}°` : `${Math.round(weatherRoot.weatherData.daily.temperature_2m_max[index])}° / ${Math.round(weatherRoot.weatherData.daily.temperature_2m_min[index])}°`) : ((Settings.settings.useFahrenheit !== undefined ? Settings.settings.useFahrenheit : false) ? "--° / --°" : "--° / --°")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12 * Theme.scale(Screen)
                            color: Theme.textPrimary
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }

            Text {
                text: weatherRoot.errorString
                color: Theme.error
                visible: weatherRoot.errorString !== ""
                font.family: Theme.fontFamily
                font.pixelSize: 10 * Theme.scale(Screen)
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    function materialSymbolForCode(code) {
        if (code === 0)
            return "sunny";
        if (code === 1 || code === 2)
            return "partly_cloudy_day";
        if (code === 3)
            return "cloud";
        if (code >= 45 && code <= 48)
            return "foggy";
        if (code >= 51 && code <= 67)
            return "rainy";
        if (code >= 71 && code <= 77)
            return "weather_snowy";
        if (code >= 80 && code <= 82)
            return "rainy";
        if (code >= 95 && code <= 99)
            return "thunderstorm";
        return "cloud";
    }
    function weatherDescriptionForCode(code) {
        if (code === 0)
            return "Clear sky";
        if (code === 1)
            return "Mainly clear";
        if (code === 2)
            return "Partly cloudy";
        if (code === 3)
            return "Overcast";
        if (code === 45 || code === 48)
            return "Fog";
        if (code >= 51 && code <= 67)
            return "Drizzle";
        if (code >= 71 && code <= 77)
            return "Snow";
        if (code >= 80 && code <= 82)
            return "Rain showers";
        if (code >= 95 && code <= 99)
            return "Thunderstorm";
        return "Unknown";
    }
}
